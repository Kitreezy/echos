//
//  WallViewModel.swift
//  echos
//

import Foundation
import Observation

/// Стена одного собеседника.
///
/// Стен две: своя, на которой рисуют другие, и чужая, на которой рисуете вы.
/// Различает их `owner`: `nil` — своя.
@Observable
@MainActor
final class WallViewModel {

    /// Чья стена открыта. `nil` — своя.
    let owner: String?

    private(set) var strokes: [Stroke] = []

    /// Росчерк, который рисуется прямо сейчас. Отдельно от `strokes`, чтобы
    /// не перекладывать массив на каждое движение пальца.
    private(set) var pending: Stroke?

    private let transport: any PeerTransport
    private let store: any StrokeStoring

    private var incomingTask: Task<Void, Never>?

    init(owner: String?,
         transport: any PeerTransport,
         store: any StrokeStoring = StrokeStore()) {
        self.owner = owner
        self.transport = transport
        self.store = store
    }

    // MARK: - Lifecycle

    func start() async {
        await loadHistory()
        observeIncoming()
    }

    func stop() {
        incomingTask?.cancel()
        incomingTask = nil
    }

    private func loadHistory() async {
        do {
            strokes = try await store.loadStrokes(wallOwner: owner)
        }
        catch {
            print("[WallViewModel] Failed to load wall: \(error)")
        }
    }

    /// Чужие росчерки приходят только на свою стену: рисуют у вас, а не у себя.
    ///
    /// Задача снимается в `stop()` из `onDisappear`, а не в `deinit`:
    /// до изолированного свойства оттуда не дотянуться.
    private func observeIncoming() {
        guard incomingTask == nil, owner == nil else {
            return
        }

        incomingTask = Task { [weak self] in
            guard let strokes = self?.transport.strokeStream else {
                return
            }

            for await stroke in strokes {
                await self?.receive(stroke)
            }
        }
    }

    /// Открытая стена дорисовывает пришедшее сразу. Сохранять не нужно:
    /// это уже сделала `ChatViewModel`, которая слушает поток всегда.
    private func receive(_ stroke: Stroke) async {
        guard !strokes.contains(where: { $0.id == stroke.id }) else {
            return  // повтор после переподключения или уже загружен из истории
        }

        strokes.append(stroke)
    }

    // MARK: - Drawing

    func beginStroke(at point: Stroke.Point) {
        pending = Stroke(author: transport.myDisplayName, points: [point])
    }

    func extendStroke(to point: Stroke.Point) {
        guard let current = pending else {
            return
        }

        pending = Stroke(id: current.id,
                         author: current.author,
                         points: current.points + [point],
                         createdAt: current.createdAt)
    }

    /// Отрыв пальца: росчерк закончен, уходит собеседнику и в хранилище.
    func endStroke() async {
        guard let stroke = pending else {
            return
        }
        pending = nil

        // Точка — это не росчерк. Случайное касание не должно оставлять след.
        guard stroke.points.count > 1 else {
            return
        }

        strokes.append(stroke)

        do {
            try await store.saveStroke(stroke, wallOwner: owner)
        }
        catch {
            print("[WallViewModel] Failed to save stroke: \(error)")
        }

        // На своей стене рисуют для себя — отправлять некому.
        guard owner != nil else {
            return
        }

        do {
            try await transport.sendStroke(stroke)
        }
        catch {
            print("[WallViewModel] Failed to send stroke: \(error)")
        }
    }

    // MARK: - Clearing

    func clear() async {
        strokes = []
        pending = nil

        do {
            try await store.clearWall(owner)
        }
        catch {
            print("[WallViewModel] Failed to clear wall: \(error)")
        }
    }

    var isEmpty: Bool {
        strokes.isEmpty && pending == nil
    }
}
