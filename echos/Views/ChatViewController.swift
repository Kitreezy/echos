//
//  ChatViewController.swift
//  echos
//
//  Created by Artem Rodionov on 16.02.2026.
//

import UIKit
import SwiftUI

final class ChatViewController: UIViewController {
    
    private let sharedViewModel: ChatViewModel
    
    // MARK: - ViewModel
    
    private var viewModel: ChatViewModel {
        return sharedViewModel
    }
    
    // MARK: - UI
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.separatorStyle = .none
        table.backgroundColor = .surface
        table.keyboardDismissMode = .interactive
        table.allowsSelection = false
        table.translatesAutoresizingMaskIntoConstraints = false
        table.estimatedRowHeight = 80
        table.rowHeight = UITableView.automaticDimension
        
        return table
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let typingLabel: UILabel = {
        let label = UILabel()
        label.textColor = .tertiaryLabel
        label.font = .italicSystemFont(ofSize: 13)
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let emptyStateView: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = "Нет сообщений\nНачни общаться!"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(icon)
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -30),
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),
        ])
        
        return container
    }()
    
    private let inputContainer: UIView = {
        // Панель отделена от переписки волосяной линией, а не тенью:
        // тень на чёрном всё равно не видна, зато добавляет слой.
        let view = UIView()
        view.backgroundColor = .surface
        view.translatesAutoresizingMaskIntoConstraints = false

        let hairline = UIView()
        hairline.backgroundColor = .hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hairline)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: view.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        return view
    }()
    
    private let textField: UITextField = {
        let textField = UITextField()
        textField.attributedPlaceholder = NSAttributedString(
            string: "Сообщение",
            attributes: [.foregroundColor: UIColor.inkMuted]
        )
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .ink
        textField.font = Typography.body
        textField.tintColor = .own
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.returnKeyType = .send
        
        return textField
    }()
    
    /// Вход в набор мозаики — слева от поля, где обычно живёт вложение.
    private let mosaicButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "square.grid.3x3")
        config.baseForegroundColor = .inkMuted
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let sendButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.up")
        config.baseForegroundColor = .own
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    private var typingAnimationTimer: Timer?
    private var typingDots = 0
    private var currentTypingPeer: String?

    // MARK: - Мозаика

    /// Черновик живёт, пока его не отправили или не очистили: закрыть
    /// палитру и вернуться к нему можно сколько угодно.
    private var mosaicDraft = Mosaic(columns: 4, rows: 4)
    private var isComposingMosaic = false

    /// Ждём один эмодзи с настоящей клавиатуры — для кисти, которой нет в
    /// палитре. Пока ждём, набранное — не сообщение.
    private var awaitingCustomBrush = false

    private lazy var palette: MosaicPaletteView = {
        let palette = MosaicPaletteView()
        palette.delegate = self
        return palette
    }()

    private lazy var draftView: MosaicDraftView = {
        let view = MosaicDraftView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.onTap = { [weak self] column, row in
            self?.paint(column: column, row: row, toggling: true)
        }
        view.onDrag = { [weak self] column, row in
            self?.paint(column: column, row: row, toggling: false)
        }
        return view
    }()
    
    // MARK: Init
    
    init(viewModel: ChatViewModel) {
        self.sharedViewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
     
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(false, animated: animated)
        
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil

        restoreMosaicDraft()

        // Пока экран чата на экране, входящее в него — прочитанное, и
        // баннер о нём не нужен.
        viewModel.isConversationOnScreen = true
    }

    /// Набросок этой переписки — сразу на экран, без палитры: видно, что
    /// начатое не пропало, а дорисовать можно кнопкой сетки.
    private func restoreMosaicDraft() {
        guard let address = viewModel.currentConversationPeer,
              let saved = UserSettings.mosaicDraft(for: address) else {
            return
        }
        mosaicDraft = saved
        draftView.show(mosaicDraft)
        draftView.isHidden = false
        updateMosaicChrome()
    }

    /// Открытый чат начинается с конца — с последних сообщений. Крутить
    /// ленту до раскладки бесполезно: у неё ещё нет размера, — поэтому
    /// первый раз это делается здесь, после раскладки, без анимации.
    private var needsScrollToBottom = true

    /// Черновик лежит поверх ленты и не должен закрывать последние
    /// сообщения: лента получает отступ снизу на его высоту.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let inset = draftView.isHidden ? 0 : draftView.bounds.height + Space.tight
        let insetChanged = tableView.contentInset.bottom != inset
        if insetChanged {
            tableView.contentInset.bottom = inset
            tableView.verticalScrollIndicatorInsets.bottom = inset
        }

        if needsScrollToBottom || insetChanged {
            needsScrollToBottom = false
            scrollToBottom(animated: false)
        }
    }

    private func saveMosaicDraft() {
        guard let address = viewModel.currentConversationPeer else {
            return
        }
        UserSettings.setMosaicDraft(mosaicDraft, for: address)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "echos"
        view.backgroundColor = .surface
        
        setupNavigationBar()
        setupLayout()
        setupTableView()
        setupGestures()
        bindViewModel()
        setupAppLifecycleObservers()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.isConversationOnScreen = false

        print("[lifecycle] ChatViewController viewWillDisappear (isMovingFromParent: \(isMovingFromParent))")
        stopTypingAnimation()
    }
    
    // MARK: - App Lifecycle
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil
        )
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil
        )
    }
    
    // MARK: - Navigation Bar
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backToDiscovery)
        )
        
        // В заголовке имя, а не адрес: отпечаток ключа человеку ни о чём
        // не говорит.
        if let peerName = viewModel.currentConversationName {
            title = peerName
            // Приписка над заголовком — если собеседника мы не узнаём.
            // Именно здесь она нужнее всего: обмануть можно того, кто пишет,
            // а не того, кто смотрит на список.
            navigationItem.prompt = conversationNote()
        } else {
            title = "echos"
        }
        
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: createMainMenu()
        )

        // Стена — половина смысла переписки, а не служебный пункт. В меню
        // третьим сверху её никто не находил.
        var items = [menuButton]

        if viewModel.currentConversationPeer != nil {
            items.append(UIBarButtonItem(
                image: UIImage(systemName: "scribble.variable"),
                style: .plain,
                target: self,
                action: #selector(openPeerWall)
            ))
        }

        navigationItem.rightBarButtonItems = items
    }

    @objc
    private func openPeerWall() {
        guard let address = viewModel.currentConversationPeer else {
            return
        }

        showWall(of: address)
    }

    // MARK: - Layout
    
    private lazy var layoutConstraints: [NSLayoutConstraint] = {
        [
            // Status label
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Table
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.widthAnchor.constraint(equalTo: tableView.widthAnchor),
            
            // Typing
            typingLabel.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 4),
            typingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            typingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            typingLabel.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -4),
            
            // InputContainer
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 64),
            inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: 0),
            
            // Черновик мозаики — над полем ввода, справа, как своё сообщение.
            draftView.bottomAnchor.constraint(equalTo: typingLabel.topAnchor, constant: -Space.tight),
            draftView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Space.margin),

            // Мозаика
            mosaicButton.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 4),
            mosaicButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            mosaicButton.widthAnchor.constraint(equalToConstant: 40),
            mosaicButton.heightAnchor.constraint(equalToConstant: 40),

            // TextField
            textField.leadingAnchor.constraint(equalTo: mosaicButton.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            textField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 40),
            
            // Send button
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40)
        ]
    }()
    
    private func setupLayout() {
        view.addSubview(statusLabel)

        // Строка с адресом нажимается: объясняет, зачем он и как сверить.
        statusLabel.isUserInteractionEnabled = true
        statusLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(explainAddress))
        )
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(typingLabel)
        view.addSubview(inputContainer)
        inputContainer.addSubview(mosaicButton)
        inputContainer.addSubview(textField)
        inputContainer.addSubview(sendButton)
        view.addSubview(draftView)
        
        NSLayoutConstraint.activate(layoutConstraints)
        
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        mosaicButton.addTarget(self, action: #selector(composeMosaic), for: .touchUpInside)
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }
    
    /// Открытый ряд реакций — над одним сообщением за раз.
    private var reactionPicker: ReactionPickerView?

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self

        // Нажатие на сообщение — ряд реакций. Одно нажатие свободно:
        // выделение — долгое, ссылки — свои, и они отсеиваются в делегате.
        let tap = UITapGestureRecognizer(target: self, action: #selector(messageTapped))
        tap.delegate = self
        tableView.addGestureRecognizer(tap)
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseID)
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tapGesture)
    }
    
    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Binding
    
    /// Подписка на @Observable ViewModel через withObservationTracking.
    /// При каждом изменении observed-свойства вызывается onChange -  перегружаем UI.
    private func bindViewModel() {
        // Первый показ: без этого вызова заглушка «Нет сообщений» висит
        // поверх уже загруженной переписки, пока что-нибудь не изменится.
        updateUI()
        scheduleObservation()
    }
    
    private func scheduleObservation() {
        withObservationTracking {
            let _ = viewModel.messages
            let _ = viewModel.connectionStatus
            let _ = viewModel.typingPeerName
        } onChange: { [weak self] in
            // onChange прилетает вне главного актора и вне изоляции вьюхи,
            // поэтому возвращаемся на него явно через Task { @MainActor }.
            Task { @MainActor in
                guard let self else { return }
                self.updateUI()
                self.scheduleObservation()  // переподписка
            }
        }
    }
    
    private func updateUI() {
        statusLabel.text = viewModel.connectionStatus
        emptyStateView.isHidden = !viewModel.messages.isEmpty
        
        tableView.reloadData()
        // До первого показа крутить нечего: лента ещё без размера, за это
        // отвечает раскладка. Дальше — плавно, как и положено новому
        // сообщению.
        if view.window != nil {
            scrollToBottom(animated: true)
        }
        
        updateMenu()
        
        if let peerName = viewModel.typingPeerName {
            if currentTypingPeer != peerName {
                currentTypingPeer = peerName
                startTypingAnimation(peerName: peerName)
            }
        } else {
            currentTypingPeer = nil
            stopTypingAnimation()
        }
    }
    
    // MARK: - Actions
    
    /// Мозаика — часть печатания: вместо клавиатуры выезжает палитра, над
    /// полем появляется черновик. Повторное нажатие убирает палитру,
    /// черновик остаётся до отправки.
    @objc
    private func composeMosaic() {
        setComposingMosaic(!isComposingMosaic)
    }

    private func setComposingMosaic(_ composing: Bool) {
        isComposingMosaic = composing
        awaitingCustomBrush = false

        if composing {
            textField.text = ""
            textField.inputView = palette
            textField.reloadInputViews()
            textField.becomeFirstResponder()
            draftView.show(mosaicDraft)
            draftView.isHidden = false
        } else {
            textField.inputView = nil
            textField.reloadInputViews()
            textField.resignFirstResponder()
            // Начатое остаётся на виду и без палитры: так видно, что оно
            // не пропало. Пустой черновик показывать незачем.
            draftView.isHidden = mosaicDraft.isEmpty
        }

        updateMosaicChrome()
    }

    /// Кнопка сетки и подсказка в поле говорят, в каком мы режиме — и что
    /// черновик есть, даже когда палитра убрана.
    private func updateMosaicChrome() {
        let hasDraft = !mosaicDraft.isEmpty
        mosaicButton.configuration?.baseForegroundColor = isComposingMosaic || hasDraft ? .own : .inkMuted
        textField.attributedPlaceholder = NSAttributedString(
            string: isComposingMosaic ? "мозаика · стрелка отправит" : "Сообщение",
            attributes: [.foregroundColor: UIColor.inkMuted]
        )
    }

    /// `toggling` — нажатие: та же кисть по той же клетке стирает.
    /// Протягивание не стирает: палец, прошедший по уже покрашенной
    /// клетке, не должен её снимать.
    private func paint(column: Int, row: Int, toggling: Bool) {
        let brush = palette.brush
        let current = mosaicDraft[column, row]
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
        mosaicDraft = mosaicDraft.setting(column: column, row: row, to: next)
        draftView.show(mosaicDraft)
        UISelectionFeedbackGenerator().selectionChanged()
        updateMosaicChrome()
        saveMosaicDraft()
    }

    // MARK: - Реакции

    @objc
    private func messageTapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: tableView)

        // Ряд открыт — любое нажатие мимо него закрывает.
        if reactionPicker != nil {
            dismissReactionPicker()
            return
        }

        guard let indexPath = tableView.indexPathForRow(at: point),
              let cell = tableView.cellForRow(at: indexPath) else {
            return
        }
        let message = viewModel.messages[indexPath.row]

        let picker = ReactionPickerView(current: message.myReaction)
        picker.onPick = { [weak self] emoji in
            self?.dismissReactionPicker()
            Task {
                await self?.viewModel.react(to: message.id, with: emoji)
            }
        }
        tableView.addSubview(picker)
        reactionPicker = picker

        // Над сообщением, с его стороны: своё — справа, чужое — слева.
        var constraints = [
            picker.bottomAnchor.constraint(equalTo: cell.topAnchor, constant: -Space.hair),
            picker.heightAnchor.constraint(equalToConstant: 44)
        ]
        if message.isFromMe {
            constraints.append(picker.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Space.margin))
        } else {
            constraints.append(picker.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Space.margin))
        }
        NSLayoutConstraint.activate(constraints)

        picker.alpha = 0
        picker.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            picker.alpha = 1
            picker.transform = .identity
        }
    }

    private func dismissReactionPicker() {
        guard let picker = reactionPicker else {
            return
        }
        reactionPicker = nil
        UIView.animate(withDuration: 0.15, animations: {
            picker.alpha = 0
        }, completion: { _ in
            picker.removeFromSuperview()
        })
    }

    @objc
    private func sendTapped() {
        if isComposingMosaic {
            guard !mosaicDraft.isEmpty else {
                return
            }
            let mosaic = mosaicDraft
            Task {
                await viewModel.sendMosaic(mosaic)
            }
            mosaicDraft = Mosaic(columns: mosaic.columns, rows: mosaic.rows)
            saveMosaicDraft()
            setComposingMosaic(false)
            return
        }

        guard let text = textField.text, !text.isEmpty else {
            return
        }
        Task {
            await viewModel.sendMessage(text)
        }
        textField.text = ""
    }
    
    @objc
    private func textFieldDidChange() {
        if awaitingCustomBrush {
            guard let last = textField.text?.last else {
                return
            }
            // Один знак — и обратно к палитре.
            textField.text = ""
            awaitingCustomBrush = false
            palette.setBrush(String(last))
            textField.inputView = palette
            textField.reloadInputViews()
            return
        }

        guard let text = textField.text, !text.isEmpty else {
            viewModel.stopTyping()
            return
        }
        
        viewModel.startTyping()
    }
    
    @objc
    private func appDidEnterBackground() {
        stopTypingAnimation()
    }
    
    @objc
    private func appWillEnterForeground() {

    }
    
    @objc
    private func backToDiscovery() {
        navigationController?.popViewController(animated: true)
    }
    
    // MARK: - Main Menu (UIMenu)
    
    private func createMainMenu() -> UIMenu {
        let navigationSection = UIMenu(title: "", options: .displayInline, children: [
            UIAction(
                title: "Все чаты",
                image: UIImage(systemName: "bubble.left.and.bubble.right")
            ) { [weak self] _ in
                self?.showConversationsList()
            },
            
            UIAction(
                title: "Устройства поблизости",
                image: UIImage(systemName: "antenna.radiowaves.left.and.right")
            ) { [weak self] _ in
                self?.showPeersList()
            },

            UIAction(
                title: "Связи",
                image: UIImage(systemName: "point.3.connected.trianglepath.dotted")
            ) { [weak self] _ in
                self?.showPeersNetwork()
            },

            UIAction(
                title: "Моя стена",
                image: UIImage(systemName: "scribble")
            ) { [weak self] _ in
                self?.showWall(of: nil)
            }
        ])
        
        var chatSection: UIMenu?
        if let address = viewModel.currentConversationPeer {
            let peerName = viewModel.currentConversationName ?? address
            chatSection = UIMenu(title: "Чат с '\(peerName)'", options: .displayInline, children: [
                UIAction(
                    title: "Стена '\(peerName)'",
                    image: UIImage(systemName: "scribble.variable")
                ) { [weak self] _ in
                    self?.showWall(of: address)
                },

                UIAction(
                    title: "Отключиться",
                    image: UIImage(systemName: "link.badge.minus"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.confirmDisconnect()
                },
                
                UIAction(
                    title: "Очистить историю",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.confirmClearCurrentConversation()
                }
            ])
        }
        
        let generalSection = UIMenu(title: "", options: .displayInline, children: [
            UIAction(
                title: "Очистить всю историю",
                image: UIImage(systemName: "trash.fill"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmClearAllMessages()
            }
        ])
        
        var children: [UIMenuElement] = [navigationSection]
        if let chatSection = chatSection {
            children.append(chatSection)
        }
        children.append(generalSection)
        
        return UIMenu(title: "", children: children)
    }
    
    // MARK: - Menu Update
    
    private func updateMenu() {
        if let menuButton = navigationItem.rightBarButtonItems?.first {
            menuButton.menu = createMainMenu()
        }
    }
    
    // MARK: - History Menu
    
    // MARK: - Disconnect Confirmation
    
    private func confirmDisconnect() {
        guard let peerName = viewModel.currentConversationName
                ?? viewModel.currentConversationPeer else {
            return
        }
        
        let alert = UIAlertController(title: "Отключиться?",
                                      message: "Вы будете отключены от '\(peerName)'. История сохранится.",
                                      preferredStyle: .alert)
        
        let disconnectAction = UIAlertAction(title: "Отключиться",
                                             style: .destructive) { [weak self] _ in
            self?.viewModel.disconnectFromCurrentPeer()
            print("[ChatViewController] Disconnected from  '\(peerName)'... [DONE]")
        }
        
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel)
        
        alert.addAction(disconnectAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    // MARK: - Clear Confirmations
    
    private func confirmClearCurrentConversation() {
        guard let peerName = viewModel.currentConversationName
                ?? viewModel.currentConversationPeer else {
            return
        }
        
        let alert = UIAlertController(title: "Очистить чат?",
                                      message: "Вы действительно хотите очистить весь чат с \(peerName)?",
                                      preferredStyle: .alert)
        
        let deleteAction = UIAlertAction(title: "Очистить",
                                         style: .destructive) { [weak self] _ in
            Task {
                do {
                    try await self?.viewModel.clearCurrentConversation()
                    await MainActor.run {
                        self?.updateUI()
                    }
                    print("[ChatViewController] Cleared conversation with '\(peerName)'")
                }
                catch {
                    print("[ChatViewController] Failed to clear: \(error)")
                    await MainActor.run {
                        self?.showError("Не удалось очистить историю")
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Отмена",
                                         style: .cancel)
        
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func confirmClearAllMessages() {
        let alert = UIAlertController(
            title: "Очистить всю историю?",
            message: "Все сообщения со всеми устройствами будут удалены.",
            preferredStyle: .alert
        )
        
        let deleteAction = UIAlertAction(title: "Удалить всё", style: .destructive) { [weak self] _ in
            Task {
                do {
                    try await self?.viewModel.clearAllMessages()
                    await MainActor.run {
                        self?.updateUI()
                    }
                    print("[ChatViewController] Cleared all messages")
                } catch {
                    print("[ChatViewController] Failed to clear all: \(error)")
                    await MainActor.run {
                        self?.showError("Не удалось очистить историю")
                    }
                }
            }
        }
        
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel)
        
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    // MARK: - Helpers
    
    private func scrollToBottom(animated: Bool) {
        guard !viewModel.messages.isEmpty else {
            return
        }
        let idx = IndexPath(row: viewModel.messages.count - 1, section: 0)
        tableView.scrollToRow(at: idx, at: .bottom, animated: animated)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Ошибка",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Routing
    
    @objc
    private func showPeersList() {
        let peersView = PeersListView(viewModel: viewModel)
        let hostingVC = UIHostingController(rootView: peersView)
        navigationController?.pushViewController(hostingVC, animated: true)
    }
    
    /// Стена: своя (`owner == nil`) или собеседника.
    /// Что сказать о собеседнике над заголовком. `nil` — говорить нечего.
    private func conversationNote() -> String? {
        guard let address = viewModel.currentConversationPeer,
              let name = viewModel.currentConversationName else {
            return nil
        }

        let recognition = viewModel.recognizer.recognize(address: address, name: name)
        return recognition.deservesAttention ? recognition.note : nil
    }

    /// Зачем под именем адрес и что с ним делать.
    ///
    /// Показывается только когда адрес на экране есть: вне чата и без связи
    /// строка про другое, и объяснять там нечего.
    @objc
    private func explainAddress() {
        guard let address = viewModel.currentConversationPeer,
              viewModel.connectionStatus.hasPrefix("зашифровано") else {
            return
        }

        let alert = UIAlertController(
            title: Fingerprint.display(address),
            message: "Переписка зашифрована между вашими устройствами: "
                   + "сервер её переносит, но прочитать не может.\n\n"
                   + Fingerprint.howToCheck,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Скопировать", style: .default) { _ in
            UIPasteboard.general.string = Fingerprint.display(address)
        })
        alert.addAction(UIAlertAction(title: "Понятно", style: .cancel))
        present(alert, animated: true)
    }

    /// `owner` — адрес владельца стены, `nil` для своей.
    private func showWall(of owner: String?) {
        guard let transport = viewModel.multipeerService else {
            return
        }

        let wall = WallView(
            viewModel: WallViewModel(owner: owner, transport: transport),
            ownAddress: transport.myAddress
        )
        navigationController?.pushViewController(UIHostingController(rootView: wall),
                                                 animated: true)
    }

    /// Общая картина: кто на связи, кто рядом, с кем связь потеряна.
    /// В отличие от «Устройств поблизости», сгруппировано по состоянию.
    @objc
    private func showPeersNetwork() {
        let networkView = PeersNetworkView(
            viewModel: viewModel,
            onOpenChat: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onNewScan: { [weak self] in
                self?.navigationController?.popToRootViewController(animated: true)
            }
        )
        let hostingVC = UIHostingController(rootView: networkView)
        navigationController?.pushViewController(hostingVC, animated: true)
    }

    @objc
    private func showConversationsList() {
        let conversationsView = ConversationsListView(viewModel: viewModel)
        let hostingVC = UIHostingController(rootView: conversationsView)
        navigationController?.pushViewController(hostingVC, animated: true)
    }
    
    // MARK: - Typing Animation
    
    private func startTypingAnimation(peerName: String) {
        stopTypingAnimation()
        
        typingLabel.isHidden = false
        typingDots = 0
        
        typingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5,
                                                    repeats: true) { [weak self] _ in
            // Timer со scheduledTimer всегда стреляет на главном run loop,
            // но замыкание для компилятора — @Sendable и nonisolated.
            // assumeIsolated фиксирует факт, который мы и так знаем.
            MainActor.assumeIsolated {
                guard let self = self else {
                    return
                }

                self.typingDots = (self.typingDots % 3) + 1
                let dots = String(repeating: ".", count: self.typingDots)
                self.typingLabel.text = "\(peerName) печатает\(dots)"
            }
        }
        
        typingLabel.text = "\(peerName) печатает."
    }
    
    private func stopTypingAnimation() {
        typingAnimationTimer?.invalidate()
        typingAnimationTimer = nil
        typingLabel.isHidden = true
    }
    
    deinit {
        print("[lifecycle] ChatViewController deinit")
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        viewModel.messages.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MessageCell.reuseID,
            for: indexPath
        ) as? MessageCell else {
            return UITableViewCell()
        }
        let message = viewModel.messages[indexPath.row]
        cell.configure(with: message)
        cell.onRetry = { [weak self] in
            Task {
                await self?.viewModel.resend(message.id)
            }
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {

    /// Долгое нажатие на мозаику: скопировать как текст, отправить снова.
    ///
    /// У текста меню нет: текст выделяется прямо в ленте, и копирование там
    /// штатное, а «повторить» — нажатием на подпись «не отправлено».
    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        let message = viewModel.messages[indexPath.row]
        guard message.mosaic != nil else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []

            if message.isFromMe && message.status == .failed {
                actions.append(UIAction(title: "Отправить снова",
                                        image: UIImage(systemName: "arrow.clockwise")) { _ in
                    Task {
                        await self?.viewModel.resend(message.id)
                    }
                })
            }

            // Наружу — картинкой: сетку в другом мессенджере не повторить,
            // а картинку — можно.
            actions.append(UIAction(title: "Поделиться картинкой",
                                    image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.share(mosaic: message.mosaic)
            })

            // В чужом мессенджере ровно не встанет, но это лучшее, что там
            // возможно текстом.
            actions.append(UIAction(title: "Скопировать как текст",
                                    image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = message.text
            })

            return UIMenu(children: actions)
        }
    }
}

extension ChatViewController {

    private func share(mosaic: Mosaic?) {
        guard let mosaic else {
            return
        }
        let image = MosaicImageRenderer.render(mosaic)
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ChatViewController: UIGestureRecognizerDelegate {

    /// У текста свои распознаватели, и без этого они выигрывают у нашего:
    /// нажатие на текст до ряда реакций не доходило.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Нажатие на ссылку — ссылке, на подпись «повторить» — ей, на сам
    /// ряд реакций — ему. Остальное — ряд реакций.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else {
            return true
        }
        if let picker = reactionPicker, view.isDescendant(of: picker) {
            return false
        }
        if view is UIControl {
            return false
        }
        if let textView = view as? UITextView {
            let point = touch.location(in: textView)
            if let position = textView.closestPosition(to: point),
               let range = textView.tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .layout(.left)),
               textView.textStyling(at: range.start, in: .forward)?[.link] != nil {
                return false
            }
        }
        if view.isUserInteractionEnabled, view is UILabel {
            // Подпись «повторить» — у неё свой обработчик.
            return false
        }
        return true
    }
}

// MARK: - UITextFieldDelegate

extension ChatViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Пока ждём кисть с клавиатуры, Return — просто вернуться к палитре.
        if awaitingCustomBrush {
            awaitingCustomBrush = false
            textField.inputView = palette
            textField.reloadInputViews()
            return true
        }
        sendTapped()
        return true
    }
}

// MARK: - MosaicPaletteDelegate

extension ChatViewController: MosaicPaletteDelegate {

    func palette(_ palette: MosaicPaletteView, didPickBrush brush: String) {
        // Кисть сменилась — черновик тот же, перерисовывать нечего.
    }

    func palette(_ palette: MosaicPaletteView, didPickSide side: Int) {
        // Нарисованное переносится, насколько влезает: сменить размер на
        // ходу и потерять всё — обидно.
        var resized = Mosaic(columns: side, rows: side)
        for row in 0..<min(side, mosaicDraft.rows) {
            for column in 0..<min(side, mosaicDraft.columns) {
                resized = resized.setting(column: column, row: row, to: mosaicDraft[column, row])
            }
        }
        mosaicDraft = resized
        draftView.show(mosaicDraft)
        updateMosaicChrome()
        saveMosaicDraft()
    }

    func paletteDidAskToFill(_ palette: MosaicPaletteView) {
        let brush = palette.brush
        guard !brush.isEmpty else {
            return
        }
        for row in 0..<mosaicDraft.rows {
            for column in 0..<mosaicDraft.columns where mosaicDraft[column, row].isEmpty {
                mosaicDraft = mosaicDraft.setting(column: column, row: row, to: brush)
            }
        }
        draftView.show(mosaicDraft)
        UISelectionFeedbackGenerator().selectionChanged()
        updateMosaicChrome()
        saveMosaicDraft()
    }

    func paletteDidAskToClear(_ palette: MosaicPaletteView) {
        mosaicDraft = Mosaic(columns: mosaicDraft.columns, rows: mosaicDraft.rows)
        draftView.show(mosaicDraft)
        updateMosaicChrome()
        saveMosaicDraft()
    }

    /// Настоящая клавиатура на один знак: палитра уходит, набранное
    /// становится кистью, палитра возвращается.
    func paletteDidAskForKeyboard(_ palette: MosaicPaletteView) {
        awaitingCustomBrush = true
        textField.text = ""
        textField.inputView = nil
        textField.reloadInputViews()
    }
}

// MARK: - PeerConnectionApproving

extension ChatViewController: PeerConnectionApproving {
   
    func shouldAcceptConnection(from peerName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                guard self.isViewLoaded && self.view.window != nil else {
                    print("[ChatViewController] Not in hierarchy, auto-accepting")
                    continuation.resume(returning: true)
                    return
                }
                
                let alert = UIAlertController(title: "Новое подключение",
                                              message: "\(peerName) хочет подключиться к вам. Разрешить?",
                                              preferredStyle: .alert)
                
                let acceptAction = UIAlertAction(title: "Принять", style: .default) { _ in
                    continuation.resume(returning: true)
                }
                
                let declineAction = UIAlertAction(title: "Отклонить", style: .default) { _ in
                    continuation.resume(returning: false)
                }
                
                alert.addAction(acceptAction)
                alert.addAction(declineAction)
                alert.preferredAction = acceptAction
                
                self.present(alert, animated: true)
            }
        }
    }
}
