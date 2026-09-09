//
//  KnownPeerStoring.swift
//  echos
//
//  Абстракция над списком знакомых — тот же шов, что у сообщений и росчерков.
//

import Foundation

@MainActor
protocol KnownPeerStoring: AnyObject {

    func loadKnownPeers() async throws -> [KnownPeer]

    /// Запомнить собеседника под этим именем.
    ///
    /// Повторный вызов обновляет имя: значит, вы с ним разговаривали уже
    /// после переименования и приняли новое имя как своё.
    func remember(address: String, name: String) async throws

    func forgetAll() async throws
}

extension KnownPeerStore: KnownPeerStoring {}
