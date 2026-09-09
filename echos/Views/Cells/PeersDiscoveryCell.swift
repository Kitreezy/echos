//
//  PeersDiscoveryCell.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import UIKit

final class PeerDiscoveryCell: UITableViewCell {
    
    // MARK: - Properties
    
    var onConnect: (() -> Void)?
    
    // MARK: - UI
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.surfaceRaised
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let statusBar: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.own
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        label.textColor = UIColor.own
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let infoLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = UIColor.own.withAlphaComponent(0.6)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let hoverLayer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        return view
    }()
    
    private let actionButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "CONNECT"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            return outgoing
        }
        
        let button = UIButton(configuration: config)
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Init
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private lazy var layoutConstraints: [NSLayoutConstraint] = {
        [
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            
            hoverLayer.topAnchor.constraint(equalTo: containerView.topAnchor),
            hoverLayer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hoverLayer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hoverLayer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            statusBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            statusBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            statusBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            statusBar.widthAnchor.constraint(equalToConstant: 3),
            
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: 12),
            
            infoLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            infoLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            infoLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),
            
            statusIcon.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            statusIcon.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),
            statusIcon.widthAnchor.constraint(equalToConstant: 18),
            statusIcon.heightAnchor.constraint(equalToConstant: 18),
            
            actionButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            actionButton.heightAnchor.constraint(equalToConstant: 28)
        ]
    }()
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        
        setupLayout()
        
        actionButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
    }
    
    private func setupLayout() {
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(containerView)
        containerView.addSubview(hoverLayer)
        containerView.addSubview(statusBar)
        containerView.addSubview(nameLabel)
        containerView.addSubview(infoLabel)
        containerView.addSubview(statusIcon)
        containerView.addSubview(actionButton)
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    // MARK: - Configure
     
     func configure(with peer: Peer) {
         nameLabel.text = peer.displayName.uppercased()
         
         let distance = peer.formattedDistance
         let signal = peer.signalPercentage
         infoLabel.text = "DIST: \(distance) // SIGNAL: \(signal)%"
         
         switch peer.status {
         case .connected:
             configureConnected()
             
         case .notConnected:
             configureNotConnected()
             
         case .connecting:
             configureConnecting()
             
         case .failed:
             configureFailed()
         }
     }
     
     // MARK: - Configuration Helpers
     
    private func configureConnected() {
        let color = UIColor.alive
        
        containerView.alpha = 1.0
        statusBar.backgroundColor = color
        nameLabel.textColor = color
        infoLabel.textColor = UIColor.inkMuted  
        hoverLayer.backgroundColor = color.withAlphaComponent(0.05)
        
        // Shadow
        containerView.layer.shadowColor = color.cgColor
        containerView.layer.shadowRadius = 10
        containerView.layer.shadowOpacity = 0.05
        containerView.layer.shadowOffset = .zero
        
        statusIcon.image = UIImage(systemName: "checkmark.circle.fill")
        statusIcon.tintColor = color
        
        // Icon glow
        statusIcon.layer.shadowColor = color.cgColor
        statusIcon.layer.shadowRadius = 4
        statusIcon.layer.shadowOpacity = 0.6
        statusIcon.layer.shadowOffset = .zero
        
        // Text glow
        nameLabel.layer.shadowColor = color.cgColor
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOpacity = 0.8
        nameLabel.layer.shadowOffset = .zero
        
        actionButton.configuration?.title = "OPEN >"
        actionButton.configuration?.baseForegroundColor = color
        actionButton.layer.borderColor = color.cgColor
        actionButton.isEnabled = true
    }
     
    private func configureNotConnected() {
        let color = UIColor.other
        
        containerView.alpha = 1.0
        statusBar.backgroundColor = color
        nameLabel.textColor = color
        infoLabel.textColor = UIColor.inkMuted
        hoverLayer.backgroundColor = color.withAlphaComponent(0.05)
        
        // Shadow
        containerView.layer.shadowColor = color.cgColor
        containerView.layer.shadowRadius = 10
        containerView.layer.shadowOpacity = 0.05
        containerView.layer.shadowOffset = .zero
        
        statusIcon.image = UIImage(systemName: "dot.radiowaves.left.and.right")
        statusIcon.tintColor = color
        
        // Icon glow
        statusIcon.layer.shadowColor = color.cgColor
        statusIcon.layer.shadowRadius = 4
        statusIcon.layer.shadowOpacity = 0.6
        statusIcon.layer.shadowOffset = .zero
        
        // Text glow
        nameLabel.layer.shadowColor = color.cgColor
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOpacity = 0.8
        nameLabel.layer.shadowOffset = .zero
        
        actionButton.configuration?.title = "CONNECT"
        actionButton.configuration?.baseForegroundColor = color
        actionButton.layer.borderColor = color.cgColor
        actionButton.isEnabled = true
    }
     
    private func configureConnecting() {
        let color = UIColor.systemOrange
        
        containerView.alpha = 1.0
        statusBar.backgroundColor = color
        nameLabel.textColor = color
        infoLabel.textColor = UIColor.inkMuted
        hoverLayer.backgroundColor = color.withAlphaComponent(0.05)
        
        // Shadow
        containerView.layer.shadowColor = color.cgColor
        containerView.layer.shadowRadius = 10
        containerView.layer.shadowOpacity = 0.05
        containerView.layer.shadowOffset = .zero
        
        statusIcon.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        statusIcon.tintColor = color
        
        // Icon glow
        statusIcon.layer.shadowColor = color.cgColor
        statusIcon.layer.shadowRadius = 4
        statusIcon.layer.shadowOpacity = 0.6
        statusIcon.layer.shadowOffset = .zero
        
        // Text glow
        nameLabel.layer.shadowColor = color.cgColor
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOpacity = 0.8
        nameLabel.layer.shadowOffset = .zero
        
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 1.5
        rotation.repeatCount = .infinity
        statusIcon.layer.add(rotation, forKey: "connecting_rotation")
        
        actionButton.configuration?.title = "..."
        actionButton.configuration?.baseForegroundColor = color
        actionButton.layer.borderColor = color.cgColor
        actionButton.isEnabled = false
    }
     
    private func configureFailed() {
        let color = UIColor.lost
        
        containerView.alpha = 0.8
        
        statusBar.backgroundColor = color
        nameLabel.textColor = color
        infoLabel.textColor = color.withAlphaComponent(0.7)
        hoverLayer.backgroundColor = color.withAlphaComponent(0.05)
        
        // Shadow
        containerView.layer.shadowColor = color.cgColor
        containerView.layer.shadowRadius = 10
        containerView.layer.shadowOpacity = 0.05
        containerView.layer.shadowOffset = .zero
        
        statusIcon.image = UIImage(systemName: "exclamationmark.triangle.fill")
        statusIcon.tintColor = color
        
        // Icon glow + pulse
        statusIcon.layer.shadowColor = color.cgColor
        statusIcon.layer.shadowRadius = 4
        statusIcon.layer.shadowOpacity = 0.6
        statusIcon.layer.shadowOffset = .zero
        
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.5
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusIcon.layer.add(pulse, forKey: "pulse")
        
        // Text glow (stronger)
        nameLabel.layer.shadowColor = color.cgColor
        nameLabel.layer.shadowRadius = 4
        nameLabel.layer.shadowOpacity = 0.8
        nameLabel.layer.shadowOffset = .zero
        
        actionButton.configuration?.title = "FAILED"
        actionButton.configuration?.baseForegroundColor = color.withAlphaComponent(0.5)
        actionButton.layer.borderColor = color.withAlphaComponent(0.5).cgColor
        actionButton.isEnabled = false
    }
     
     @objc
    private func connectTapped() {
         onConnect?()
     }
     
     override func prepareForReuse() {
         super.prepareForReuse()
         statusIcon.layer.removeAllAnimations()
     }
}
