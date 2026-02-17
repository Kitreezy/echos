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
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private let statusIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        return imageView
    }()
    
    // TODO: - заменить force крит!
    // Dynamic constraints (меняются в configure)
    private var bubbleLeading: NSLayoutConstraint!
    private var bubbleTrailing: NSLayoutConstraint!
    
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
            // Bubble
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72),
            
            // Text in bubble
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            // Time and status
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            statusIcon.widthAnchor.constraint(equalToConstant: 12),
            statusIcon.heightAnchor.constraint(equalToConstant: 12),
            statusIcon.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor)
        ]
    }()
    
    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(bubbleView)
        contentView.addSubview(messageLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(statusIcon)
        
        bubbleLeading = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        bubbleTrailing = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    // MARK: - Configure
    
    func configure(with message: Message) {
        messageLabel.text = message.text
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        timeLabel.text = formatter.string(from: message.timestamp)
        
        if message.isFromMe {
            // Cообщение — справа
            bubbleView.backgroundColor = .systemBlue
            messageLabel.textColor = .white
            
            bubbleLeading.isActive = false
            bubbleTrailing.isActive = true
            
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16).isActive = true
            
            statusIcon.isHidden = false
            statusIcon.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -4).isActive = true
            switch message.status {
            case .sending:
                statusIcon.image = UIImage(systemName: "arrow.triangle.2.circlepath")
                
            case .sent:
                statusIcon.image = UIImage(systemName: "checkmark")
                
            case .failed:
                statusIcon.image = UIImage(systemName: "xmark")
                statusIcon.tintColor = .systemRed
            }
        } else {
            // Cообщение — слева
            bubbleView.backgroundColor = .secondarySystemBackground
            messageLabel.textColor = .label
            
            bubbleTrailing.isActive = false
            bubbleLeading.isActive = true
            timeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16).isActive = true
            
            statusIcon.isHidden = true
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        statusIcon.tintColor = .systemBlue
        statusIcon.isHidden = false
    }
}
