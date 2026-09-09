//
//  DiscoveryViewController.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import UIKit
import SwiftUI

final class DiscoveryViewController: UIViewController {
    
    // MARK: - ViewModel
    
    private let viewModel = ChatViewModel()
    
    private let radarState = RadarState()
    
    // MARK: - UI Components
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setTracked("echos", tracking: Typography.wide)
        return label
    }()

    /// Сколько рядом. Пусто — значит ноль, и говорить об этом незачем.
    private let peerCountLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var radarView: UIView = {
        let radarSwiftUI = RadarView(state: radarState)
        let hosting = UIHostingController(rootView: radarSwiftUI)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        hosting.didMove(toParent: self)
        return hosting.view
    }()
    
    /// Одна строка вместо крутящейся иконки с надписью капсом.
    /// Показывается, только когда сказать действительно есть что.
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    /// Возобновлять поиск при возврате из фона только если он реально шёл.
    private var shouldResumeDiscovery = false
    
    // MARK: - Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupTableView()
        bindViewModel()
        startAnimations()
        setupAppLifecycleObservers()

        Task {
            viewModel.initialize()
            viewModel.multipeerService?.approvalDelegate = self
            await viewModel.startDeviceDiscovery()
            radarState.isScanning = true
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        stopAnimations()

        // navigationController?.setNavigationBarHidden(false, animated: animated)  // ❌ НЕ НУЖНО
    }

    // MARK: - App Lifecycle

    /// Наблюдатели живут здесь, а не в ChatViewController: этот экран —
    /// root навигации и владелец ChatViewModel, он жив всё время работы
    /// приложения. ChatViewController существует только пока открыт чат,
    /// и свернуть приложение с экрана радара он бы не поймал.
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

    @objc
    private func appDidEnterBackground() {
        guard viewModel.isDiscovering else {
            return
        }

        shouldResumeDiscovery = true
        viewModel.stopDeviceDiscovery()
        radarState.isScanning = false
        stopAnimations()
    }

    @objc
    private func appWillEnterForeground() {
        guard shouldResumeDiscovery else {
            return
        }

        shouldResumeDiscovery = false
        startAnimations()

        Task {
            await viewModel.startDeviceDiscovery()
            radarState.isScanning = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Status Bar
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent  
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    // MARK: - Layout

    private lazy var layoutConstraints: [NSLayoutConstraint] = {
        [
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                            constant: Space.room),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                constant: Space.margin),

            peerCountLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            peerCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                     constant: -Space.margin),

            radarView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Space.ma),
            radarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            radarView.widthAnchor.constraint(equalToConstant: 240),
            radarView.heightAnchor.constraint(equalToConstant: 240),

            statusLabel.topAnchor.constraint(equalTo: radarView.bottomAnchor, constant: Space.room),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Space.ma),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ]
    }()
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = UIColor.surface
        
        setupLayout()
    }
    
    private func setupLayout() {
        view.addSubview(titleLabel)
        view.addSubview(peerCountLabel)
        view.addSubview(radarView)
        view.addSubview(statusLabel)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PeerDiscoveryCell.self, forCellReuseIdentifier: "PeerCell")
    }
    
    // MARK: - Animations

    /// Вращение и пульсация ушли вместе с иконкой: единственное движение
    /// на экране — круг на воде в RadarView.
    private func startAnimations() {}

    private func stopAnimations() {}
    
    // MARK: - Binding
    
    private func bindViewModel() {
        updateUI()
        scheduleObservation()
    }
    
    private func scheduleObservation() {
        withObservationTracking {
            _ = viewModel.peers
        } onChange: { [weak self] in
            // onChange прилетает вне главного актора и вне изоляции вьюхи,
            // поэтому возвращаемся на него явно через Task { @MainActor }.
            Task { @MainActor in
                guard let self else { return }
                self.updateUI()
                self.scheduleObservation()
            }
        }
    }
    
    /// Что показывать в списке. Демо-список подставляется, только если его
    /// явно попросили аргументом запуска.
    private var displayedPeers: [Peer] {
        if viewModel.peers.isEmpty, UserSettings.showsDemoPeers {
            return demoPeers()
        }
        return viewModel.peers
    }
    
    private func updateUI() {
        let displayPeers = displayedPeers
        
        peerCountLabel.text = displayPeers.isEmpty ? "" : "\(displayPeers.count)"

        // Когда рядом кто-то есть, список говорит сам за себя — строка молчит.
        statusLabel.text = displayPeers.isEmpty ? "Пока никого рядом" : ""

        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    private func connectToPeer(_ peer: Peer) {
        Task {
            do {
                try await viewModel.multipeerService?.connectToPeer(displayName: peer.displayName)
            } catch {
                print("Failed to connect: \(error)")
            }
        }
    }
    
    private func openChat(with peer: Peer) {
        Task {
            await viewModel.switchToConversation(with: peer.displayName)
            
            let chatVC = ChatViewController(viewModel: viewModel)
            await MainActor.run {
                navigationController?.pushViewController(chatVC, animated: true)
            }
            print("[DiscoveryViewController] Opened chat with \(peer.displayName)")
        }
    }
    
    // MARK: - Toast Helper
     
    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        
        // Auto dismiss after 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alert.dismiss(animated: true)
        }
    }
}
 
// MARK: - TableView
 
extension DiscoveryViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return displayedPeers.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath) as? PeerDiscoveryCell else {
            return UITableViewCell()
        }
        
        let peer = displayedPeers[indexPath.row]
        
        cell.configure(with: peer)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // В демо-режиме строки некликабельны: за ними нет живых устройств.
        guard !viewModel.peers.isEmpty else {
            return
        }
        
        let peer = viewModel.peers[indexPath.row]
        
        switch peer.status {
        case .connected:
            openChat(with: peer)
            
        case .notConnected:
            connectToPeer(peer)
            
        case .connecting:
            print("Already connecting to \(peer.displayName)...")
            showToast("Подключение...")
            
        case .failed:
            print("Peer \(peer.displayName) is unavailable")
            showToast("Устройство недоступно")
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
}

// MARK: - PeerConnectionApproving

extension DiscoveryViewController: PeerConnectionApproving {
    func shouldAcceptConnection(from peerName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                let alert = UIAlertController(
                    title: "INCOMING CONNECTION",
                    message: "\(peerName) wants to connect. Accept?",
                    preferredStyle: .alert
                )
                
                alert.view.tintColor = UIColor.alive
                
                alert.addAction(UIAlertAction(title: "ACCEPT", style: .default) { _ in
                    continuation.resume(returning: true)
                })
                
                alert.addAction(UIAlertAction(title: "DECLINE", style: .destructive) { _ in
                    continuation.resume(returning: false)
                })
                
                self.present(alert, animated: true)
            }
        }
    }
}

extension DiscoveryViewController {
    
    private func demoPeers() -> [Peer] {
        return [
            Peer(
                id: UUID(),
                displayName: "UNIT-7F3A",
                status: .connected,
                lastSeen: Date(),
                rssi: -45,
                distance: 12
            ),
            Peer(
                id: UUID(),
                displayName: "GHOST-9X",
                status: .notConnected,
                lastSeen: Date(),
                rssi: -68,
                distance: 45
            ),
            Peer(
                id: UUID(),
                displayName: "NEO_WORM",
                status: .connecting,
                lastSeen: Date(),
                rssi: -58,
                distance: 28
            ),
            Peer(
                id: UUID(),
                displayName: "UNKNOWN_E",
                status: .failed,
                lastSeen: Date(),
                rssi: -95,
                distance: 98
            )
        ]
    }
}
