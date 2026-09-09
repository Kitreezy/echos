//
//  WallView.swift
//  echos
//

import SwiftUI

/// Стена.
///
/// Почти всегда пустая — и это не недоделка, а замысел: кто-то зашёл,
/// оставил след, ушёл. Ни счётчиков, ни отметок «нравится», ни подписей
/// под каждым росчерком.
///
/// Свои росчерки золотом, чужие лиловым — как и в переписке.
struct WallView: View {

    @State var viewModel: WallViewModel
    @State private var canvasSize: CGSize = .zero

    private let ownName: String

    init(viewModel: WallViewModel, ownName: String) {
        _viewModel = State(initialValue: viewModel)
        self.ownName = ownName
    }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            canvas

            if viewModel.isEmpty {
                Text(hint)
                    .font(Font(Typography.caption))
                    .foregroundStyle(Color.inkMuted)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.isEmpty {
                Button("Стереть") {
                    Task { await viewModel.clear() }
                }
                .font(Font(Typography.caption))
                .foregroundStyle(Color.inkMuted)
            }
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for stroke in viewModel.strokes {
                    draw(stroke, in: &context, size: size)
                }

                if let pending = viewModel.pending {
                    draw(pending, in: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(in: geometry.size))
            .onAppear { canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, new in canvasSize = new }
        }
    }

    private func draw(_ stroke: Stroke, in context: inout GraphicsContext, size: CGSize) {
        guard let first = stroke.points.first else {
            return
        }

        var path = Path()
        path.move(to: first.cgPoint(in: size))

        for point in stroke.points.dropFirst() {
            path.addLine(to: point.cgPoint(in: size))
        }

        context.stroke(
            path,
            with: .color(stroke.author == ownName ? Color.own : Color.other),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = Stroke.Point(value.location, in: size)

                if viewModel.pending == nil {
                    viewModel.beginStroke(at: point)
                } else {
                    viewModel.extendStroke(to: point)
                }
            }
            .onEnded { _ in
                Task { await viewModel.endStroke() }
            }
    }

    // MARK: - Texts

    private var title: String {
        viewModel.owner ?? "Моя стена"
    }

    private var hint: String {
        viewModel.owner == nil
            ? "Здесь пусто. Сюда рисуют другие"
            : "Нарисуйте что-нибудь"
    }
}
