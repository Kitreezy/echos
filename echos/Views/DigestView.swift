//
//  DigestView.swift
//  echos
//
//  Что я пропустил: пересказ непрочитанного, составленный на телефоне.
//
//  Пункты появляются по мере того, как модель их пишет, — ждать весь
//  ответ незачем, главное идёт первым.
//

import SwiftUI

struct DigestView: View {

    @State var viewModel: DigestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                content
                Section {
                } footer: {
                    Text("Пересказ составлен на этом телефоне. Переписка никуда не отправлялась. Модель может ошибаться — сверяйтесь с сообщениями.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Пропущенное")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .starting:
            progress("Читаю \(viewModel.messageCount) сообщений от \(viewModel.peerName)…")
        case let .reading(part, total):
            progress("Переписка длинная, читаю частями: \(part) из \(total)…")
        case let .writing(digest):
            sections(of: digest)
            progress("Пишу…")
        case let .done(digest):
            sections(of: digest)
        case let .failed(message):
            Section {
                Label(message, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func sections(of digest: Digest) -> some View {
        items("Главное", digest.points)
        items("Ждут ответа", digest.questions)
        items("Договорились", digest.plans)
    }

    @ViewBuilder
    private func items(_ title: String, _ items: [String]) -> some View {
        // Пустое не показывается: «ждут ответа — ничего» — шум.
        if !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                }
            }
        }
    }

    private func progress(_ text: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(text).foregroundStyle(Color.inkMuted)
            }
        }
    }
}
