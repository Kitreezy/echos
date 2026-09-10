//
//  WallTests.swift
//  echosTests
//
//  Стена: рисование, отправка, приём, хранение.
//

import XCTest
@testable import echos

@MainActor
final class WallTests: XCTestCase {

    private var transport: LoopbackTransport!
    private var store: SpyStrokeStore!

    override func setUp() async throws {
        try await super.setUp()
        transport = LoopbackTransport()
        store = SpyStrokeStore()
    }

    private func makeWall(owner: String?) -> WallViewModel {
        WallViewModel(owner: owner, transport: transport, store: store)
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

    func test_stroke_isKeptAndSaved() async {
        let wall = makeWall(owner: "Bob")

        await draw(wall, points: 5)

        XCTAssertEqual(wall.strokes.count, 1)
        XCTAssertEqual(store.saved.count, 1)
        XCTAssertEqual(store.saved.first?.wallOwner, "Bob")
    }

    /// Случайное касание не должно оставлять точку на чужой стене.
    func test_singleTap_leavesNothing() async {
        let wall = makeWall(owner: "Bob")

        wall.beginStroke(at: .init(x: 0.5, y: 0.5))
        await wall.endStroke()

        XCTAssertTrue(wall.strokes.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertNil(wall.pending)
    }

    // MARK: - Отправка

    /// Росчерк адресный: он предназначен владельцу стены, а не всем вокруг.
    func test_strokeOnSomeoneElsesWall_isSentToThatPeer() async {
        let wall = makeWall(owner: "Bob")

        await draw(wall, points: 3)

        XCTAssertEqual(transport.sentStrokes.count, 1)
        XCTAssertEqual(transport.sentStrokes.first?.recipient, "Bob")
    }

    /// На своей стене рисуют для себя — отправлять некому.
    func test_strokeOnOwnWall_isNotSent() async {
        let wall = makeWall(owner: nil)

        await draw(wall, points: 3)

        XCTAssertTrue(transport.sentStrokes.isEmpty)
        XCTAssertEqual(wall.strokes.count, 1)
    }

    // MARK: - Приём

    func test_incomingStroke_appearsOnOwnWall() async {
        let wall = await started(makeWall(owner: nil))
        defer { wall.stop() }

        transport.emit(stroke: Stroke(author: "Bob", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))

        let received = await waitUntil { wall.strokes.count == 1 }

        XCTAssertTrue(received)
        XCTAssertEqual(wall.strokes.first?.author, "Bob")
        XCTAssertTrue(store.saved.isEmpty, "Сохраняет ChatViewModel, а не открытый экран")
    }

    /// После переподключения тот же росчерк может прийти снова.
    func test_repeatedStroke_isIgnored() async {
        let wall = await started(makeWall(owner: nil))
        defer { wall.stop() }

        let stroke = Stroke(author: "Bob", points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])

        transport.emit(stroke: stroke)
        _ = await waitUntil { wall.strokes.count == 1 }

        transport.emit(stroke: stroke)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(wall.strokes.count, 1)
    }

    /// Чужая стена — не почтовый ящик: там показывают только своё.
    func test_someoneElsesWall_doesNotReceiveStrokes() async {
        let wall = makeWall(owner: "Bob")
        await wall.start()
        defer { wall.stop() }

        transport.emit(stroke: Stroke(author: "Carol", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(wall.strokes.isEmpty)
    }

    // MARK: - История и очистка

    func test_start_loadsHistory() async {
        store.preloaded = [Stroke(author: "Bob", points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])]

        let wall = makeWall(owner: nil)
        await wall.start()
        defer { wall.stop() }

        XCTAssertEqual(wall.strokes.count, 1)
    }

    func test_clear_emptiesWall() async {
        let wall = makeWall(owner: "Bob")
        await draw(wall, points: 4)

        await wall.clear()

        XCTAssertTrue(wall.strokes.isEmpty)
        XCTAssertTrue(wall.isEmpty)
    }

    // MARK: - Координаты

    /// Точки хранятся в долях: на экране другого размера рисунок не должен съезжать.
    func test_points_areRelativeToCanvas() {
        let small = CGSize(width: 100, height: 200)
        let large = CGSize(width: 300, height: 600)

        let point = Stroke.Point(CGPoint(x: 50, y: 100), in: small)

        XCTAssertEqual(point.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(point.cgPoint(in: large).x, 150, accuracy: 0.001)
        XCTAssertEqual(point.cgPoint(in: large).y, 300, accuracy: 0.001)
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

    func test_openingSomeoneElsesWall_asksTheOwnerForIt() async {
        _ = await started(makeWall(owner: "Bob"))

        XCTAssertEqual(transport.wallRequests, ["Bob"])
    }

    /// Своя стена и есть источник правды — спрашивать некого.
    func test_openingOwnWall_asksNobody() async {
        _ = await started(makeWall(owner: nil))

        XCTAssertTrue(transport.wallRequests.isEmpty)
    }

    /// Раньше в чужой стене лежали только собственные штрихи: то, что нарисовали
    /// там другие, не приходило никогда.
    func test_ownersWall_bringsInStrokesDrawnByOthers() async {
        let wall = await started(makeWall(owner: "Bob"))
        let byCarol = stroke(author: "Carol", at: 1)

        transport.emit(wall: [byCarol], from: "Bob")
        _ = await waitUntil { !wall.strokes.isEmpty }

        XCTAssertEqual(wall.strokes.map(\.author), ["Carol"])
        XCTAssertEqual(store.saved.map(\.wallOwner), ["Bob"],
                       "Пришедшее с чужой стены сохраняется под её владельцем")
    }

    /// Ключевой случай: рисовали, пока владельца не было, и релей это выбросил.
    func test_strokeTheOwnerNeverGot_isResentOnReconcile() async {
        let wall = await started(makeWall(owner: "Bob"))
        await draw(wall, points: 5)

        let mine = try? XCTUnwrap(wall.strokes.first)
        transport.clearSentStrokes()

        // У владельца этого штриха нет.
        transport.emit(wall: [], from: "Bob")
        _ = await waitUntil { !self.transport.sentStrokes.isEmpty }

        XCTAssertEqual(transport.sentStrokes.map(\.recipient), ["Bob"])
        XCTAssertEqual(transport.sentStrokes.first?.stroke.id, mine?.id)
    }

    func test_strokeTheOwnerAlreadyHas_isNotResent() async {
        let wall = await started(makeWall(owner: "Bob"))
        await draw(wall, points: 5)

        guard let mine = wall.strokes.first else {
            return XCTFail("Росчерк не нарисовался")
        }
        transport.clearSentStrokes()

        transport.emit(wall: [mine], from: "Bob")
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(transport.sentStrokes.isEmpty)
    }

    func test_reconcile_doesNotDuplicateWhatWeAlreadyHave() async {
        let wall = await started(makeWall(owner: "Bob"))
        let shared = stroke(author: "Carol", at: 1)

        transport.emit(wall: [shared], from: "Bob")
        _ = await waitUntil { !wall.strokes.isEmpty }

        transport.emit(wall: [shared], from: "Bob")
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(wall.strokes.count, 1)
    }

    /// Владельца нет рядом — стена всё равно открывается тем, что есть.
    /// Терять нарисованное из-за его отсутствия было бы хуже.
    func test_absentOwner_leavesTheLocalCopyAlone() async {
        store.preloaded = [stroke(author: "me", at: 1)]
        transport.unreachableOwners = ["Bob"]

        let wall = await started(makeWall(owner: "Bob"))

        XCTAssertEqual(wall.strokes.count, 1)
    }

    /// Ответ чужого человека к нашей стене отношения не имеет.
    func test_wallStateFromSomeoneElse_isIgnored() async {
        let wall = await started(makeWall(owner: "Bob"))

        transport.emit(wall: [stroke(author: "Carol", at: 1)], from: "Carol")
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(wall.strokes.isEmpty)
    }
}

// MARK: - Приём при закрытой стене

@MainActor
final class WallDeliveryTests: XCTestCase {

    /// Главное свойство стены: след остаётся, даже когда её никто не смотрит.
    func test_strokeArrivingWithWallClosed_isStillSaved() async {
        let transport = LoopbackTransport()
        let strokes = SpyStrokeStore()

        let chat = ChatViewModel()
        chat.initialize(transport: transport, store: SpyMessageStore(), strokes: strokes)

        _ = await waitUntil { transport.strokeSubscriberCount > 0 }

        transport.emit(stroke: Stroke(author: "Bob", points: [
            .init(x: 0, y: 0), .init(x: 1, y: 1)
        ]))

        let saved = await waitUntil { strokes.saved.count == 1 }

        XCTAssertTrue(saved, "Экран стены не открыт, но росчерк должен сохраниться")
        XCTAssertEqual(strokes.saved.first?.wallOwner, nil)
        XCTAssertEqual(strokes.saved.first?.stroke.author, "Bob")
    }
}
