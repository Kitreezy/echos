//
//  Typography.swift
//  echos
//
//  Шрифты.
//
//  Моноширинный был частью прежней интонации — «терминал». В тихой комнате
//  он читается как чужой, поэтому остаётся только там, где важна разрядка
//  цифр. Всё остальное — обычный системный шрифт лёгкого начертания.
//
//  Разрядка важнее размера: воздух внутри слова делает заголовок спокойным,
//  а не крупный кегль.
//

import SwiftUI
import UIKit

enum Typography {

    /// Крупная надпись: имя собеседника, заголовок экрана.
    static let title = UIFont.systemFont(ofSize: 22, weight: .light)

    /// Текст сообщения.
    static let body = UIFont.systemFont(ofSize: 17, weight: .regular)

    /// Второстепенное: статус, время.
    static let caption = UIFont.systemFont(ofSize: 13, weight: .regular)

    /// Совсем тихое: подписи в шапке.
    static let micro = UIFont.systemFont(ofSize: 11, weight: .regular)

    /// Разрядка для крупного.
    static let wide: CGFloat = 3

    /// Разрядка для мелкого.
    static let narrow: CGFloat = 1.2
}

extension UILabel {

    /// Текст с разрядкой. UIKit не умеет её без атрибутов.
    func setTracked(_ text: String, tracking: CGFloat) {
        attributedText = NSAttributedString(
            string: text,
            attributes: [.kern: tracking]
        )
    }
}

extension Font {

    /// Мост из UIKit-шрифта в SwiftUI.
    ///
    /// Отдельных SwiftUI-токенов нет намеренно: `Font.title`, `.body` и
    /// `.caption` уже заняты системой, и одноимённые свои молча растворились
    /// бы среди них. Пишем `Font(Typography.title)` — источник один.
    init(_ font: UIFont) {
        self = Font(font as CTFont)
    }
}
