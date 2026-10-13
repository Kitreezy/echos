//
//  MosaicDraftView.swift
//  echos
//
//  Черновик мозаики — там и таким, каким он уйдёт.
//
//  Лежит поверх ленты, над полем ввода, прижат вправо и подписан, как
//  своё сообщение. Клетки того же размера, что в чате: что видишь, то и
//  отправится, без «садится при отправке». Красится нажатием и
//  протягиванием прямо здесь.
//

import UIKit

final class MosaicDraftView: UIView {

    var onTap: ((Int, Int) -> Void)? {
        get { grid.onTap }
        set { grid.onTap = newValue }
    }

    var onDrag: ((Int, Int) -> Void)? {
        get { grid.onDrag }
        set { grid.onDrag = newValue }
    }

    private let grid: MosaicView = {
        let view = MosaicView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let footnote: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Черновик лежит поверх ленты, и лента не должна просвечивать
        // сквозь пустые клетки: фон плотный, край — волосяной линией.
        backgroundColor = .surface
        layer.cornerRadius = 12
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.hairline.cgColor

        addSubview(grid)
        addSubview(footnote)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: Space.tight),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.tight),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.tight),

            footnote.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: Space.tight),
            footnote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.tight),
            footnote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.tight),
            footnote.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Space.tight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ mosaic: Mosaic) {
        grid.show(mosaic)
        footnote.text = mosaic.isEmpty
            ? "черновик"
            : "черновик · \(mosaic.filledCount) из \(mosaic.cells.count)"
    }
}
