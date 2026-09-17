//
//  MessageCell.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import UIKit

/// Сообщение без пузыря.
///
/// Было: скруглённый контейнер с заливкой, цветная полоса слева, время и
/// статус капсом внутри — «SENT», «RECEIVED». Стало: текст и время под ним.
///
/// Кто написал, видно по цвету и стороне: своё золотом справа, чужое лиловым
/// слева. Подпись «RECEIVED» под входящим сообщением не сообщала ничего —
/// раз оно на экране, значит получено. Статус остался только у своих и только
/// пока он что-то значит: отправляется или не ушло.
final class MessageCell: UITableViewCell {

    static let reuseID = "MessageCell"

    // MARK: - UI

    private let senderNameLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    /// Текст — в `UITextView`, а не в `UILabel`: так его можно выделить
    /// прямо в ленте и скопировать штатным меню, а ссылки в нём живые.
    /// Не редактируется, не прокручивается, размер задаёт содержимое.
    private let messageLabel: UITextView = {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = Typography.body
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link]
        view.linkTextAttributes = [
            .foregroundColor: UIColor.action,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        view.tintColor = .own
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Что делать по нажатию на «не отправлено». `nil` — нажимать нечего.
    var onRetry: (() -> Void)?

    /// Мозаика — вместо текста, когда сообщение ею и является.
    private let mosaicView: MosaicView = {
        let view = MosaicView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    /// Текст или мозаика — что-то одно; скрытое в стеке не занимает места.
    private let body: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let footnoteLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Подпись нажимается только у неотправленного — там она и есть кнопка.
    private lazy var retryTap = UITapGestureRecognizer(target: self, action: #selector(retryTapped))

    private let column = UIView()

    private var columnLeading: NSLayoutConstraint?
    private var columnTrailing: NSLayoutConstraint?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none

        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)
        column.addSubview(senderNameLabel)
        column.addSubview(body)
        column.addSubview(footnoteLabel)
        footnoteLabel.addGestureRecognizer(retryTap)
        body.addArrangedSubview(messageLabel)
        body.addArrangedSubview(mosaicView)

        columnLeading = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                        constant: Space.margin)
        columnTrailing = column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                          constant: -Space.margin)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Space.tight),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Space.tight),
            column.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8),

            senderNameLabel.topAnchor.constraint(equalTo: column.topAnchor),
            senderNameLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            senderNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),

            body.topAnchor.constraint(equalTo: senderNameLabel.bottomAnchor, constant: Space.hair),
            body.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            messageLabel.widthAnchor.constraint(equalTo: body.widthAnchor),

            footnoteLabel.topAnchor.constraint(equalTo: body.bottomAnchor, constant: Space.tight),
            footnoteLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),
            footnoteLabel.bottomAnchor.constraint(equalTo: column.bottomAnchor)
        ])
    }

    // MARK: - Configure

    func configure(with message: Message) {
        if let mosaic = message.mosaic {
            mosaicView.show(mosaic)
            mosaicView.isHidden = false
            messageLabel.isHidden = true
        } else {
            messageLabel.text = message.text
            messageLabel.isHidden = false
            mosaicView.isHidden = true
        }

        let time = Self.timeFormatter.string(from: message.timestamp)

        if message.isFromMe {
            alignRight()
            messageLabel.textColor = .own
            senderNameLabel.isHidden = true
            footnoteLabel.text = footnote(time: time, status: message.status)
            footnoteLabel.textColor = message.status == .failed ? .lost : .inkMuted
            footnoteLabel.isUserInteractionEnabled = message.status == .failed
        } else {
            alignLeft()
            messageLabel.textColor = .other
            footnoteLabel.text = time
            footnoteLabel.textColor = .inkMuted
            footnoteLabel.isUserInteractionEnabled = false

            senderNameLabel.text = message.senderName
            senderNameLabel.isHidden = message.senderName == nil
        }
    }

    /// Время говорит всегда, статус — только когда он новость.
    private func footnote(time: String, status: MessageStatus) -> String {
        switch status {
        case .sending:
            return "\(time) · отправляется"

        case .sent:
            return time

        case .failed:
            return "\(time) · не отправлено · повторить"
        }
    }

    @objc
    private func retryTapped() {
        onRetry?()
    }

    private func alignLeft() {
        columnTrailing?.isActive = false
        columnLeading?.isActive = true
        messageLabel.textAlignment = .left
        footnoteLabel.textAlignment = .left
        body.alignment = .leading
    }

    private func alignRight() {
        columnLeading?.isActive = false
        columnTrailing?.isActive = true
        messageLabel.textAlignment = .right
        footnoteLabel.textAlignment = .right
        body.alignment = .trailing
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()

        senderNameLabel.isHidden = true
        columnLeading?.isActive = false
        columnTrailing?.isActive = false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
