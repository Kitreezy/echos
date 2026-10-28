//
//  QuoteView.swift
//  echos
//
//  Цитата оригинала: полоса, чей он и строка текста.
//
//  Одна и та же — над ответом в ленте и над полем ввода, пока ответ
//  пишется: человек должен узнавать её с первого взгляда. Цвет — по
//  автору оригинала, как в ленте: своё золотом, чужое лиловым.
//

import UIKit

final class QuoteView: UIView {

    private let stripe: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 1.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let authorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(stripe)
        addSubview(authorLabel)
        addSubview(previewLabel)

        NSLayoutConstraint.activate([
            stripe.leadingAnchor.constraint(equalTo: leadingAnchor),
            stripe.topAnchor.constraint(equalTo: topAnchor),
            stripe.bottomAnchor.constraint(equalTo: bottomAnchor),
            stripe.widthAnchor.constraint(equalToConstant: 3),

            authorLabel.topAnchor.constraint(equalTo: topAnchor, constant: Space.hair),
            authorLabel.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: Space.tight),
            authorLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            previewLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 1),
            previewLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Space.hair)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(author: String, preview: String, isFromMe: Bool) {
        let color: UIColor = isFromMe ? .own : .other
        stripe.backgroundColor = color
        authorLabel.textColor = color
        authorLabel.text = author
        // Цитата — одна строка: многострочный оригинал в ней не нужен.
        previewLabel.text = preview.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
