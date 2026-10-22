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

    // Размеры — при обычной настройке текста, и они не изменились. Но шрифт
    // растёт вместе с настройкой «Размер текста»: каждый токен привязан к
    // системному стилю, и UIFontMetrics пересчитывает его. Раньше размеры
    // были фиксированные, и человек, которому нужен крупный текст, получал
    // мелкий — во всём приложении. Подписям нужно ещё
    // `adjustsFontForContentSizeCategory`, чтобы менялись на лету.

    /// Крупная надпись: имя собеседника, заголовок экрана.
    static var title: UIFont { scaled(.systemFont(ofSize: 22, weight: .light), as: .title2) }

    /// Текст сообщения.
    static var body: UIFont { scaled(.systemFont(ofSize: 17, weight: .regular), as: .body) }

    /// Второстепенное: статус, время.
    static var caption: UIFont { scaled(.systemFont(ofSize: 13, weight: .regular), as: .footnote) }

    /// Совсем тихое: подписи в шапке.
    ///
    /// Масштаб — по `footnote`, а не по `caption2`, хотя 11 пунктов — это
    /// размер caption2. Caption2 при крупном тексте из специальных
    /// возможностей растёт заметно меньше остальных стилей, и аудит
    /// доступности считал такие подписи поддерживающими Dynamic Type лишь
    /// частично. При обычной настройке размер тот же.
    static var micro: UIFont { scaled(.systemFont(ofSize: 11, weight: .regular), as: .footnote) }

    // SwiftUI: те же размеры на системных стилях — title2 это 22, body 17,
    // footnote 13, caption2 11 — и SwiftUI масштабирует их сам. Мост
    // Font(UIFont) для этого не годится: такой шрифт SwiftUI не растит.
    static let titleText = Font.system(.title2, weight: .light)
    static let bodyText = Font.system(.body)
    static let captionText = Font.system(.footnote)
    static let microText = Font.system(.caption2)

    /// Свой размер, но растущий вместе со стилем `style`.
    static func scaled(_ font: UIFont, as style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

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

extension UIButton.Configuration {

    /// Шрифт заголовка, который растёт вместе с размером текста на лету.
    ///
    /// Шрифт, вшитый в `attributedTitle`, вычисляется один раз — при сборке
    /// заголовка: запустились с крупным текстом — заголовок крупный, но
    /// поменяли размер, не закрывая приложения, — остался прежним. Аудит
    /// доступности меряет именно это. Преобразователь же вызывается при
    /// каждом обновлении кнопки, в том числе при смене размера текста.
    mutating func scalesTitle(with font: @escaping @Sendable () -> UIFont) {
        titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font()
            return attributes
        }
    }
}
