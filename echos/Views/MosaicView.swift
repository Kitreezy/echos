//
//  MosaicView.swift
//  echos
//
//  Мозаика на экране — сеткой из одинаковых клеток.
//
//  Именно ради этого мозаика и ходит сеткой, а не текстом: клетки здесь
//  одного размера у обоих собеседников, и рисунок не разъезжается.
//  Одна и та же вью показывает готовую мозаику в чате и рисуемую — в
//  наборе; в наборе ещё и принимает нажатия по клеткам.
//

import UIKit

final class MosaicView: UIView {

    /// Клетка в чате. В наборе клетки крупнее — см. `cellSize`.
    static let chatCellSize: CGFloat = 32

    var cellSize: CGFloat = MosaicView.chatCellSize {
        didSet { rebuild() }
    }

    /// Нажатие по клетке: столбец и строка. `nil` — мозаика только для
    /// показа.
    var onTap: ((Int, Int) -> Void)?

    /// Протягивание по клеткам: вызывается на каждую новую клетку под
    /// пальцем. Рисовать проведя пальцем — быстрее, чем тыкать в каждую.
    var onDrag: ((Int, Int) -> Void)?

    private var lastDragged: Int?

    private(set) var mosaic = Mosaic(columns: 1, rows: 1)

    private let rowsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Space.hair
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var cellLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(rowsStack)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged)))
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ mosaic: Mosaic) {
        let sameShape = mosaic.columns == self.mosaic.columns && mosaic.rows == self.mosaic.rows
        self.mosaic = mosaic

        // Та же форма — только перекрасить клетки: в наборе это каждое
        // нажатие, и пересобирать сетку ради одного знака незачем.
        if sameShape, cellLabels.count == mosaic.cells.count {
            for (label, cell) in zip(cellLabels, mosaic.cells) {
                fill(label, with: cell)
            }
        } else {
            rebuild()
        }
    }

    // MARK: - Private

    private func rebuild() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cellLabels.removeAll()

        for row in 0..<mosaic.rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = Space.hair

            for column in 0..<mosaic.columns {
                let label = makeCell(column: column, row: row)
                fill(label, with: mosaic[column, row])
                rowStack.addArrangedSubview(label)
                cellLabels.append(label)
            }
            rowsStack.addArrangedSubview(rowStack)
        }
    }

    private func makeCell(column: Int, row: Int) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: cellSize * 0.7)
        label.layer.cornerRadius = cellSize * 0.18
        label.layer.masksToBounds = true
        label.tag = row * mosaic.columns + column
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: cellSize),
            label.heightAnchor.constraint(equalToConstant: cellSize)
        ])

        if onTap != nil {
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cellTapped)))
        }
        return label
    }

    /// Пустая клетка — чуть светлее фона, чтобы сетка читалась как сетка.
    /// В чате пустые клетки прозрачные: там рисунок, а не поле.
    private func fill(_ label: UILabel, with cell: String) {
        label.text = cell
        label.backgroundColor = cell.isEmpty && onTap != nil ? .surfaceRaised : .clear
    }

    @objc
    private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let onDrag else {
            return
        }

        switch recognizer.state {
        case .began, .changed:
            let point = recognizer.location(in: self)
            guard let label = cellLabels.first(where: { $0.convert($0.bounds, to: self).contains(point) }),
                  label.tag != lastDragged else {
                return
            }
            lastDragged = label.tag
            onDrag(label.tag % mosaic.columns, label.tag / mosaic.columns)

        default:
            lastDragged = nil
        }
    }

    @objc
    private func cellTapped(_ recognizer: UITapGestureRecognizer) {
        guard let index = recognizer.view?.tag else {
            return
        }
        onTap?(index % mosaic.columns, index / mosaic.columns)
    }
}
