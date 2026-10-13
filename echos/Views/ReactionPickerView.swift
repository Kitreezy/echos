//
//  ReactionPickerView.swift
//  echos
//
//  Ряд эмодзи над сообщением: одна реакция — одно нажатие.
//
//  Появляется по нажатию на сообщение, уходит по выбору или по нажатию
//  мимо. Своя текущая реакция подсвечена; нажать на неё — снять.
//

import UIKit

final class ReactionPickerView: UIView {

    var onPick: ((String) -> Void)?

    init(current: String?) {
        super.init(frame: .zero)
        backgroundColor = .surfaceRaised
        layer.cornerRadius = 22
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.hairline.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Space.hair
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        for emoji in ChatViewModel.reactionChoices {
            var config = UIButton.Configuration.plain()
            config.title = emoji
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            config.background.cornerRadius = 16
            config.background.backgroundColor = emoji == current ? .surface : .clear
            let button = UIButton(configuration: config)
            button.titleLabel?.font = .systemFont(ofSize: 26)
            button.addAction(UIAction { [weak self] _ in
                UISelectionFeedbackGenerator().selectionChanged()
                self?.onPick?(emoji)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
