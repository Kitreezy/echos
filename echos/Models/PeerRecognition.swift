//
//  PeerRecognition.swift
//  echos
//
//  Узнаём ли мы собеседника.
//
//  Адрес уникален, но человеку он ни о чём не говорит: шестнадцать
//  шестнадцатеричных знаков не отличить на глаз от других шестнадцати. Поэтому
//  сравнивать адреса должно приложение, а показывать — словами.
//

import Foundation

/// Человек, с которым уже разговаривали.
struct KnownPeer: Equatable, Sendable {
    /// Адрес — то, по чему узнаём. Отпечаток ключа на релее, имя устройства
    /// у Multipeer.
    let address: String

    /// Имя, под которым он был известен в последний разговор.
    let name: String

    let firstSeen: Date
    let lastSeen: Date
}

enum PeerRecognition: Equatable, Sendable {

    /// Адрес знаком, имя то же — обычный случай, показывать нечего.
    case known

    /// Тот же адрес под другим именем. Человек тот же, просто переименовался.
    case renamed(from: String)

    /// Имя знакомое, а ключ чужой. Самый важный случай: именно так выглядит
    /// попытка выдать себя за другого.
    case namesake

    /// Ни адрес, ни имя ещё не встречались. Просто незнакомец.
    case new

    /// Что показать под именем. `nil` — показывать нечего.
    var note: String? {
        switch self {
        case .known:
            return nil

        case .renamed(let previous):
            return "раньше — \(previous)"

        case .namesake:
            return "имя знакомое, человек другой"

        case .new:
            return "впервые"
        }
    }

    /// Стоит ли обращать внимание. Переименование и тёзка — да, новый
    /// собеседник — нет, в этом ничего необычного.
    var deservesAttention: Bool {
        switch self {
        case .renamed, .namesake: return true
        case .known, .new:        return false
        }
    }
}

/// Сопоставляет то, кого видим сейчас, с теми, с кем уже разговаривали.
///
/// Отдельный тип, а не метод во ViewModel: здесь чистое сравнение без
/// хранилища и без состояния, и проверять его удобно так же — на месте.
struct PeerRecognizer: Sendable {

    private let byAddress: [String: KnownPeer]

    /// Имена, которые уже за кем-то закреплены. Нужны, чтобы отличить тёзку
    /// от просто незнакомца.
    private let takenNames: Set<String>

    init(known: [KnownPeer]) {
        self.byAddress = Dictionary(known.map { ($0.address, $0) },
                                    uniquingKeysWith: { $1 })
        self.takenNames = Set(known.map(\.name))
    }

    func recognize(address: String, name: String) -> PeerRecognition {
        if let known = byAddress[address] {
            return known.name == name ? .known : .renamed(from: known.name)
        }

        return takenNames.contains(name) ? .namesake : .new
    }

    func recognize(_ peer: Peer) -> PeerRecognition {
        recognize(address: peer.address, name: peer.displayName)
    }
}
