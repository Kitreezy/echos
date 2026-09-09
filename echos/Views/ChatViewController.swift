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
        
        if let peerName = viewModel.currentConversationPeer {
            title = peerName
        } else {
            title = "echos"
        }
        
        let menuButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: createMainMenu()
        )
        navigationItem.rightBarButtonItem = menuButton
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
            
            // TextField
            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
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
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(typingLabel)
        view.addSubview(inputContainer)
        inputContainer.addSubview(textField)
        inputContainer.addSubview(sendButton)
        
        NSLayoutConstraint.activate(layoutConstraints)
        
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }
    
    private func setupTableView() {
        tableView.dataSource = self
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
    
    // MARK: - Onboarding
    
    private func showOnboardingAlert() {
        let alert = UIAlertController(title: "Добро пожаловать в echos!",
                                     message: "Как вас зовут? Это имя увидят другие устройства поблизости.",
                                     preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Ваше имя"
            textField.autocapitalizationType = .words
            textField.returnKeyType = .done
        }
        
        let contunieAction = UIAlertAction(title: "Продолжить", style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                self?.showOnboardingAlert()
                return
            }
            UserSettings.userName = name
            
            Task {
                self?.viewModel.initialize()
                self?.viewModel.multipeerService?.approvalDelegate = self
                await self?.viewModel.startDeviceDiscovery()
            }
        }
        alert.addAction(contunieAction)
        alert.preferredAction = contunieAction
        present(alert, animated: true)
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
        scrollToBottom(animated: true)
        
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
    
    private func restartServiceWithNewName() async {
        viewModel.multipeerService?.stopDeviceDiscovery()
        
        viewModel.initialize()
        viewModel.multipeerService?.approvalDelegate = self
        await viewModel.startDeviceDiscovery()
        print("[ChatViewController] Service restarted with new name: \(UserSettings.displayName)")
    }
    
    // MARK: - Actions
    
    @objc
    private func sendTapped() {
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
        if let peerName = viewModel.currentConversationPeer {
            chatSection = UIMenu(title: "Чат с '\(peerName)'", options: .displayInline, children: [
                UIAction(
                    title: "Стена '\(peerName)'",
                    image: UIImage(systemName: "scribble.variable")
                ) { [weak self] _ in
                    self?.showWall(of: peerName)
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
        if let menuButton = navigationItem.rightBarButtonItem {
            menuButton.menu = createMainMenu()
        }
    }
    
    // MARK: - History Menu
    
    // MARK: - Disconnect Confirmation
    
    private func confirmDisconnect() {
        guard let peerName = viewModel.currentConversationPeer else {
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
        guard let peerName = viewModel.currentConversationPeer else {
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
    private func showWall(of owner: String?) {
        guard let transport = viewModel.multipeerService else {
            return
        }

        let wall = WallView(
            viewModel: WallViewModel(owner: owner, transport: transport),
            ownName: transport.myDisplayName
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
        cell.configure(with: viewModel.messages[indexPath.row])
        return cell
    }
}

// MARK: - UITextFieldDelegate

extension ChatViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
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
