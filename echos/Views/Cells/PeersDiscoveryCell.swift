//
//  PeersDiscoveryCell.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import UIKit

/// Строка списка вместо карточки.
///
/// Было: контейнер с рамкой и скруглением, цветная полоса слева, тень,
/// свечение у текста и иконки, вращающаяся стрелка, пульсация и кнопка
/// в рамке. Стало: имя, слово о состоянии и волосяная линия снизу.
///
/// Статус несёт цвет точки, а не рамка вокруг всего. Действие — нажатие на
/// строку: кнопка была лишней, потому что таблица и так обрабатывала выбор.
final class PeerDiscoveryCell: UITableViewCell {

    // MARK: - UI

    /// Единственная цветная деталь в строке.
    private let statusDot: UIView = {
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

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
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
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(statusDot)
        contentView.addSubview(nameLabel)
        contentView.addSubview(statusLabel)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                               constant: Space.margin),
            statusDot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 5),
            statusDot.heightAnchor.constraint(equalToConstant: 5),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor,
                                           constant: Space.room),
            nameLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor,
                                               constant: Space.step),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                constant: -Space.margin),

            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor,
                                             constant: Space.tight),
            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor,
                                                constant: -Space.room),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor,
                                               constant: Space.margin),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor,
                                                constant: -Space.margin),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    // MARK: - Configure

    func configure(with peer: Peer) {
        nameLabel.setTracked(peer.displayName, tracking: Typography.narrow)
        statusLabel.text = peer.statusLabel
        statusDot.backgroundColor = UIColor(peer.statusColor)

        // Недоступный собеседник не кричит, а тускнеет.
        contentView.alpha = peer.status == .failed ? 0.4 : 1
    }
}
