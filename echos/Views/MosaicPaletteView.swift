//
//  MosaicPaletteView.swift
//  echos
//
//  Палитра мозаики — на месте клавиатуры.
//
//  Мозаика — часть печатания, а не отдельный экран: нажал кнопку сетки,
//  и вместо клавиатуры выезжает палитра, а над полем ввода появляется
//  черновик прямо в том виде, в каком он уйдёт. Здесь — то, что внизу:
//  размер, инструменты, группы эмодзи и сами эмодзи, восемь в ряд.
//  Квадраты и круги первыми: из них складываются пиксели.
//

import UIKit

@MainActor
protocol MosaicPaletteDelegate: AnyObject {
    func palette(_ palette: MosaicPaletteView, didPickBrush brush: String)
    func palette(_ palette: MosaicPaletteView, didPickSide side: Int)
    func paletteDidAskToFill(_ palette: MosaicPaletteView)
    func paletteDidAskToClear(_ palette: MosaicPaletteView)
    /// Своего эмодзи в палитре нет — нужна настоящая клавиатура.
    func paletteDidAskForKeyboard(_ palette: MosaicPaletteView)
}

final class MosaicPaletteView: UIView {

    weak var delegate: MosaicPaletteDelegate?

    /// Стороны на выбор. Квадраты — потому что так рисуют чаще всего.
    static let sides = [2, 3, 4, 5, 6, 8]

    /// Что сейчас в руке. Пустая кисть — ластик.
    private(set) var brush = ""

    private var selectedGroup = 0

    // MARK: - UI

    private let sizeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: MosaicPaletteView.sides.map { "\($0)×\($0)" })
        control.selectedSegmentIndex = 2
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let brushPreview: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 24)
        label.textAlignment = .center
        label.backgroundColor = .surfaceRaised
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var eraserButton = makeToolButton("ластик", symbol: "eraser", action: #selector(pickEraser))
    private lazy var fillButton = makeToolButton("залить", symbol: "paintbrush.fill", action: #selector(fillTapped))
    private lazy var clearButton = makeToolButton("очистить", symbol: "trash", action: #selector(clearTapped))
    private lazy var customButton = makeToolButton("свой", symbol: "keyboard", action: #selector(customTapped))

    private lazy var toolsRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [brushPreview, eraserButton, fillButton, clearButton, customButton])
        stack.axis = .horizontal
        stack.spacing = Space.tight
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let groupsBar: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let groupsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Space.tight
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var emojis: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Space.hair
        layout.minimumLineSpacing = Space.hair
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        collection.dataSource = self
        collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        return collection
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .surfaceRaised
        setupLayout()
        sizeControl.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        showGroups()
        setBrush(UserSettings.mosaicBrushes.first ?? EmojiPalette.groups[0].emojis[0])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Высота как у клавиатуры. `inputView` берёт её из фрейма, а не из
    /// констрейнтов, поэтому фрейм задаётся явно и растягивается по ширине.
    static let height: CGFloat = 300

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height))
        autoresizingMask = [.flexibleWidth]
    }

    private func setupLayout() {
        [sizeControl, toolsRow, groupsBar, emojis].forEach(addSubview)
        groupsBar.addSubview(groupsStack)

        NSLayoutConstraint.activate([
            sizeControl.topAnchor.constraint(equalTo: topAnchor, constant: Space.tight),
            sizeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.margin),
            sizeControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.margin),

            toolsRow.topAnchor.constraint(equalTo: sizeControl.bottomAnchor, constant: Space.tight),
            toolsRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            brushPreview.widthAnchor.constraint(equalToConstant: 44),
            brushPreview.heightAnchor.constraint(equalToConstant: 44),

            groupsBar.topAnchor.constraint(equalTo: toolsRow.bottomAnchor, constant: Space.tight),
            groupsBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupsBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            groupsBar.heightAnchor.constraint(equalToConstant: 32),

            groupsStack.topAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.topAnchor),
            groupsStack.bottomAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.bottomAnchor),
            groupsStack.leadingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.leadingAnchor, constant: Space.margin),
            groupsStack.trailingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.trailingAnchor, constant: -Space.margin),
            groupsStack.heightAnchor.constraint(equalTo: groupsBar.frameLayoutGuide.heightAnchor),

            emojis.topAnchor.constraint(equalTo: groupsBar.bottomAnchor, constant: Space.tight),
            emojis.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.margin),
            emojis.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.margin),
            emojis.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Space.tight)
        ])
    }

    private func makeToolButton(_ title: String, symbol: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: symbol)
        config.title = title
        config.imagePlacement = .top
        config.imagePadding = 2
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.baseForegroundColor = .ink
        config.baseBackgroundColor = .surface
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Typography.micro
            return attributes
        }
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Кисть

    func setBrush(_ brush: String) {
        self.brush = brush
        brushPreview.text = brush.isEmpty ? "⌫" : brush
        eraserButton.configuration?.baseBackgroundColor = brush.isEmpty ? .own : .surface
        eraserButton.configuration?.baseForegroundColor = brush.isEmpty ? .surface : .ink

        if !brush.isEmpty {
            UserSettings.rememberBrush(brush)
        }
        showGroups()
        emojis.reloadData()
        delegate?.palette(self, didPickBrush: brush)
    }

    @objc
    private func pickEraser() {
        setBrush("")
    }

    @objc
    private func fillTapped() {
        delegate?.paletteDidAskToFill(self)
    }

    @objc
    private func clearTapped() {
        delegate?.paletteDidAskToClear(self)
    }

    @objc
    private func customTapped() {
        delegate?.paletteDidAskForKeyboard(self)
    }

    @objc
    private func sizeChanged() {
        delegate?.palette(self, didPickSide: Self.sides[sizeControl.selectedSegmentIndex])
    }

    // MARK: - Группы

    /// Первая группа — недавние: то, чем рисовали, под рукой.
    private var groups: [EmojiPalette.Group] {
        let recent = UserSettings.mosaicBrushes
        let recentGroup = EmojiPalette.Group(id: "recent", title: "недавние", emojis: recent)
        return (recent.isEmpty ? [] : [recentGroup]) + EmojiPalette.groups
    }

    private func showGroups() {
        let groups = self.groups
        selectedGroup = min(selectedGroup, groups.count - 1)
        groupsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, group) in groups.enumerated() {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
            config.attributedTitle = AttributedString(group.title, attributes: AttributeContainer([
                .font: Typography.micro,
                .kern: Typography.narrow
            ]))
            config.baseForegroundColor = index == selectedGroup ? .surface : .inkMuted
            config.background.backgroundColor = index == selectedGroup ? .own : .surface
            config.background.cornerRadius = 12

            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedGroup = index
                self?.showGroups()
                self?.emojis.reloadData()
                self?.emojis.setContentOffset(.zero, animated: false)
            }, for: .touchUpInside)
            groupsStack.addArrangedSubview(button)
        }
    }
}

// MARK: - Эмодзи

extension MosaicPaletteView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var currentEmojis: [String] {
        let groups = self.groups
        guard selectedGroup < groups.count else {
            return []
        }
        return groups[selectedGroup].emojis
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath)
        let emoji = currentEmojis[indexPath.item]
        (cell as? EmojiCell)?.show(emoji, selected: emoji == brush)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let picked = currentEmojis[indexPath.item]
        // Выбор из недавних переставляет недавние, а выбранная группа
        // должна остаться той же: она первая и ею остаётся.
        let hadRecent = groups.first?.id == "recent"
        setBrush(picked)
        if !hadRecent, groups.first?.id == "recent" {
            selectedGroup += 1
            showGroups()
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = 8
        let side = (collectionView.bounds.width - (columns - 1) * Space.hair) / columns
        return CGSize(width: floor(side), height: floor(side))
    }
}

/// Один эмодзи в палитре. Выбранный — с рамкой цвета своих сообщений.
private final class EmojiCell: UICollectionViewCell {

    static let reuseID = "EmojiCell"

    private let label: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 24)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 2
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ emoji: String, selected: Bool) {
        label.text = emoji
        contentView.layer.borderColor = selected ? UIColor.own.cgColor : UIColor.clear.cgColor
        contentView.backgroundColor = selected ? .surface : .clear
    }
}
