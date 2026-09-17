//
//  MosaicComposerViewController.swift
//  echos
//
//  Набор мозаики: размер, сетка, палитра.
//
//  Рисуется без клавиатуры. Кисть берётся из палитры внизу — эмодзи там
//  разложены по тому, как они выглядят, а не по назначению, и первыми идут
//  квадраты и круги: из них складываются пиксели. Красить можно нажатием и
//  протягиванием; той же кистью по клетке — стереть, есть и ластик. Свой
//  эмодзи, которого в палитре нет, набирается по отдельной кнопке — это
//  единственное место, где появляется клавиатура.
//

import UIKit

final class MosaicComposerViewController: UIViewController {

    /// Что делать с готовой мозаикой. Вызывается один раз, перед закрытием.
    var onSend: ((Mosaic) -> Void)?

    /// Стороны на выбор. Квадраты — потому что так рисуют чаще всего; сама
    /// сетка умеет и прямоугольники, выбор появится, когда понадобится.
    private static let sides = [2, 3, 4, 5, 6, 8]

    private var mosaic = Mosaic(columns: 4, rows: 4)

    /// Чем красим. Пустая кисть — ластик.
    private var brush = "" {
        didSet { brushChanged() }
    }

    private var selectedGroup = 0

    private let feedback = UISelectionFeedbackGenerator()

    // MARK: - UI

    private let sizeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: MosaicComposerViewController.sides.map { "\($0)×\($0)" })
        control.selectedSegmentIndex = 2
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let grid: MosaicView = {
        let view = MosaicView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Что сейчас в руке: кисть крупно, рядом — что с ней можно сделать.
    private let brushPreview: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 30)
        label.textAlignment = .center
        label.backgroundColor = .surfaceRaised
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var eraserButton = makeToolButton("ластик", symbol: "eraser", action: #selector(pickEraser))
    private lazy var fillButton = makeToolButton("залить", symbol: "paintbrush.fill", action: #selector(fillEmpty))
    private lazy var clearButton = makeToolButton("очистить", symbol: "trash", action: #selector(clearAll))
    private lazy var customButton = makeToolButton("свой", symbol: "keyboard", action: #selector(typeCustom))

    private lazy var toolsRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [brushPreview, eraserButton, fillButton, clearButton, customButton])
        stack.axis = .horizontal
        stack.spacing = Space.tight
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Скрытое поле для своего эмодзи. Появляется только по кнопке «свой».
    private let customField: UITextField = {
        let field = UITextField()
        field.font = .systemFont(ofSize: 28)
        field.textAlignment = .center
        field.returnKeyType = .done
        field.backgroundColor = .surfaceRaised
        field.layer.cornerRadius = 10
        field.tintColor = .own
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isHidden = true
        return field
    }()

    /// Скрытое поле не должно занимать место: высота у него ноль, пока
    /// его не позвали.
    private lazy var customFieldHeight = customField.heightAnchor.constraint(equalToConstant: 0)

    private lazy var groupsBar: UIScrollView = {
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

    private lazy var palette: UICollectionView = {
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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .surface
        title = "Мозаика"

        // Отправка — в шапке: её не перекроет ни палитра, ни клавиатура.
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Отправить", style: .done, target: self, action: #selector(sendTapped))
        navigationItem.rightBarButtonItem?.tintColor = .own
        navigationItem.leftBarButtonItem?.tintColor = .ink

        setupLayout()

        sizeControl.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)
        customField.delegate = self
        customField.addTarget(self, action: #selector(customChanged), for: .editingChanged)

        grid.onTap = { [weak self] column, row in
            self?.paint(column: column, row: row, toggling: true)
        }
        grid.onDrag = { [weak self] column, row in
            self?.paint(column: column, row: row, toggling: false)
        }

        // Нажатие мимо поля убирает клавиатуру — если она вообще была.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        showGroups()
        brush = UserSettings.mosaicBrushes.first ?? EmojiPalette.groups[0].emojis[0]
    }

    private var laidOutWidth: CGFloat = 0

    /// Размер клетки зависит от ширины, а она известна только здесь.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width != laidOutWidth else {
            return
        }
        laidOutWidth = view.bounds.width
        showGrid()
        palette.collectionViewLayout.invalidateLayout()
    }

    private func setupLayout() {
        [sizeControl, grid, toolsRow, customField, groupsBar, palette].forEach(view.addSubview)
        groupsBar.addSubview(groupsStack)

        NSLayoutConstraint.activate([
            sizeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Space.tight),
            sizeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Space.margin),
            sizeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Space.margin),

            grid.topAnchor.constraint(equalTo: sizeControl.bottomAnchor, constant: Space.step),
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            toolsRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: Space.step),
            toolsRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolsRow.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Space.margin),
            brushPreview.widthAnchor.constraint(equalToConstant: 52),
            brushPreview.heightAnchor.constraint(equalToConstant: 52),

            customField.topAnchor.constraint(equalTo: toolsRow.bottomAnchor, constant: Space.tight),
            customField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            customField.widthAnchor.constraint(equalToConstant: 80),
            customFieldHeight,

            groupsBar.topAnchor.constraint(equalTo: customField.bottomAnchor, constant: Space.tight),
            groupsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            groupsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            groupsBar.heightAnchor.constraint(equalToConstant: 36),

            groupsStack.topAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.topAnchor),
            groupsStack.bottomAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.bottomAnchor),
            groupsStack.leadingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.leadingAnchor, constant: Space.margin),
            groupsStack.trailingAnchor.constraint(equalTo: groupsBar.contentLayoutGuide.trailingAnchor, constant: -Space.margin),
            groupsStack.heightAnchor.constraint(equalTo: groupsBar.frameLayoutGuide.heightAnchor),

            palette.topAnchor.constraint(equalTo: groupsBar.bottomAnchor, constant: Space.tight),
            palette.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Space.margin),
            palette.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Space.margin),
            palette.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Space.tight)
        ])
    }

    private func makeToolButton(_ title: String, symbol: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: symbol)
        config.title = title
        config.imagePlacement = .top
        config.imagePadding = 2
        config.baseForegroundColor = .ink
        config.baseBackgroundColor = .surfaceRaised
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = Typography.micro
            return attributes
        }
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Сетка

    private func showGrid() {
        // Клетки — по ширине экрана, но не больше 44, и в высоту сетка
        // не должна съедать палитру: на 8×8 клетка меньше.
        let available = view.bounds.width - 2 * Space.margin
        let byWidth = (available - CGFloat(mosaic.columns - 1) * Space.hair) / CGFloat(mosaic.columns)
        let byHeight = (view.bounds.height * 0.42) / CGFloat(mosaic.rows)
        grid.cellSize = min(44, byWidth, byHeight)
        grid.show(mosaic)
        updateSend()
    }

    /// `toggling` — нажатие: та же кисть по той же клетке стирает.
    /// Протягивание не стирает: палец, прошедший по уже покрашенной
    /// клетке, не должен её снимать.
    private func paint(column: Int, row: Int, toggling: Bool) {
        let current = mosaic[column, row]
        let next: String
        if brush.isEmpty {
            next = ""
        } else if toggling && current == brush {
            next = ""
        } else {
            next = brush
        }

        guard next != current else {
            return
        }
        mosaic = mosaic.setting(column: column, row: row, to: next)
        grid.show(mosaic)
        feedback.selectionChanged()
        updateSend()
    }

    private func updateSend() {
        navigationItem.rightBarButtonItem?.isEnabled = !mosaic.isEmpty
    }

    @objc
    private func sizeChanged() {
        let side = Self.sides[sizeControl.selectedSegmentIndex]

        // Нарисованное переносится, насколько влезает: сменить размер на
        // ходу и потерять всё — обидно.
        var resized = Mosaic(columns: side, rows: side)
        for row in 0..<min(side, mosaic.rows) {
            for column in 0..<min(side, mosaic.columns) {
                resized = resized.setting(column: column, row: row, to: mosaic[column, row])
            }
        }
        mosaic = resized
        showGrid()
    }

    // MARK: - Инструменты

    @objc
    private func pickEraser() {
        brush = ""
    }

    /// Все пустые клетки — кистью. Фон одним нажатием.
    @objc
    private func fillEmpty() {
        guard !brush.isEmpty else {
            return
        }
        for row in 0..<mosaic.rows {
            for column in 0..<mosaic.columns where mosaic[column, row].isEmpty {
                mosaic = mosaic.setting(column: column, row: row, to: brush)
            }
        }
        grid.show(mosaic)
        feedback.selectionChanged()
        updateSend()
    }

    @objc
    private func clearAll() {
        mosaic = Mosaic(columns: mosaic.columns, rows: mosaic.rows)
        grid.show(mosaic)
        updateSend()
    }

    @objc
    private func typeCustom() {
        customField.isHidden = false
        customFieldHeight.constant = 44
        customField.text = ""
        customField.becomeFirstResponder()
    }

    @objc
    private func customChanged() {
        guard let last = customField.text?.last else {
            return
        }
        // Один знак. Набрали несколько — остаётся последний.
        brush = String(last)
        customField.text = brush
    }

    @objc
    private func dismissKeyboard() {
        customField.resignFirstResponder()
        customField.isHidden = true
        customFieldHeight.constant = 0
    }

    // MARK: - Кисть

    private func brushChanged() {
        brushPreview.text = brush.isEmpty ? "⌫" : brush
        eraserButton.isSelected = brush.isEmpty
        eraserButton.configuration?.baseBackgroundColor = brush.isEmpty ? .own : .surfaceRaised
        eraserButton.configuration?.baseForegroundColor = brush.isEmpty ? .surface : .ink

        if !brush.isEmpty {
            UserSettings.rememberBrush(brush)
        }
        palette.reloadData()
    }

    // MARK: - Палитра

    /// Первая группа — недавние: то, чем рисовали, под рукой. Дальше —
    /// палитра как есть.
    private var groups: [EmojiPalette.Group] {
        let recent = UserSettings.mosaicBrushes
        let recentGroup = EmojiPalette.Group(id: "recent", title: "недавние", emojis: recent)
        return (recent.isEmpty ? [] : [recentGroup]) + EmojiPalette.groups
    }

    private func showGroups() {
        groupsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, group) in groups.enumerated() {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            config.attributedTitle = AttributedString(group.title, attributes: AttributeContainer([
                .font: Typography.micro,
                .kern: Typography.narrow
            ]))
            config.baseForegroundColor = index == selectedGroup ? .surface : .inkMuted
            config.background.backgroundColor = index == selectedGroup ? .own : .surfaceRaised
            config.background.cornerRadius = 14

            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedGroup = index
                self?.showGroups()
                self?.palette.reloadData()
                self?.palette.setContentOffset(.zero, animated: false)
            }, for: .touchUpInside)
            groupsStack.addArrangedSubview(button)
        }
    }

    // MARK: - Действия

    @objc
    private func sendTapped() {
        guard !mosaic.isEmpty else {
            return
        }
        onSend?(mosaic)
        dismiss(animated: true)
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Палитра

extension MosaicComposerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

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
        brush = currentEmojis[indexPath.item]
        feedback.selectionChanged()
        // Недавние поменялись — первая группа могла появиться или
        // перестроиться, а выбранная остаётся той же по смыслу.
        let hadRecent = groups.first?.id == "recent"
        showGroups()
        if !hadRecent, groups.first?.id == "recent" {
            selectedGroup += 1
            showGroups()
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        // Восемь в ряд, сколько бы ни было места.
        let columns: CGFloat = 8
        let side = (collectionView.bounds.width - (columns - 1) * Space.hair) / columns
        return CGSize(width: floor(side), height: floor(side))
    }
}

extension MosaicComposerViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        dismissKeyboard()
        return true
    }
}

/// Один эмодзи в палитре. Выбранный — с рамкой цвета своих сообщений.
private final class EmojiCell: UICollectionViewCell {

    static let reuseID = "EmojiCell"

    private let label: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 26)
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
        contentView.backgroundColor = selected ? .surfaceRaised : .clear
    }
}
