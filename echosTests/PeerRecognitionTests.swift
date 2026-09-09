//
//  PeerRecognitionTests.swift
//  echosTests
//
//  Узнавание собеседника по адресу.
//

import XCTest
@testable import echos

final class PeerRecognitionTests: XCTestCase {

    private func known(_ address: String, _ name: String) -> KnownPeer {
        KnownPeer(address: address, name: name, firstSeen: Date(), lastSeen: Date())
    }

    // MARK: - Знакомый

    func test_sameAddressAndName_isKnown() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        XCTAssertEqual(recognizer.recognize(address: "a1b2", name: "Bob"), .known)
    }

    func test_knownPeer_hasNothingToSay() {
        XCTAssertNil(PeerRecognition.known.note)
        XCTAssertFalse(PeerRecognition.known.deservesAttention)
    }

    // MARK: - Переименование

    func test_sameAddressUnderNewName_isRenamed() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        XCTAssertEqual(recognizer.recognize(address: "a1b2", name: "Роберт"),
                       .renamed(from: "Bob"))
    }

    func test_renamed_saysWhoItWas() {
        XCTAssertEqual(PeerRecognition.renamed(from: "Bob").note, "раньше — Bob")
        XCTAssertTrue(PeerRecognition.renamed(from: "Bob").deservesAttention)
    }

    // MARK: - Тёзка

    /// Ради этого случая всё и делалось: имя знакомое, ключ чужой.
    func test_knownNameFromAnotherAddress_isNamesake() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        XCTAssertEqual(recognizer.recognize(address: "c3d4", name: "Bob"), .namesake)
    }

    func test_namesake_deservesAttention() {
        XCTAssertTrue(PeerRecognition.namesake.deservesAttention)
        XCTAssertNotNil(PeerRecognition.namesake.note)
    }

    // MARK: - Незнакомец

    func test_unseenAddressWithUnseenName_isNew() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        XCTAssertEqual(recognizer.recognize(address: "c3d4", name: "Carol"), .new)
    }

    /// Незнакомец — не повод настораживаться, иначе примета обесценится.
    func test_new_doesNotDeserveAttention() {
        XCTAssertFalse(PeerRecognition.new.deservesAttention)
    }

    func test_emptyMemory_makesEveryoneNew() {
        let recognizer = PeerRecognizer(known: [])

        XCTAssertEqual(recognizer.recognize(address: "a1b2", name: "Bob"), .new)
    }

    // MARK: - Через Peer

    func test_recognizesPeerByAddressNotByName() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        let real = Peer(address: "a1b2", displayName: "Bob")
        let impostor = Peer(address: "c3d4", displayName: "Bob")

        XCTAssertEqual(recognizer.recognize(real), .known)
        XCTAssertEqual(recognizer.recognize(impostor), .namesake)
    }

    /// У Multipeer адресом служит имя, и переименоваться там нельзя:
    /// другое имя — это просто другой адрес.
    func test_whenAddressIsTheName_renameLooksLikeANewPeer() {
        let recognizer = PeerRecognizer(known: [known("Bob", "Bob")])

        XCTAssertEqual(recognizer.recognize(address: "Роберт", name: "Роберт"), .new)
    }
}
