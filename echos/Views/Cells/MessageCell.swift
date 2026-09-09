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

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = Typography.body
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let footnoteLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

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
        column.addSubview(messageLabel)
        column.addSubview(footnoteLabel)

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

            messageLabel.topAnchor.constraint(equalTo: senderNameLabel.bottomAnchor, constant: Space.hair),
            messageLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            footnoteLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: Space.tight),
            footnoteLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            footnoteLabel.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),
            footnoteLabel.bottomAnchor.constraint(equalTo: column.bottomAnchor)
        ])
    }

    // MARK: - Configure

    func configure(with message: Message) {
        messageLabel.text = message.text

        let time = Self.timeFormatter.string(from: message.timestamp)

        if message.isFromMe {
            alignRight()
            messageLabel.textColor = .own
            senderNameLabel.isHidden = true
            footnoteLabel.text = footnote(time: time, status: message.status)
            footnoteLabel.textColor = message.status == .failed ? .lost : .inkMuted
        } else {
            alignLeft()
            messageLabel.textColor = .other
            footnoteLabel.text = time
            footnoteLabel.textColor = .inkMuted

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
            return "\(time) · не отправлено"
        }
    }

    private func alignLeft() {
        columnTrailing?.isActive = false
        columnLeading?.isActive = true
        messageLabel.textAlignment = .left
        footnoteLabel.textAlignment = .left
    }

    private func alignRight() {
        columnLeading?.isActive = false
        columnTrailing?.isActive = true
        messageLabel.textAlignment = .right
        footnoteLabel.textAlignment = .right
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
