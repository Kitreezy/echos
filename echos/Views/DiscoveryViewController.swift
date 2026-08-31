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
    
    private let scanlinesView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.alpha = 0.1
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let headerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: "#0D0F14").withAlphaComponent(0.8)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let radarIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "dot.radiowaves.left.and.right"))
        imageView.tintColor = UIColor(hex: "#39FF14")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.layer.shadowColor = UIColor(hex: "#39FF14").cgColor
        imageView.layer.shadowRadius = 8
        imageView.layer.shadowOpacity = 0.8
        imageView.layer.shadowOffset = .zero
        
        return imageView
    }()
    
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "ECHOS // SIGNAL: STRONG"
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = UIColor(hex: "#39FF14")
        label.translatesAutoresizingMaskIntoConstraints = false
        
        label.layer.shadowColor = UIColor(hex: "#39FF14").cgColor
        label.layer.shadowRadius = 5
        label.layer.shadowOpacity = 0.8
        label.layer.shadowOffset = .zero
        
        return label
    }()
    
    private let peerCountLabel: UILabel = {
        let label = UILabel()
        label.text = "PEER: 0 CONN"
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = UIColor(hex: "#39FF14")
        label.translatesAutoresizingMaskIntoConstraints = false
        
        label.layer.shadowColor = UIColor(hex: "#39FF14").cgColor
        label.layer.shadowRadius = 5
        label.layer.shadowOpacity = 0.8
        label.layer.shadowOffset = .zero
        
        return label
    }()
    
    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(hex: "#39FF14").withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
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
    
    private let scanningContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let scanningIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
        imageView.tintColor = UIColor(hex: "#00E5FF")
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.layer.shadowColor = UIColor(hex: "#00E5FF").cgColor
        imageView.layer.shadowRadius = 4
        imageView.layer.shadowOpacity = 0.6
        imageView.layer.shadowOffset = .zero
        
        return imageView
    }()
    
    private let scanningLabel: UILabel = {
        let label = UILabel()
        label.text = "SCANNING FREQUENCIES..."
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = UIColor(hex: "#00E5FF")
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        label.layer.shadowColor = UIColor(hex: "#00E5FF").cgColor
        label.layer.shadowRadius = 4
        label.layer.shadowOpacity = 0.6
        label.layer.shadowOffset = .zero
        
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private var pulseTimer: Timer?
    private var rotationAnimation: CABasicAnimation?

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
            viewModel.multipeerService?.invitationDelegate = self
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
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),
            
            // Radar icon
            radarIcon.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            radarIcon.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            radarIcon.widthAnchor.constraint(equalToConstant: 18),
            radarIcon.heightAnchor.constraint(equalToConstant: 18),
            
            // Header label
            headerLabel.leadingAnchor.constraint(equalTo: radarIcon.trailingAnchor, constant: 6),
            headerLabel.centerYAnchor.constraint(equalTo: radarIcon.centerYAnchor),
            
            // Peer count
            peerCountLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            peerCountLabel.centerYAnchor.constraint(equalTo: radarIcon.centerYAnchor),
            
            // Separator
            separatorLine.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            
            radarView.topAnchor.constraint(equalTo: separatorLine.bottomAnchor, constant: 24),
            radarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            radarView.widthAnchor.constraint(equalToConstant: 256),
            radarView.heightAnchor.constraint(equalToConstant: 256),
            
            scanningContainer.topAnchor.constraint(equalTo: radarView.bottomAnchor, constant: 20),
            scanningContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningContainer.heightAnchor.constraint(equalToConstant: 24),
            
            // Scanning icon
            scanningIcon.leadingAnchor.constraint(equalTo: scanningContainer.leadingAnchor),
            scanningIcon.centerYAnchor.constraint(equalTo: scanningContainer.centerYAnchor),
            scanningIcon.widthAnchor.constraint(equalToConstant: 16),
            scanningIcon.heightAnchor.constraint(equalToConstant: 16),
            
            // Scanning label
            scanningLabel.leadingAnchor.constraint(equalTo: scanningIcon.trailingAnchor, constant: 8),
            scanningLabel.trailingAnchor.constraint(equalTo: scanningContainer.trailingAnchor),
            scanningLabel.centerYAnchor.constraint(equalTo: scanningContainer.centerYAnchor),
            
            tableView.topAnchor.constraint(equalTo: scanningContainer.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ]
    }()
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = UIColor(hex: "#0D0F14")
        
        setupScanlines()
        
        setupLayout()
    }
    
    private func setupScanlines() {
        view.addSubview(scanlinesView)
        
        NSLayoutConstraint.activate([
            scanlinesView.topAnchor.constraint(equalTo: view.topAnchor),
            scanlinesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanlinesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanlinesView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let lineHeight: CGFloat = 4
        let lineLayer = CALayer()
        lineLayer.backgroundColor = UIColor.black.cgColor
        lineLayer.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: lineHeight / 2)
        
        let patternImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: lineHeight)).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: lineHeight))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: lineHeight / 2, width: 1, height: lineHeight / 2))
        }
        
        scanlinesView.backgroundColor = UIColor(patternImage: patternImage)
    }
    
    private func setupLayout() {
        view.addSubview(headerContainer)
        headerContainer.addSubview(radarIcon)
        headerContainer.addSubview(headerLabel)
        headerContainer.addSubview(peerCountLabel)
        view.addSubview(separatorLine)
        view.addSubview(radarView)
        
        scanningContainer.addSubview(scanningIcon)
        scanningContainer.addSubview(scanningLabel)
        view.addSubview(scanningContainer)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PeerDiscoveryCell.self, forCellReuseIdentifier: "PeerCell")
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 2.0
        rotation.repeatCount = .infinity
        scanningIcon.layer.add(rotation, forKey: "rotation")
        rotationAnimation = rotation
        
        startPulseAnimation()
    }
    
    private func startPulseAnimation() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Таймер живёт на главном run loop, а UIView.animate изолирован
            // главным актором — подтверждаем это компилятору явно.
            MainActor.assumeIsolated {
                UIView.animate(withDuration: 0.5, delay: 0, options: [.autoreverse, .repeat], animations: {
                    self?.scanningLabel.alpha = 0.4
                    self?.scanningIcon.alpha = 0.4
                }, completion: nil)
            }
        }
    }
    
    private func stopAnimations() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        scanningIcon.layer.removeAnimation(forKey: "rotation")
    }
    
    // MARK: - Binding
    
    private func bindViewModel() {
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
    
    private func updateUI() {
        let displayPeers = viewModel.peers.isEmpty ? mockPeers() : viewModel.peers
        
        let connectedCount = displayPeers.filter { $0.status == .connected }.count
        peerCountLabel.text = "PEER: \(connectedCount) CONN"
        
        let averageSignal = calculateAverageSignal(from: displayPeers)
        let signalStatus = getSignalStatus(averageSignal)
        headerLabel.text = "ECHOS // SIGNAL: \(signalStatus)"
        
        tableView.reloadData()
    }
    
    private func calculateAverageSignal(from peers: [Peer]) -> Int {
        let connectedPeers = peers.filter { $0.status == .connected }
        guard !connectedPeers.isEmpty else {
            return 0
        }
        
        let totalSignal = connectedPeers.reduce(0) { sum, peer in
            sum + peer.signalPercentage
        }
        return totalSignal / connectedPeers.count
    }
    
    private func getSignalStatus(_ percentage: Int) -> String {
        switch percentage {
        case 80...100:
            return "STRONG"
            
        case 50..<80:
            return "MEDIUM"
            
        case 20..<50:
            return "WEAK"
            
        default:
            return "LOST"
        }
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
        return viewModel.peers.isEmpty ? mockPeers().count : viewModel.peers.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath) as? PeerDiscoveryCell else {
            return UITableViewCell()
        }
        
        let peers = viewModel.peers.isEmpty ? mockPeers() : viewModel.peers
        let peer = peers[indexPath.row]
        
        cell.configure(with: peer)
        
        if viewModel.peers.isEmpty {
            cell.onConnect = nil
        } else {
            cell.onConnect = { [weak self] in
                self?.connectToPeer(peer)
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !viewModel.peers.isEmpty else {
            showToast("Демо режим - ожидание устройств...")
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
        80
    }
}

// MARK: - MultipeerInvitationDelegate

extension DiscoveryViewController: MultipeerInvitationDelegate {
    func shouldAcceptInvitation(from peerName: String) async -> Bool {
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
                
                alert.view.tintColor = UIColor(hex: "#39FF14")
                
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
    
    private func mockPeers() -> [Peer] {
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
