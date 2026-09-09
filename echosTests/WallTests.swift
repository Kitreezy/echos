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
