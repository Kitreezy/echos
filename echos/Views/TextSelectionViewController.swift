//
//  TextSelectionViewController.swift
//  echos
//
//  Текст сообщения — так, чтобы выделить часть.
//
//  В ленте сообщения — `UILabel`, выделять в нём нельзя, а превращать все
//  ячейки в `UITextView` ради редкого случая — дорого и хрупко: долгое
//  нажатие тогда спорит с меню сообщения. Поэтому «выделить» — это лист с
//  тем же текстом, где работает штатное выделение и копирование.
//

import UIKit

final class TextSelectionViewController: UIViewController {

    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .surface

        let textView = UITextView()
        textView.text = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Typography.body
        textView.textColor = .ink
        textView.backgroundColor = .clear
        textView.tintColor = .own
        textView.textContainerInset = UIEdgeInsets(top: Space.room, left: Space.margin,
                                                   bottom: Space.room, right: Space.margin)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
