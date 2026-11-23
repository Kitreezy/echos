//
//  DeviceIdentityStore.swift
//  echos
//
//  Загрузка личности устройства из Keychain. Пакет EchosCrypto хранением
//  не занимается: приложение решает, где и как переживает перезапуски пара
//  ключей, а пакету отдаёт уже готовую личность.
//

import EchosCrypto

extension DeviceIdentity {

    /// Личность этого устройства: из Keychain, а при первом обращении —
    /// созданная и сразу туда записанная.
    static func current() throws -> DeviceIdentity {
        try store.identity()
    }

    private static let store = IdentityStore(store: KeychainSecretStore(service: "com.echos.identity"))
}
