//
//  PeerRecognitionTests.swift
//  echosTests
//
//  Узнавание собеседника по адресу.
//

import Foundation
import Testing
@testable import echos

struct PeerRecognitionTests {

    private func known(_ address: String, _ name: String) -> KnownPeer {
        KnownPeer(address: address, name: name, firstSeen: Date(), lastSeen: Date())
    }

    // MARK: - Знакомый

    @Test func sameAddressAndName_isKnown() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        #expect(recognizer.recognize(address: "a1b2", name: "Bob") == .known)
    }

    @Test func knownPeer_hasNothingToSay() {
        #expect(PeerRecognition.known.note == nil)
        #expect(!PeerRecognition.known.deservesAttention)
    }

    // MARK: - Переименование

    @Test func sameAddressUnderNewName_isRenamed() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        #expect(recognizer.recognize(address: "a1b2", name: "Роберт") == .renamed(from: "Bob"))
    }

    @Test func renamed_saysWhoItWas() {
        #expect(PeerRecognition.renamed(from: "Bob").note == "раньше — Bob")
        #expect(PeerRecognition.renamed(from: "Bob").deservesAttention)
    }

    // MARK: - Тёзка

    /// Ради этого случая всё и делалось: имя знакомое, ключ чужой.
    @Test func knownNameFromAnotherAddress_isNamesake() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        #expect(recognizer.recognize(address: "c3d4", name: "Bob") == .namesake)
    }

    @Test func namesake_deservesAttention() {
        #expect(PeerRecognition.namesake.deservesAttention)
        #expect(PeerRecognition.namesake.note != nil)
    }

    // MARK: - Незнакомец

    @Test func unseenAddressWithUnseenName_isNew() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        #expect(recognizer.recognize(address: "c3d4", name: "Carol") == .new)
    }

    /// Незнакомец — не повод настораживаться, иначе примета обесценится.
    @Test func new_doesNotDeserveAttention() {
        #expect(!PeerRecognition.new.deservesAttention)
    }

    @Test func emptyMemory_makesEveryoneNew() {
        let recognizer = PeerRecognizer(known: [])

        #expect(recognizer.recognize(address: "a1b2", name: "Bob") == .new)
    }

    // MARK: - Через Peer

    @Test func recognizesPeerByAddressNotByName() {
        let recognizer = PeerRecognizer(known: [known("a1b2", "Bob")])

        let real = Peer(address: "a1b2", displayName: "Bob")
        let impostor = Peer(address: "c3d4", displayName: "Bob")

        #expect(recognizer.recognize(real) == .known)
        #expect(recognizer.recognize(impostor) == .namesake)
    }

    /// У Multipeer адресом служит имя, и переименоваться там нельзя:
    /// другое имя — это просто другой адрес.
    @Test func whenAddressIsTheName_renameLooksLikeANewPeer() {
        let recognizer = PeerRecognizer(known: [known("Bob", "Bob")])

        #expect(recognizer.recognize(address: "Роберт", name: "Роберт") == .new)
    }
}
