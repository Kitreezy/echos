//
//  ConversationCell.swift
//  echos
//
//  Строка разговора на главном экране.
//
//  Плотнее, чем строка собеседника на радаре: там важно состояние связи и
//  узнавание, здесь — с кем и о чём. Имя, последняя реплика и когда она была,
//  в две строки; точка слева гаснет, когда человека нет на связи.
//
//  Отдельная ячейка, а не `ConversationRow` из SwiftUI: та осталась от
//  прежнего оформления — системные цвета, кружок в пятьдесят точек с буквой
//  внутри — и на этом экране выглядела бы чужой.
//

import UIKit

final class ConversationCell: UITableViewCell {

    static let reuseIdentifier = "ConversationCell"

    // MARK: - UI

    private let presenceDot: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 2.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.title
        label.textColor = .ink
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let lastMessageLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let separator: UIView = {
        let view = UIView()
        view.backgroundColor = .hairline
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        contentView.addSubview(presenceDot)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(lastMessageLabel)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            presenceDot.widthAnchor.constraint(equalToConstant: 5),
            presenceDot.heightAnchor.constraint(equalToConstant: 5),
            presenceDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                                 constant: Space.margin),
            presenceDot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor,
                                           constant: Space.room),
            nameLabel.leadingAnchor.constraint(equalTo: presenceDot.trailingAnchor,
                                               constant: Space.step),

            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor,
                                               constant: Space.step),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                constant: -Space.margin),

            lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor,
                                                  constant: Space.tight),
            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                       constant: -Space.margin),
            lastMessageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                     constant: -Space.room),

            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                               constant: Space.margin),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                constant: -Space.margin),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // MARK: - Configure

    func configure(with conversation: ConversationSummary) {
        nameLabel.setTracked(conversation.peerName, tracking: Typography.narrow)
        timeLabel.text = Self.formatter.localizedString(for: conversation.lastMessageTime,
                                                        relativeTo: Date())

        // Пустая переписка бывает: чат открыли и ничего не написали.
        lastMessageLabel.text = conversation.lastMessage.isEmpty
            ? "Пока ни слова"
            : conversation.lastMessage

        presenceDot.backgroundColor = conversation.isActive
            ? .alive
            : .hairline
    }

    /// Язык задан явно, а не берётся у системы.
    ///
    /// Приложение целиком написано по-русски строками в коде, локализации в
    /// нём нет. Без этой строки на телефоне с английским языком в русском
    /// списке появлялось «3 sec ago».
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()
}
