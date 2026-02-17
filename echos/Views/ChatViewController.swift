//
//  ChatViewController.swift
//  echos
//
//  Created by Artem Rodionov on 16.02.2026.
//

import UIKit

final class ChatViewController: UIViewController {
    
    // MARK: - ViewModel
    
    private let viewModel = ChatViewModel()
    
    // MARK: - UI
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.separatorStyle = .none
        table.backgroundColor = UIColor(named: "Background") ?? .systemBackground
        table.keyboardDismissMode = .interactive
        table.allowsSelection = false
        table.translatesAutoresizingMaskIntoConstraints = false
        
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
    
    private let inputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let textField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Сообщение..."
        textField.borderStyle = .none
        textField.backgroundColor = .secondarySystemBackground
        textField.layer.cornerRadius = 18
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        textField.rightViewMode = .always
                                     
        return textField
    }()
    
    private let sendButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.up.circle")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemBlue
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    // TODO: - убрать force / посмотреть в сторону keyboardLayoutGuide для отступа от клавиатуры
    private var inputBottomConstraint: NSLayoutConstraint!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "echos"
        view.backgroundColor = .systemBackground
        setupLayout()
        setupTableView()
        setupKeyboardHandling()
        bindViewModel()
        startApp()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stopDeviceDiscovery()
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
            
            // Typing
            typingLabel.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 4),
            typingLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            typingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            typingLabel.bottomAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -4),
            
            // InputContainer
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 64),
            inputBottomConstraint,
            
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
        view.addSubview(typingLabel)
        view.addSubview(inputContainer)
        inputContainer.addSubview(textField)
        inputContainer.addSubview(sendButton)
        
        inputBottomConstraint = inputContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        
        NSLayoutConstraint.activate(layoutConstraints)
        
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseID)
    }
    
    // MARK: - Keyboard
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }
    
    @objc
    private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else {
            return
        }
        let keyboardHeight = max(0, view.frame.maxY - view.frame.minY)
        inputBottomConstraint.constant = -keyboardHeight
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Binding
    
    /// Подписка на @Observable ViewModel через withObservationTracking.
    /// При каждом изменении observed-свойства вызывается onChange -  перегружаем UI.
    private func bindViewModel() {
        scheduleObservation()
    }
    
    private func scheduleObservation() {
        withObservationTracking {
            let _ = viewModel.messages
            let _ = viewModel.connectionStatus
            let _ = viewModel.typingPeerName
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateUI()
                self?.scheduleObservation()  // переподписка
            }
        }
    }
    
    private func updateUI() {
        statusLabel.text = viewModel.connectionStatus
        tableView.reloadData()
        scrollToBottom()
        
        if let peerName = viewModel.typingPeerName {
            typingLabel.text = "\(peerName) печатает..."
        } else {
            typingLabel.isHidden = true
        }
    }
    
    // MARK: - Actions
    
    private func startApp() {
        Task {
            await viewModel.startDeviceDiscovery()
            
            // Запуск прослушивания входящих сообщений параллельно
            async let _ = viewModel.startListeningForMessages()
            
            // DEMO: Через 4 секунды имитируем входящее сообщение
            try? await Task.sleep(for: .seconds(4))
            viewModel.injectIncomingMessage(
                Message(text: "Привет! Денис Колбасенко", isFromMe: false, status: .sent)
            )
            
            // DEMO: typing индикатор
            try? await Task.sleep(for: .seconds(1))
            await viewModel.simulateIncomingTyping(from: "iPhone Артем")
        }
    }
    
    @objc
    private func sendTapped() {
        guard var text = textField.text, !text.isEmpty else {
            return
        }
        text = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
    
    private func scrollToBottom() {
        guard !viewModel.messages.isEmpty else {
            return
        }
        let idx = IndexPath(row: viewModel.messages.count - 1, section: 0)
        tableView.scrollToRow(at: idx, at: .bottom, animated: true)
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
