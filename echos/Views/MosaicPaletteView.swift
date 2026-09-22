//
//  MosaicPaletteView.swift
//  echos
//
//  Палитра мозаики — на месте клавиатуры.
//
//  Мозаика — часть печатания, а не отдельный экран: нажал кнопку сетки,
//  и вместо клавиатуры выезжает палитра, а над полем ввода появляется
//  черновик прямо в том виде, в каком он уйдёт.
//
//  Всё, что нужно для рисования, — здесь: размер, кисть, ластик, заливка,
//  сохранённые мозаики и эмодзи. Порядок рядов — по тому, как часто их
//  трогают: размер выбирают раз, инструменты изредка, а эмодзи — каждое
//  нажатие, и им отдана вся оставшаяся высота.
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

    /// Сохранить то, что нарисовано, — как мозаику на будущее.
    func paletteDidAskToSaveTemplate(_ palette: MosaicPaletteView)
    /// Взять сохранённую мозаику за основу.
    func palette(_ palette: MosaicPaletteView, didPickTemplate mosaic: Mosaic)
    /// Убрать сохранённую мозаику.
    func palette(_ palette: MosaicPaletteView, didAskToDelete mosaic: Mosaic)

    /// Картинкой: в фотоплёнку или куда угодно.
    func paletteDidAskToSaveImage(_ palette: MosaicPaletteView)
    func paletteDidAskToShare(_ palette: MosaicPaletteView)
}

final class MosaicPaletteView: UIView {

    weak var delegate: MosaicPaletteDelegate?

    /// Стороны на выбор. Квадраты — потому что так рисуют чаще всего.
    static let sides = [2, 3, 4, 5, 6, 8]

    /// Высота как у клавиатуры, чуть больше: эмодзи должно быть видно
    /// рядами, а не полоской. `inputView` берёт её из фрейма, а не из
    /// констрейнтов, поэтому фрейм задаётся явно.
    static let height: CGFloat = 380

    /// Что сейчас в руке. Пустая кисть — ластик.
    private(set) var brush = ""

    /// Выбранная вкладка — по имени, а не по номеру: вкладки появляются
    /// и исчезают (сохранили мозаику, взяли новую кисть), и номер после
    /// этого показывает на соседа.
    private var selectedSectionID = EmojiPalette.groups[0].id

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
        label.backgroundColor = .surface
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var eraserButton = makeToolButton("ластик", symbol: "eraser", action: #selector(pickEraser))
    private lazy var fillButton = makeToolButton("залить", symbol: "paintbrush.fill", action: #selector(fillTapped))
    private lazy var clearButton = makeToolButton("очистить", symbol: "trash", action: #selector(clearTapped))
    private lazy var customButton = makeToolButton("свой", symbol: "keyboard", action: #selector(customTapped))

    /// Всё, что делают с готовым рисунком, — под одной кнопкой: ряд
    /// инструментов должен оставаться рядом для рисования.
    private lazy var moreButton: UIButton = {
        let button = makeToolButton("ещё", symbol: "ellipsis", action: nil)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIAction(title: "Сохранить мозаику", image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.paletteDidAskToSaveTemplate(self)
            },
            UIAction(title: "Сохранить картинку", image: UIImage(systemName: "arrow.down.to.line")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.paletteDidAskToSaveImage(self)
            },
            UIAction(title: "Поделиться картинкой", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.paletteDidAskToShare(self)
            }
        ])
        return button
    }()

    private lazy var toolsRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [brushPreview, eraserButton, fillButton,
                                                   clearButton, customButton, moreButton])
        stack.axis = .horizontal
        stack.spacing = Space.hair
        stack.distribution = .fillProportionally
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

    private lazy var items: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Space.hair
        layout.minimumLineSpacing = Space.hair
        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        collection.register(TemplateCell.self, forCellWithReuseIdentifier: TemplateCell.reuseID)
        collection.dataSource = self
        collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        return collection
    }()

    // MARK: - Init

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height))
        autoresizingMask = [.flexibleWidth]
    }

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

    private func setupLayout() {
        [sizeControl, toolsRow, groupsBar, items].forEach(addSubview)
        groupsBar.addSubview(groupsStack)

        NSLayoutConstraint.activate([
            sizeControl.topAnchor.constraint(equalTo: topAnchor, constant: Space.tight),
            sizeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.step),
            sizeControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.step),

            toolsRow.topAnchor.constraint(equalTo: sizeControl.bottomAnchor, constant: Space.tight),
            toolsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.tight),
            toolsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.tight),
            toolsRow.heightAnchor.constraint(equalToConstant: 48),
            brushPreview.widthAnchor.constraint(equalToConstant: 44),
            brushPreview.heightAnchor.constraint(equalToConstant: 44),

            groupsBar.topAnchor.constraint(equalTo: toolsRow.bottomAnchor, constant: Space.tight),
            groupsBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            groupsBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            groupsBar.heightAnchor.constraint(equalToConstant: 30),

            groupsStack.topAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.topAnchor),
            groupsStack.bottomAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.bottomAnchor),
            groupsStack.leadingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.leadingAnchor, constant: Space.step),
            groupsStack.trailingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.trailingAnchor, constant: -Space.step),
            groupsStack.heightAnchor.constraint(equalTo: groupsBar.frameLayoutGuide.heightAnchor),

            items.topAnchor.constraint(equalTo: groupsBar.bottomAnchor, constant: Space.hair),
            items.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.step),
            items.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.step),
            items.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Space.hair)
        ])
    }

    private func makeToolButton(_ title: String, symbol: String, action: Selector?) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: symbol)
        config.title = title
        config.imagePlacement = .top
        config.imagePadding = 1
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        config.baseForegroundColor = .ink
        config.baseBackgroundColor = .surface
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Typography.micro
            return attributes
        }
        let button = UIButton(configuration: config)
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
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
        items.reloadData()
        delegate?.palette(self, didPickBrush: brush)
    }

    /// Сохранили мозаику — она появилась в палитре, и это надо показать:
    /// вкладкой и тем, что она открыта.
    func showTemplates() {
        selectedSectionID = "templates"
        showGroups()
        items.reloadData()
        items.setContentOffset(.zero, animated: false)
        scrollGroupsToSelected()
    }

    /// Убрали мозаику — вкладка могла исчезнуть вместе с последней.
    func reloadTemplates() {
        showGroups()
        items.reloadData()
    }

    /// Вкладок много, и выбранная может оказаться за краем.
    private func scrollGroupsToSelected() {
        layoutIfNeeded()
        guard let index = sections.firstIndex(where: { $0.id == selectedSectionID }),
              index < groupsStack.arrangedSubviews.count else {
            return
        }
        let button = groupsStack.arrangedSubviews[index]
        groupsBar.scrollRectToVisible(button.frame.insetBy(dx: -Space.step, dy: 0), animated: true)
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

    /// Размер сменили не отсюда — например, взяли сохранённую мозаику
    /// другой формы.
    func showSide(_ side: Int) {
        guard let index = Self.sides.firstIndex(of: side) else {
            return
        }
        sizeControl.selectedSegmentIndex = index
    }

    // MARK: - Группы

    private enum Section: Equatable {
        case templates
        case recent
        case emoji(EmojiPalette.Group)

        var id: String {
            switch self {
            case .templates:            return "templates"
            case .recent:               return "recent"
            case .emoji(let group):     return group.id
            }
        }

        var title: String {
            switch self {
            case .templates:            return "мозаики"
            case .recent:               return "недавние"
            case .emoji(let group):     return group.title
            }
        }
    }

    /// Сначала своё — сохранённые мозаики и недавние кисти, — потом палитра.
    private var sections: [Section] {
        var sections: [Section] = []
        if !UserSettings.mosaicTemplates.isEmpty {
            sections.append(.templates)
        }
        if !UserSettings.mosaicBrushes.isEmpty {
            sections.append(.recent)
        }
        return sections + EmojiPalette.groups.map(Section.emoji)
    }

    private func showGroups() {
        let sections = self.sections
        if !sections.contains(where: { $0.id == selectedSectionID }) {
            selectedSectionID = sections.first?.id ?? ""
        }
        groupsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for section in sections {
            let isSelected = section.id == selectedSectionID
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            config.attributedTitle = AttributedString(section.title, attributes: AttributeContainer([
                .font: Typography.micro,
                .kern: Typography.narrow
            ]))
            config.baseForegroundColor = isSelected ? .surface : .inkMuted
            config.background.backgroundColor = isSelected ? .own : .surface
            config.background.cornerRadius = 11

            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedSectionID = section.id
                self?.showGroups()
                self?.items.reloadData()
                self?.items.setContentOffset(.zero, animated: false)
            }, for: .touchUpInside)
            groupsStack.addArrangedSubview(button)
        }
    }
}

// MARK: - Содержимое

extension MosaicPaletteView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    private var currentSection: Section? {
        sections.first { $0.id == selectedSectionID } ?? sections.first
    }

    private var currentEmojis: [String] {
        switch currentSection {
        case .recent:               return UserSettings.mosaicBrushes
        case .emoji(let group):     return group.emojis
        default:                    return []
        }
    }

    private var currentTemplates: [Mosaic] {
        currentSection == .templates ? UserSettings.mosaicTemplates : []
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        currentSection == .templates ? currentTemplates.count : currentEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if currentSection == .templates {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TemplateCell.reuseID, for: indexPath)
            (cell as? TemplateCell)?.show(currentTemplates[indexPath.item])
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath)
        let emoji = currentEmojis[indexPath.item]
        (cell as? EmojiCell)?.show(emoji, selected: emoji == brush)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if currentSection == .templates {
            delegate?.palette(self, didPickTemplate: currentTemplates[indexPath.item])
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }

        // Вкладка запомнена по имени, поэтому появление «недавних» её
        // не сдвигает.
        setBrush(currentEmojis[indexPath.item])
    }

    /// Долгое нажатие на сохранённую мозаику — убрать её.
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard currentSection == .templates else {
            return nil
        }
        let mosaic = currentTemplates[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Убрать", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    guard let self else { return }
                    self.delegate?.palette(self, didAskToDelete: mosaic)
                }
            ])
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Сохранённые мозаики крупнее: в клетку эмодзи рисунок не разглядеть.
        let columns: CGFloat = currentSection == .templates ? 4 : 8
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

/// Сохранённая мозаика — маленькой сеткой, какой её и узнают.
private final class TemplateCell: UICollectionViewCell {

    static let reuseID = "TemplateCell"

    private let grid: MosaicView = {
        let view = MosaicView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .surface
        contentView.layer.cornerRadius = 8
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ mosaic: Mosaic) {
        // Клетка подгоняется под самую длинную сторону: 8×8 должна влезать
        // целиком, иначе рисунок обрежется.
        let side = max(mosaic.columns, mosaic.rows)
        let available = bounds.width - 8
        grid.cellSize = max(3, floor(available / CGFloat(side)) - 1)
        grid.show(mosaic)
    }
}
