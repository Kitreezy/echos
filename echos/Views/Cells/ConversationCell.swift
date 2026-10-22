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
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .ink
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .inkMuted
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let lastMessageLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .inkMuted
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Сколько непрочитанного. Пусто — ничего, и метки нет.
    private let unreadBadge: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .surface
        label.backgroundColor = .own
        label.textAlignment = .center
        label.layer.masksToBounds = true
        label.isHidden = true
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
        contentView.addSubview(unreadBadge)
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

            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                constant: -Space.margin),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                constant: -Space.margin),

            lastMessageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            lastMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: unreadBadge.leadingAnchor,
                                                       constant: -Space.tight),
            lastMessageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                     constant: -Space.room),

            unreadBadge.centerYAnchor.constraint(equalTo: lastMessageLabel.centerYAnchor),
            unreadBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                  constant: -Space.margin),
            // Кружок растёт вместе с числом в нём: при фиксированных 18
            // пунктах крупное число обрезалось.
            unreadBadge.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
            unreadBadge.widthAnchor.constraint(greaterThanOrEqualTo: unreadBadge.heightAnchor),

            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                               constant: Space.margin),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                constant: -Space.margin),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        arrange(for: traitCollection.preferredContentSizeCategory)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: Self, _) in
            cell.arrange(for: cell.traitCollection.preferredContentSizeCategory)
        }
    }

    // MARK: - Крупный текст

    /// Обычно время стоит справа от имени. При крупном тексте из
    /// специальных возможностей им вдвоём не хватает строки, и время,
    /// которое держит своё место, сжимало имя до «А…» — человек не видел,
    /// чей это разговор. Тогда время уходит под имя, а превью получает
    /// несколько строк.
    private lazy var sideBySide = [
        timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
        timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: Space.step),
        timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Space.margin),
        lastMessageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Space.tight)
    ]

    private lazy var stacked = [
        timeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: Space.hair),
        timeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
        lastMessageLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: Space.tight)
    ]

    private func arrange(for category: UIContentSizeCategory) {
        let large = category.isAccessibilityCategory
        NSLayoutConstraint.deactivate(large ? sideBySide : stacked)
        NSLayoutConstraint.activate(large ? stacked : sideBySide)
        // Две строки и при обычных размерах: на крупных из обычного ряда
        // одна строка превью уже обрезалась.
        lastMessageLabel.numberOfLines = large ? 3 : 2
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        unreadBadge.layer.cornerRadius = unreadBadge.bounds.height / 2
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

        // Непрочитанное — числом в кружке; последнее сообщение при этом
        // светлее обычного, чтобы разговор заметить и не считая.
        unreadBadge.isHidden = conversation.unreadCount == 0
        unreadBadge.text = " \(conversation.unreadCount) "
        lastMessageLabel.textColor = conversation.unreadCount == 0 ? .inkMuted : .ink

        describe(conversation)
    }

    /// Для VoiceOver ячейка — одна фраза, а не четыре куска подряд: «Боб, 3
    /// непрочитанных, мозаика, 5 минут назад». Без этого кружок с числом
    /// читался как « 3 » без смысла, а мозаика — эмодзи за эмодзи.
    private func describe(_ conversation: ConversationSummary) {
        isAccessibilityElement = true
        accessibilityTraits = .button
        var parts = [conversation.peerName]
        if conversation.unreadCount > 0 {
            parts.append(Self.unread(conversation.unreadCount))
        }
        parts.append(conversation.lastMessageIsMosaic ? "мозаика" : (lastMessageLabel.text ?? ""))
        parts.append(timeLabel.text ?? "")
        accessibilityLabel = parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// «1 непрочитанное», «3 непрочитанных», «5 непрочитанных».
    static func unread(_ count: Int) -> String {
        let (tens, ones) = (count % 100, count % 10)
        let word = ones == 1 && tens != 11 ? "непрочитанное" : "непрочитанных"
        return "\(count) \(word)"
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
