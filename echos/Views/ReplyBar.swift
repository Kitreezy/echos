//
//  ReplyBar.swift
//  echos
//
//  Плашка над полем ввода, пока пишется ответ: на что отвечаем и крестик.
//
//  Нажатие на цитату показывает оригинал в ленте — перед тем как
//  отправить, полезно перечитать, на что отвечаешь.
//

import UIKit

final class ReplyBar: UIView {

    var onClose: (() -> Void)?
    var onTap: (() -> Void)?

    private let icon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left"))
        view.tintColor = .inkMuted
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let quote: QuoteView = {
        let view = QuoteView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let closeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark")
        config.baseForegroundColor = .inkMuted
        let button = UIButton(configuration: config)
        button.accessibilityLabel = String(localized: "Не отвечать")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .surface
        clipsToBounds = true

        addSubview(icon)
        addSubview(quote)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.step),
            icon.centerYAnchor.constraint(equalTo: quote.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),

            quote.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Space.tight),
            quote.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -Space.tight),
            quote.topAnchor.constraint(equalTo: topAnchor, constant: Space.tight),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.tight),
            closeButton.centerYAnchor.constraint(equalTo: quote.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        quote.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(quoteTapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Высота плашки, когда она видна.
    static let height: CGFloat = 52

    func show(author: String, preview: String, isFromMe: Bool) {
        quote.show(author: author, preview: preview, isFromMe: isFromMe)
    }

    @objc
    private func quoteTapped() {
        onTap?()
    }
}
