//
//  OnceFlag.swift
//  echos
//
//  Флажок «кто первый»: из нескольких вызовов `claim()` true получит
//  ровно один, с какого бы потока они ни шли.
//

import Synchronization

/// Нужен там, где колбэк приходит больше одного раза, а continuation
/// можно возобновить только однажды.
///
/// Класс, а не голый `Atomic`: `Atomic` некопируемый, и escaping-замыкание
/// захватить его не может. Ссылка на класс копируется, флажок — нет.
final class OnceFlag: Sendable {

    private let claimed = Atomic(false)

    /// true — первому вызвавшему, false — всем остальным.
    ///
    /// `.relaxed` хватает: флажок ничего не публикует для других потоков,
    /// он только выбирает победителя, а это гарантирует атомарность
    /// самого `exchange`.
    func claim() -> Bool {
        !claimed.exchange(true, ordering: .relaxed)
    }
}
