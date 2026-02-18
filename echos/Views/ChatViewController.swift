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
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.returnKeyType = .send
        
        return textField
    }()
    
    private let sendButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.uturn.up")
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemBlue
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        return button
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "echos"
        view.backgroundColor = .systemBackground
        setupLayout()
        setupTableView()
        setupGestures()
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
        
        emptyStateView.isHidden = !viewModel.messages.isEmpty
        
        tableView.reloadData()
        scrollToBottom(animated: true)
        
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
        }
    }
    
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
    
    private func scrollToBottom(animated: Bool) {
        guard !viewModel.messages.isEmpty else {
            return
        }
        let idx = IndexPath(row: viewModel.messages.count - 1, section: 0)
        tableView.scrollToRow(at: idx, at: .bottom, animated: animated)
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
