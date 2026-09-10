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

    /// Своё имя — под названием приложения, нажатием меняется.
    ///
    /// Место выбрано не от нехватки: имя это про вас, и стоять ему там же,
    /// где имя приложения. Отдельного экрана настроек в echos нет, а прятать
    /// единственную настройку в меню чужого экрана — верный способ, чтобы её
    /// не нашли.
    private lazy var nameButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        config.baseForegroundColor = .ink

        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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
    
    /// Своя стена. Раньше открывалась только из меню чата, то есть была
    /// недоступна, пока рядом никого нет, — хотя смысл стены как раз в том,
    /// чтобы смотреть её, когда никого нет.
    private lazy var wallButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            "моя стена",
            attributes: AttributeContainer([
                .font: Typography.micro,
                .kern: Typography.narrow
            ])
        )
        config.baseForegroundColor = .inkMuted

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Когда разговоров ещё не было. Отдельно от строки под радаром: та про
    /// то, кто вокруг, эта — про то, с кем вы говорили.
    private let noConversationsLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Разговоров пока нет.\nНажмите на круг, чтобы посмотреть, кто рядом."
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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

    /// Ваши люди. Главный экран отвечает на вопрос «с кем я разговариваю», а
    /// не «кто вокруг»: вокруг может не быть никого, а разговоры остаются.
    private var conversations: [ConversationSummary] = []

    /// Загрузка идёт из базы и асинхронно, а поводов обновиться много —
    /// без этого флага они бы наслаивались.
    private var isReloadingConversations = false
    
    // MARK: - Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: animated)

        // Возврат из чата — там могли написать, и последняя реплика в списке
        // уже другая.
        reloadConversations()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // У радара нет заголовка, поэтому кнопка возврата на вложенных
        // экранах называлась бы системным «Back».
        navigationItem.backButtonTitle = "Назад"

        setupUI()
        setupTableView()
        bindViewModel()
        startAnimations()
        setupAppLifecycleObservers()

        updateNameButton()

        // Поиск не начинается, пока не спросили имя: иначе собеседники
        // увидят «Без имени», и переименование уже ничего не исправит —
        // они запомнят вас таким.
        Task {
            if !UserSettings.hasCompletedOnboarding {
                await askForName(
                    title: "Как вас зовут?",
                    message: "Это имя увидят те, кто окажется рядом."
                )
            }

            await startDiscovery()
        }
    }

    // MARK: - Имя

    private func updateNameButton() {
        nameButton.configuration?.attributedTitle = AttributedString(
            UserSettings.displayName,
            attributes: AttributeContainer([
                .font: Typography.micro,
                .kern: Typography.narrow
            ])
        )
    }

    @objc
    private func changeName() {
        Task {
            await askForName(title: "Как вас зовут?",
                             message: "Имя увидят те, кто окажется рядом.")

            // Транспорт берёт имя при создании, поэтому пересобираем его
            // целиком. Заодно снимаются старые подписки.
            viewModel.multipeerService?.stopDeviceDiscovery()
            await startDiscovery()
        }
    }

    private func startDiscovery() async {
        viewModel.initialize()
        viewModel.multipeerService?.approvalDelegate = self
        await viewModel.startDeviceDiscovery()
        radarState.isScanning = true
    }

    /// Спрашивает имя и не отпускает, пока не назовут.
    ///
    /// Отмены нет намеренно: без имени в echos делать нечего, а «Без имени»
    /// в списке у собеседника — не тот результат, ради которого стоит давать
    /// выбор.
    private func askForName(title: String, message: String) async {
        await withCheckedContinuation { continuation in
            presentNameAlert(title: title, message: message) {
                continuation.resume()
            }
        }
    }

    private func presentNameAlert(title: String,
                                  message: String,
                                  completion: @escaping () -> Void) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)

        alert.addTextField { field in
            field.placeholder = "Имя"
            field.text = UserSettings.userName
            field.autocapitalizationType = .words
            field.returnKeyType = .done
            field.clearButtonMode = .whileEditing
        }

        let confirm = UIAlertAction(title: "Готово", style: .default) { [weak self] _ in
            let entered = alert.textFields?.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !entered.isEmpty else {
                // Пустое имя — не ответ. Спрашиваем заново.
                self?.presentNameAlert(title: title, message: message, completion: completion)
                return
            }

            UserSettings.userName = entered
            self?.updateNameButton()
            completion()
        }

        alert.addAction(confirm)
        alert.preferredAction = confirm
        present(alert, animated: true)
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

            nameButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                                            constant: Space.tight),
            nameButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameButton.trailingAnchor.constraint(lessThanOrEqualTo: peerCountLabel.leadingAnchor,
                                                 constant: -Space.step),

            peerCountLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            peerCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                     constant: -Space.margin),

            radarView.topAnchor.constraint(equalTo: nameButton.bottomAnchor, constant: Space.ma),
            radarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            radarView.widthAnchor.constraint(equalToConstant: 240),
            radarView.heightAnchor.constraint(equalToConstant: 240),

            statusLabel.topAnchor.constraint(equalTo: radarView.bottomAnchor, constant: Space.room),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: Space.ma),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: wallButton.topAnchor),

            noConversationsLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            noConversationsLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            noConversationsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                          constant: Space.margin),
            noConversationsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                           constant: -Space.margin),

            wallButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wallButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                               constant: -Space.step)
        ]
    }()
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = UIColor.surface
        
        setupLayout()
    }
    
    private func setupLayout() {
        view.addSubview(titleLabel)
        view.addSubview(nameButton)
        view.addSubview(peerCountLabel)
        view.addSubview(radarView)
        view.addSubview(statusLabel)
        view.addSubview(tableView)
        view.addSubview(noConversationsLabel)
        view.addSubview(wallButton)

        wallButton.addTarget(self, action: #selector(showOwnWall), for: .touchUpInside)
        nameButton.addTarget(self, action: #selector(changeName), for: .touchUpInside)

        // Круг был украшением: он показывал, что поиск идёт, но нажать на
        // него было нельзя. Теперь это единственный вход к тем, кто вокруг.
        radarView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(showNearby))
        )
        radarView.isUserInteractionEnabled = true

        let statusTap = UITapGestureRecognizer(target: self, action: #selector(showNearby))
        statusLabel.addGestureRecognizer(statusTap)
        statusLabel.isUserInteractionEnabled = true
        
        NSLayoutConstraint.activate(layoutConstraints)
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ConversationCell.self,
                           forCellReuseIdentifier: ConversationCell.reuseIdentifier)
    }
    
    @objc
    private func showOwnWall() {
        guard let transport = viewModel.multipeerService else {
            return
        }

        let wall = WallView(
            viewModel: WallViewModel(owner: nil, transport: transport),
            ownAddress: transport.myAddress
        )

        // Радар прячет панель навигации в viewWillAppear, и стена без этой
        // строки открывалась бы без кнопки «назад». При возврате радар
        // спрячет её снова сам.
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(UIHostingController(rootView: wall),
                                                 animated: true)
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
        radarState.nearbyCount = displayPeers.count

        // Строка под кругом — про то, кто вокруг, и она же подсказывает, что
        // круг нажимается.
        statusLabel.text = displayPeers.isEmpty
            ? "Пока никого рядом"
            : "Рядом \(displayPeers.count) — посмотреть"

        // Кто на связи, видно по точке в строке разговора, поэтому список
        // пересобирается и при изменении присутствия.
        reloadConversations()
    }

    /// Перечитать разговоры и перерисовать список.
    private func reloadConversations() {
        guard !isReloadingConversations else {
            return
        }

        isReloadingConversations = true

        Task { [weak self] in
            guard let self else {
                return
            }

            conversations = await viewModel.getAllConversations()
            isReloadingConversations = false

            noConversationsLabel.isHidden = !conversations.isEmpty
            tableView.reloadData()
        }
    }

    @objc
    private func showNearby() {
        navigationController?.pushViewController(
            NearbyViewController(viewModel: viewModel), animated: true
        )
    }
    
}
 
// MARK: - TableView
 
extension DiscoveryViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        conversations.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ConversationCell.reuseIdentifier,
            for: indexPath) as? ConversationCell else {
            return UITableViewCell()
        }

        cell.configure(with: conversations[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.row < conversations.count else {
            return
        }

        let conversation = conversations[indexPath.row]

        Task {
            await viewModel.switchToConversation(with: conversation.peerAddress,
                                                 named: conversation.peerName)

            navigationController?.pushViewController(
                ChatViewController(viewModel: viewModel), animated: true
            )
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
