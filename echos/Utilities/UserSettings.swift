//
//  UserSettings.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import Foundation

enum UserSettings {
    
    private static let userNameKey = "echos_user_name"
    private static let relayURLKey = "echos_relay_url"
    private static let demoPeersKey = "echos_demo_peers"
    private static let usesRelayKey = "echos_uses_relay"
    private static let mosaicBrushesKey = "echos_mosaic_brushes"
    private static let mosaicDraftsKey = "echos_mosaic_drafts"
    private static let mosaicTemplatesKey = "echos_mosaic_templates"

    /// Куда идти, если человек выбрал дальнюю связь и не назвал свой адрес.
    ///
    /// Зашит в приложение намеренно: спрашивать у человека адрес вебсокета —
    /// значит сделать дальнюю связь доступной только тем, кто знает, что
    /// такое вебсокет.
    static let defaultRelayURL = URL(string: "wss://echos-relay.onrender.com/ws")!
    
    static var userName: String? {
        get {
            UserDefaults.standard.string(forKey: userNameKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userNameKey)
        }
    }
    
    static var hasCompletedOnboarding: Bool {
        userName != nil
    }
    
    /// Идти ли через релей.
    ///
    /// Выключено — работаем через MultipeerConnectivity, то есть только с
    /// теми, кто рядом. Включено — идём через сервер и видим собеседников из
    /// любой сети.
    ///
    /// По умолчанию выключено: echos прежде всего про тех, кто рядом, а
    /// дальняя связь требует интернета и чужого сервера. Это выбор человека,
    /// а не наше решение за него.
    static var usesRelay: Bool {
        get {
            UserDefaults.standard.bool(forKey: usesRelayKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: usesRelayKey)
        }
    }

    /// Свой адрес релея вместо зашитого. Задаётся аргументом запуска в схеме:
    /// `-echos_relay_url ws://имя-мака.local:8080/ws` — так проверяют на
    /// поднятом рядом сервере, не трогая боевой.
    static var relayURL: URL? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: relayURLKey),
                  !raw.isEmpty else {
                return nil
            }
            return URL(string: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: relayURLKey)
        }
    }
    
    /// Показывать выдуманный список устройств, когда рядом никого нет.
    ///
    /// Нужен, чтобы смотреть вёрстку экрана поиска без второго телефона.
    /// В обычном запуске выключен: на боевом релее четыре несуществующих
    /// собеседника выглядят как поломка, а не как демонстрация.
    ///
    /// Включается аргументом запуска в схеме: `-echos_demo_peers YES`.
    static var showsDemoPeers: Bool {
        UserDefaults.standard.bool(forKey: demoPeersKey)
    }
    
    /// Имя, под которым нас видят остальные.
    ///
    /// Запасного варианта из имени устройства здесь больше нет. С iOS 16
    /// `UIDevice.current.name` возвращает не имя из настроек, а модель —
    /// «iPhone» у всех подряд, и весь список собеседников состоял из
    /// одинаковых строк. Имя спрашивается при первом запуске, до того как
    /// начнётся поиск, так что подставлять сюда нечего.
    static var displayName: String {
        guard let name = userName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "Без имени"
        }

        return name
    }
    /// Последние кисти мозаики — эмодзи, которыми рисовали. Восьми хватает,
    /// чтобы не искать в клавиатуре то, чем рисовал минуту назад.
    static var mosaicBrushes: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: mosaicBrushesKey) ?? []
        }
        set {
            UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: mosaicBrushesKey)
        }
    }

    /// Кисть становится первой в ряду; повторы не копятся.
    static func rememberBrush(_ brush: String) {
        guard !brush.isEmpty else {
            return
        }
        mosaicBrushes = [brush] + mosaicBrushes.filter { $0 != brush }
    }

    /// Набросок мозаики в переписке с этим адресом. Начал рисовать, вышел
    /// ответить, вернулся — набросок на месте, даже после перезапуска.
    static func mosaicDraft(for address: String) -> Mosaic? {
        guard let drafts = UserDefaults.standard.dictionary(forKey: mosaicDraftsKey) as? [String: Data],
              let data = drafts[address] else {
            return nil
        }
        return try? JSONDecoder().decode(Mosaic.self, from: data)
    }

    /// `nil` — набросок отправлен или стёрт, хранить нечего.
    static func setMosaicDraft(_ draft: Mosaic?, for address: String) {
        var drafts = UserDefaults.standard.dictionary(forKey: mosaicDraftsKey) as? [String: Data] ?? [:]
        if let draft, !draft.isEmpty, let data = try? JSONEncoder().encode(draft) {
            drafts[address] = data
        } else {
            drafts.removeValue(forKey: address)
        }
        UserDefaults.standard.set(drafts, forKey: mosaicDraftsKey)
    }

    /// Сохранённые мозаики. Рисунок, который делали двадцать минут,
    /// не должен пропадать после отправки: его берут как основу для
    /// следующего или шлют ещё раз другому человеку.
    static var mosaicTemplates: [Mosaic] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: mosaicTemplatesKey) as? [Data] else {
                return []
            }
            return raw.compactMap { try? JSONDecoder().decode(Mosaic.self, from: $0) }
        }
        set {
            let raw = newValue.prefix(24).compactMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(raw, forKey: mosaicTemplatesKey)
        }
    }

    /// Сохранить мозаику. Свежая — первой; такая же уже есть — просто
    /// поднимается наверх, а не ложится второй раз.
    static func saveMosaicTemplate(_ mosaic: Mosaic) {
        guard !mosaic.isEmpty else {
            return
        }
        mosaicTemplates = [mosaic] + mosaicTemplates.filter { $0 != mosaic }
    }

    static func deleteMosaicTemplate(_ mosaic: Mosaic) {
        mosaicTemplates = mosaicTemplates.filter { $0 != mosaic }
    }

    /// Сбросить настройки 
    static func rest() {
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: relayURLKey)
        UserDefaults.standard.removeObject(forKey: demoPeersKey)
        UserDefaults.standard.removeObject(forKey: usesRelayKey)
        UserDefaults.standard.removeObject(forKey: mosaicBrushesKey)
        UserDefaults.standard.removeObject(forKey: mosaicDraftsKey)
        UserDefaults.standard.removeObject(forKey: mosaicTemplatesKey)
    }
}
