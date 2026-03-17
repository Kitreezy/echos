//
//  MessageCell.swift
//  echos
//
//  Created by Artem Rodionov on 17.02.2026.
//

import UIKit

/// step 11 заменить на красивые кастомные bubbles с Lottie.
final class MessageCell: UITableViewCell {
    
    static let reuseID = "MessageCell"
    
    // MARK: - UI
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: "#1A1F2E")
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let sideBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let senderNameLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = UIColor(hex: "#00BFFF")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Dynamic constraints (меняются в configure)
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    
    // MARK: - Init
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private lazy var layoutConstraints: [NSLayoutConstraint] = {
        [
            // Side bar (всегда слева)
            sideBar.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            sideBar.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            sideBar.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            sideBar.widthAnchor.constraint(equalToConstant: 4),
            
            // Sender name (для групповых чатов)
            senderNameLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            senderNameLabel.leadingAnchor.constraint(equalTo: sideBar.trailingAnchor, constant: 12),
            senderNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: bubbleView.trailingAnchor, constant: -12),
            
            // Message text
            messageLabel.topAnchor.constraint(equalTo: senderNameLabel.bottomAnchor, constant: 4),
            messageLabel.leadingAnchor.constraint(equalTo: sideBar.trailingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            // Bubble
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
            
            // Time label
            timeLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 6),
            timeLabel.leadingAnchor.constraint(equalTo: sideBar.trailingAnchor, constant: 12),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            
            // Status label
            statusLabel.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 8)
        ]
    }()
    
    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(sideBar)
        bubbleView.addSubview(senderNameLabel)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(timeLabel)
        bubbleView.addSubview(statusLabel)
        
        // Dynamic constraints для позиционирования bubble
        bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: 16
        )
        
        bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -16
        )
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    // MARK: - Configure
    
    func configure(with message: Message) {
        messageLabel.text = message.text
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: message.timestamp)
        
        if message.isFromMe {
            // Моё сообщение — справа (terminal green)
            configureMySide()
            configureMyStatus(message.status)
            senderNameLabel.isHidden = true
            
        } else {
            // Входящее сообщение — слева (terminal cyan)
            configureTheirSide()
            configureTheirStatus()
            
            // Показываем имя отправителя для групповых чатов
            if let senderName = message.senderName {
                senderNameLabel.text = senderName.uppercased()
                senderNameLabel.isHidden = false
            } else {
                senderNameLabel.isHidden = true
            }
        }
    }
    
    // MARK: - Private Configure Helpers
    
    private func configureMySide() {
        // Прижать справа
        bubbleLeadingConstraint?.isActive = false
        bubbleTrailingConstraint?.isActive = true
        
        // Terminal green colors
        sideBar.backgroundColor = UIColor(hex: "#00FF41")
        messageLabel.textColor = UIColor(hex: "#00FF41")
        timeLabel.textColor = UIColor(hex: "#00FF41").withAlphaComponent(0.6)
    }
    
    private func configureTheirSide() {
        // Прижать слева
        bubbleTrailingConstraint?.isActive = false
        bubbleLeadingConstraint?.isActive = true
        
        // Terminal cyan colors
        sideBar.backgroundColor = UIColor(hex: "#00BFFF")
        messageLabel.textColor = UIColor(hex: "#00BFFF")
        timeLabel.textColor = UIColor(hex: "#00BFFF").withAlphaComponent(0.6)
        senderNameLabel.textColor = UIColor(hex: "#00BFFF")
    }
    
    private func configureMyStatus(_ status: MessageStatus) {
        statusLabel.isHidden = false
        
        switch status {
        case .sending:
            statusLabel.text = "SENDING"
            statusLabel.textColor = UIColor(hex: "#FFB800")
            
        case .sent:
            statusLabel.text = "SENT"
            statusLabel.textColor = UIColor(hex: "#00FF41")
            
        case .failed:
            statusLabel.text = "FAILED"
            statusLabel.textColor = .systemRed
        }
    }
    
    private func configureTheirStatus() {
        statusLabel.text = "RECEIVED"
        statusLabel.textColor = UIColor(hex: "#00BFFF")
        statusLabel.isHidden = false
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        senderNameLabel.isHidden = true
        statusLabel.isHidden = false
        
        // Reset constraints
        bubbleLeadingConstraint?.isActive = false
        bubbleTrailingConstraint?.isActive = false
    }
}
