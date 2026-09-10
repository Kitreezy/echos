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

    /// Чья стена открыта — адрес владельца. `nil` — своя.
    let owner: String?

    private(set) var strokes: [Stroke] = []

    /// Росчерк, который рисуется прямо сейчас. Отдельно от `strokes`, чтобы
    /// не перекладывать массив на каждое движение пальца.
    private(set) var pending: Stroke?

    private let transport: any PeerTransport
    private let store: any StrokeStoring

    private var incomingTask: Task<Void, Never>?
    private var wallStateTask: Task<Void, Never>?

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
        await reconcileWithOwner()
    }

    func stop() {
        incomingTask?.cancel()
        incomingTask = nil

        wallStateTask?.cancel()
        wallStateTask = nil
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

            for await incoming in strokes {
                await self?.receive(incoming.value.by(incoming.sender))
            }
        }
    }

    // MARK: - Сведение с владельцем

    /// Спросить у владельца, как его стена выглядит на самом деле.
    ///
    /// До этого две копии жили порознь и никогда не сверялись: росчерк,
    /// отправленный владельцу в офлайне, релей выбрасывал, у вас он оставался,
    /// а у него не появлялся никогда. И чужого на его стене вы не видели вовсе
    /// — в вашей копии лежали только собственные штрихи.
    ///
    /// Владелец — источник правды. Своя стена сверки не требует: правда и так
    /// здесь.
    private func reconcileWithOwner() async {
        guard let owner else {
            return
        }

        do {
            try await transport.requestWall(from: owner)
        }
        catch {
            // Владельца нет рядом — сверимся в следующий раз. Локальная копия
            // при этом остаётся: терять нарисованное из-за его отсутствия
            // было бы хуже, чем показать её неполной.
            print("[WallViewModel] Owner is away, wall not reconciled: \(error)")
            return
        }

        await awaitWallState(from: owner)
    }

    /// Дождаться ответа и свести обе копии.
    private func awaitWallState(from owner: String) async {
        let states = transport.wallStateStream

        wallStateTask = Task { [weak self] in
            for await incoming in states where incoming.sender == owner {
                await self?.merge(incoming.value, from: owner)
                return  // ответ приходит один
            }
        }
    }

    /// Объединить свою копию с копией владельца.
    ///
    /// Объединить, а не заменить: у владельца может не быть штрихов, которые
    /// вы нарисовали, пока его не было. Их же после сверки и досылаем — так
    /// стена сходится сама, без подтверждений и очередей.
    private func merge(_ theirs: [Stroke], from owner: String) async {
        let ownersIDs = Set(theirs.map(\.id))
        let missing = strokes.filter { $0.author == transport.myAddress
            && !ownersIDs.contains($0.id) }

        let known = Set(strokes.map(\.id))
        let arrived = theirs.filter { !known.contains($0.id) }

        strokes = (strokes + arrived).sorted { $0.createdAt < $1.createdAt }

        do {
            for stroke in arrived {
                try await store.saveStroke(stroke, wallOwner: owner)
            }

            for stroke in missing {
                try await transport.sendStroke(stroke, to: owner)
            }
        }
        catch {
            print("[WallViewModel] Failed to merge wall: \(error)")
        }

        if !arrived.isEmpty || !missing.isEmpty {
            print("[WallViewModel] Wall reconciled: +\(arrived.count) received, "
                  + "\(missing.count) resent")
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
        pending = Stroke(author: transport.myAddress, points: [point])
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
        guard let owner else {
            return
        }

        do {
            try await transport.sendStroke(stroke, to: owner)
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
