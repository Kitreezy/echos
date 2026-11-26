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

    private lazy var eraserButton = makeToolButton(String(localized: "ластик"), symbol: "eraser", action: #selector(pickEraser))
    private lazy var fillButton = makeToolButton(String(localized: "залить"), symbol: "paintbrush.fill", action: #selector(fillTapped))
    private lazy var clearButton = makeToolButton(String(localized: "очистить"), symbol: "trash", action: #selector(clearTapped))
    private lazy var customButton = makeToolButton(String(localized: "свой"), symbol: "keyboard", action: #selector(customTapped))

    /// Всё, что делают с готовым рисунком, — под одной кнопкой: ряд
    /// инструментов должен оставаться рядом для рисования.
    private lazy var moreButton: UIButton = {
        let button = makeToolButton(String(localized: "ещё"), symbol: "ellipsis", action: nil)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [
            UIAction(title: String(localized: "Сохранить мозаику"), image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.paletteDidAskToSaveTemplate(self)
            },
            UIAction(title: String(localized: "Сохранить картинку"), image: UIImage(systemName: "arrow.down.to.line")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.paletteDidAskToSaveImage(self)
            },
            UIAction(title: String(localized: "Поделиться картинкой"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
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
        // Кнопки делят ряд поровну, а не по длине подписи: на языке
        // длиннее русского последняя уезжала за край экрана. Нашла это
        // псевдолокализация с удвоенными строками.
        stack.distribution = .fill
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
        let collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.reuseID)
        collection.register(TemplateCell.self, forCellWithReuseIdentifier: TemplateCell.reuseID)
        collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        return collection
    }()

    /// Элементы сетки — через diffable data source: появление вкладки
    /// «недавние» или сохранённой мозаики анимируется, а не перерисовывает
    /// сетку молча. Обязанности — в основном теле класса: extensions не
    /// держат stored properties.
    private lazy var itemsDataSource =
        UICollectionViewDiffableDataSource<Section, PaletteItem>(collectionView: items) { [weak self] collectionView, indexPath, item in
            guard let self else {
                return UICollectionViewCell()
            }
            switch item {
            case .template(let mosaic):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TemplateCell.reuseID, for: indexPath)
                (cell as? TemplateCell)?.show(mosaic)
                return cell
            case .emoji(let emoji):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.reuseID, for: indexPath)
                (cell as? EmojiCell)?.show(emoji, selected: emoji == self.brush)
                return cell
            }
        }

    /// Сетка собирается композиционно: сохранённые мозаики — крупно в
    /// четыре колонки, эмодзи — восьмью. Высота группы привязана к ширине
    /// контейнера, поэтому клетки выходят квадратными сами, без ручного
    /// sizeForItemAt.
    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] _, _ in
            let columns = self?.currentSection == .templates ? 4 : 8
            let fraction = 1 / CGFloat(columns)
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(fraction),
                heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalWidth(fraction)
                ),
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(Space.hair)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = Space.hair
            return section
        }
    }

    // MARK: - Init

    convenience init() {
        self.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height))
        autoresizingMask = [.flexibleWidth]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .surfaceRaised
        setupLayout()
        items.dataSource = itemsDataSource
        sizeControl.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        showGroups()
        applyItems(animatingDifferences: false)
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
            fillButton.widthAnchor.constraint(equalTo: eraserButton.widthAnchor),
            clearButton.widthAnchor.constraint(equalTo: eraserButton.widthAnchor),
            customButton.widthAnchor.constraint(equalTo: eraserButton.widthAnchor),
            moreButton.widthAnchor.constraint(equalTo: eraserButton.widthAnchor),

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
        // Не влезла подпись — многоточие, а не перенос по буквам.
        config.titleLineBreakMode = .byTruncatingTail
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        config.baseForegroundColor = .ink
        config.baseBackgroundColor = .surface
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Typography.micro
            return attributes
        }
        let button = UIButton(configuration: config)
        // Сжиматься до равной доли ряда, а не держаться за длину подписи.
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        applyItems(animatingDifferences: true)
        refreshBrushSelection()
        delegate?.palette(self, didPickBrush: brush)
    }

    /// Снапшот пересобирается целиком; data source сам считает дельту и
    /// анимирует её — появление новой вкладки «недавние» или сохранённой
    /// мозаики больше не перерисовывает сетку молча.
    private func applyItems(animatingDifferences: Bool) {
        guard let section = currentSection else {
            return
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, PaletteItem>()
        snapshot.appendSections([section])
        snapshot.appendItems(currentItems(for: section))
        itemsDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    private func currentItems(for section: Section) -> [PaletteItem] {
        switch section {
        case .templates:
            return UserSettings.mosaicTemplates.map(PaletteItem.template)
        case .recent:
            return UserSettings.mosaicBrushes.map(PaletteItem.emoji)
        case .emoji(let group):
            return group.emojis.map(PaletteItem.emoji)
        }
    }

    /// Рамка выбранной кисти живёт вне содержимого элементов. Равные
    /// элементы снапшот не перерисовывает, поэтому после смены кисти
    /// ячейки обновляются отдельно — reconfigure, а не повторный apply.
    private func refreshBrushSelection() {
        var snapshot = itemsDataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        itemsDataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Сохранили мозаику — она появилась в палитре, и это надо показать:
    /// вкладкой и тем, что она открыта.
    func showTemplates() {
        selectedSectionID = "templates"
        showGroups()
        applyItems(animatingDifferences: true)
        items.setContentOffset(.zero, animated: false)
        scrollGroupsToSelected()
    }

    /// Убрали мозаику — вкладка могла исчезнуть вместе с последней.
    func reloadTemplates() {
        showGroups()
        applyItems(animatingDifferences: true)
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

    private enum Section: Hashable {
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

        // Вкладки сравниваются и хэшируются по имени: экземпляр группы
        // пересоздаётся на каждый доступ, а секция в снапшоте должна
        // оставаться той же.
        static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var title: String {
            switch self {
            case .templates:            return String(localized: "мозаики")
            case .recent:               return String(localized: "недавние")
            case .emoji(let group):     return group.title
            }
        }
    }

    /// Элемент сетки: кисть или сохранённая мозаика. Одинаковый эмодзи
    /// дважды в одну секцию не попадает: палитра дедуплицирует его сама,
    /// недавние кисти — тоже.
    private enum PaletteItem: Hashable {
        case emoji(String)
        case template(Mosaic)
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
                self?.applyItems(animatingDifferences: true)
                self?.items.setContentOffset(.zero, animated: false)
            }, for: .touchUpInside)
            groupsStack.addArrangedSubview(button)
        }
    }
}

// MARK: - Содержимое

extension MosaicPaletteView: UICollectionViewDelegate {

    private var currentSection: Section? {
        sections.first { $0.id == selectedSectionID } ?? sections.first
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Элемент берём у data source: сетка могла обновиться после касания.
        guard let item = itemsDataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .template(let mosaic):
            delegate?.palette(self, didPickTemplate: mosaic)
            UISelectionFeedbackGenerator().selectionChanged()
        case .emoji(let emoji):
            // Вкладка запомнена по имени, поэтому появление «недавних» её
            // не сдвигает.
            setBrush(emoji)
        }
    }

    /// Долгое нажатие на сохранённую мозаику — убрать её.
    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard case .template(let mosaic) = itemsDataSource.itemIdentifier(for: indexPath) else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: String(localized: "Убрать"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    guard let self else { return }
                    self.delegate?.palette(self, didAskToDelete: mosaic)
                }
            ])
        }
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
