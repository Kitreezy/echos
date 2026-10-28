//
//  WallTests.swift
//  echosTests
//
//  Стена: рисование, отправка, приём, хранение.
//

import Foundation
import Testing
@testable import echos

@MainActor
struct WallTests {

    private let transport = LoopbackTransport()
    private let store = SpyStrokeStore()

    /// Свой центр уведомлений: в общий соседние тесты шлют «изменения из
    /// iCloud», и стена перечитывалась бы посреди проверки.
    private func makeWall(owner: String?) -> WallViewModel {
        WallViewModel(owner: owner, transport: transport, store: store, notificationCenter: NotificationCenter())
    }

    /// Запускает стену и дожидается, пока она встанет на поток росчерков.
    private func started(_ wall: WallViewModel) async -> WallViewModel {
        await wall.start()
        _ = await waitUntil { self.transport.strokeSubscriberCount > 0 }
        return wall
    }

    private func draw(_ wall: WallViewModel, points: Int) async {
        wall.beginStroke(at: .init(x: 0, y: 0))
        for i in 1..<max(points, 1) {
            wall.extendStroke(to: .init(x: Double(i) / 10, y: Double(i) / 10))
        }
        await wall.endStroke()
    }

    // MARK: - Рисование

    @Test func stroke_isKeptAndSaved() async {
        let wall = makeWall(owner: "Bob")

        await draw(wall, points: 5)

        #expect(wall.strokes.count == 1)
        #expect(store.saved.count == 1)
        #expect(store.saved.first?.wallOwner == "Bob")
    }

    /// Случайное касание не должно оставлять точку на чужой стене.
    @Test func singleTap_leavesNothing() async {
        let wall = makeWall(owner: "Bob")

        wall.beginStroke(at: .init(x: 0.5, y: 0.5))
        await wall.endStroke()

        #expect(wall.strokes.isEmpty)
        #expect(store.saved.isEmpty)
        #expect(wall.pending == nil)
    }

    // MARK: - Отправка

    /// Росчерк адресный: он предназначен владельцу стены, а не всем вокруг.
    @Test func strokeOnSomeoneElsesWall_isSentToThatPeer() async {
        let wall = makeWall(owner: "Bob")

        await draw(wall, points: 3)

        #expect(transport.sentStrokes.count == 1)
        #expect(transport.sentStrokes.first?.recipient == "Bob")
    }

    /// На своей стене рисуют для себя — отправлять некому.
    @Test func strokeOnOwnWall_isNotSent() async {
        let wall = makeWall(owner: nil)

        await draw(wall, points: 3)

        #expect(transport.sentStrokes.isEmpty)
        #expect(wall.strokes.count == 1)
    }

    // MARK: - Приём

    @Test func incomingStroke_appearsOnOwnWall() async {
        let wall = await started(makeWall(owner: nil))
        defer { wall.stop() }

        transport.emit(stroke: Stroke(author: "Bob", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))

        let received = await waitUntil { wall.strokes.count == 1 }

        #expect(received)
        #expect(wall.strokes.first?.author == "Bob")
        #expect(store.saved.isEmpty, "Сохраняет ChatViewModel, а не открытый экран")
    }

    /// После переподключения тот же росчерк может прийти снова.
    @Test func repeatedStroke_isIgnored() async {
        let wall = await started(makeWall(owner: nil))
        defer { wall.stop() }

        let stroke = Stroke(author: "Bob", points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])

        transport.emit(stroke: stroke)
        _ = await waitUntil { wall.strokes.count == 1 }

        transport.emit(stroke: stroke)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(wall.strokes.count == 1)
    }

    /// Чужая стена — не почтовый ящик: там показывают только своё.
    @Test func someoneElsesWall_doesNotReceiveStrokes() async {
        let wall = makeWall(owner: "Bob")
        await wall.start()
        defer { wall.stop() }

        transport.emit(stroke: Stroke(author: "Carol", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))
        try? await Task.sleep(for: .milliseconds(200))

        #expect(wall.strokes.isEmpty)
    }

    // MARK: - История и очистка

    @Test func start_loadsHistory() async {
        store.preloaded = [Stroke(author: "Bob", points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])]

        let wall = makeWall(owner: nil)
        await wall.start()
        defer { wall.stop() }

        #expect(wall.strokes.count == 1)
    }

    @Test func clear_emptiesWall() async {
        let wall = makeWall(owner: "Bob")
        await draw(wall, points: 4)

        await wall.clear()

        #expect(wall.strokes.isEmpty)
        #expect(wall.isEmpty)
    }

    // MARK: - Координаты

    /// Точки хранятся в долях: на экране другого размера рисунок не должен съезжать.
    @Test func points_areRelativeToCanvas() {
        let small = CGSize(width: 100, height: 200)
        let large = CGSize(width: 300, height: 600)

        let point = Stroke.Point(CGPoint(x: 50, y: 100), in: small)

        #expect(abs((point.x) - (0.5)) <= 0.001)
        #expect(abs((point.y) - (0.5)) <= 0.001)
        #expect(abs((point.cgPoint(in: large).x) - (150)) <= 0.001)
        #expect(abs((point.cgPoint(in: large).y) - (300)) <= 0.001)
    }

    // MARK: - Сведение с владельцем

    private func stroke(_ id: UUID = UUID(),
                        author: String,
                        at second: TimeInterval = 0) -> Stroke {
        Stroke(id: id,
               author: author,
               points: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.5)],
               createdAt: Date(timeIntervalSince1970: second))
    }

    @Test func openingSomeoneElsesWall_asksTheOwnerForIt() async {
        _ = await started(makeWall(owner: "Bob"))

        #expect(transport.wallRequests == ["Bob"])
    }

    /// Своя стена и есть источник правды — спрашивать некого.
    @Test func openingOwnWall_asksNobody() async {
        _ = await started(makeWall(owner: nil))

        #expect(transport.wallRequests.isEmpty)
    }

    /// Раньше в чужой стене лежали только собственные штрихи: то, что нарисовали
    /// там другие, не приходило никогда.
    @Test func ownersWall_bringsInStrokesDrawnByOthers() async {
        let wall = await started(makeWall(owner: "Bob"))
        let byCarol = stroke(author: "Carol", at: 1)

        transport.emit(wall: [byCarol], from: "Bob")
        _ = await waitUntil { !wall.strokes.isEmpty }

        #expect(wall.strokes.map(\.author) == ["Carol"])
        #expect(store.saved.map(\.wallOwner) == ["Bob"], "Пришедшее с чужой стены сохраняется под её владельцем")
    }

    /// Ключевой случай: рисовали, пока владельца не было, и релей это выбросил.
    @Test func strokeTheOwnerNeverGot_isResentOnReconcile() async {
        let wall = await started(makeWall(owner: "Bob"))
        await draw(wall, points: 5)

        let mine = try? #require(wall.strokes.first)
        transport.clearSentStrokes()

        // У владельца этого штриха нет.
        transport.emit(wall: [], from: "Bob")
        _ = await waitUntil { !self.transport.sentStrokes.isEmpty }

        #expect(transport.sentStrokes.map(\.recipient) == ["Bob"])
        #expect(transport.sentStrokes.first?.stroke.id == mine?.id)
    }

    @Test func strokeTheOwnerAlreadyHas_isNotResent() async throws {
        let wall = await started(makeWall(owner: "Bob"))
        await draw(wall, points: 5)

        let mine = try #require(wall.strokes.first, "Росчерк не нарисовался")
        transport.clearSentStrokes()

        transport.emit(wall: [mine], from: "Bob")
        try? await Task.sleep(for: .milliseconds(200))

        #expect(transport.sentStrokes.isEmpty)
    }

    @Test func reconcile_doesNotDuplicateWhatWeAlreadyHave() async {
        let wall = await started(makeWall(owner: "Bob"))
        let shared = stroke(author: "Carol", at: 1)

        transport.emit(wall: [shared], from: "Bob")
        _ = await waitUntil { !wall.strokes.isEmpty }

        transport.emit(wall: [shared], from: "Bob")
        try? await Task.sleep(for: .milliseconds(200))

        #expect(wall.strokes.count == 1)
    }

    /// Владельца нет рядом — стена всё равно открывается тем, что есть.
    /// Терять нарисованное из-за его отсутствия было бы хуже.
    @Test func absentOwner_leavesTheLocalCopyAlone() async {
        store.preloaded = [stroke(author: "me", at: 1)]
        transport.unreachableOwners = ["Bob"]

        let wall = await started(makeWall(owner: "Bob"))

        #expect(wall.strokes.count == 1)
    }

    /// Ответ чужого человека к нашей стене отношения не имеет.
    @Test func wallStateFromSomeoneElse_isIgnored() async {
        let wall = await started(makeWall(owner: "Bob"))

        transport.emit(wall: [stroke(author: "Carol", at: 1)], from: "Carol")
        try? await Task.sleep(for: .milliseconds(200))

        #expect(wall.strokes.isEmpty)
    }
}

// MARK: - Приём при закрытой стене

@MainActor
struct WallDeliveryTests {

    /// Главное свойство стены: след остаётся, даже когда её никто не смотрит.
    @Test func strokeArrivingWithWallClosed_isStillSaved() async {
        let transport = LoopbackTransport()
        let strokes = SpyStrokeStore()

        let chat = ChatViewModel()
        chat.initialize(transport: transport, store: SpyMessageStore(), strokes: strokes)

        _ = await waitUntil { transport.strokeSubscriberCount > 0 }

        transport.emit(stroke: Stroke(author: "Bob", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))

        let saved = await waitUntil { strokes.saved.count == 1 }

        #expect(saved, "Экран стены не открыт, но росчерк должен сохраниться")
        #expect(strokes.saved.first?.wallOwner == nil)
        #expect(strokes.saved.first?.stroke.author == "Bob")
    }
}
