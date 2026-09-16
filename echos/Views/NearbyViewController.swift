//
//  NearbyViewController.swift
//  echos
//
//  Кто здесь сейчас.
//
//  Отдельно от главного экрана намеренно. Главный отвечает на вопрос «с кем я
//  разговариваю», этот — «кто вокруг». Раньше оба списка жили на одном экране,
//  и радар с крутящимся кольцом висел над ними как украшение: он показывал,
//  что поиск идёт, но нажать на него было нельзя, а список под ним состоял из
//  незнакомцев, которых видно и так.
//

import UIKit

final class NearbyViewController: UIViewController {

    private let viewModel: ChatViewModel

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.micro
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setTracked(UserSettings.usesRelay ? "кто на связи" : "кто рядом",
                         tracking: Typography.wide)
        return label
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Пока никого.\nЭкран сам оживёт, когда кто-нибудь появится."
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

    // MARK: - Init

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .surface
        navigationItem.backButtonTitle = "Назад"

        setupLayout()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PeerDiscoveryCell.self, forCellReuseIdentifier: "PeerCell")

        updateUI()
        scheduleObservation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Радар прячет панель навигации, а здесь она нужна: без неё не
        // вернуться.
        navigationController?.setNavigationBarHidden(false, animated: animated)
        updateUI()
    }

    private func setupLayout() {
        view.addSubview(titleLabel)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                            constant: Space.room),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                constant: Space.margin),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                                           constant: Space.ma),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                constant: Space.margin),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                 constant: -Space.margin)
        ])
    }

    // MARK: - Binding

    private func scheduleObservation() {
        withObservationTracking {
            _ = viewModel.peers
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateUI()
                self?.scheduleObservation()
            }
        }
    }

    private func updateUI() {
        emptyLabel.isHidden = !viewModel.peers.isEmpty
        tableView.reloadData()
    }

    // MARK: - Actions

    private func connect(to peer: Peer) {
        Task {
            do {
                try await viewModel.multipeerService?.connectToPeer(address: peer.address)
            }
            catch {
                print("[NearbyViewController] Failed to connect: \(error)")
            }
        }
    }

    private func openChat(with peer: Peer) {
        Task {
            await viewModel.switchToConversation(with: peer.address,
                                                 named: peer.displayName)

            let chat = ChatViewController(viewModel: viewModel)
            navigationController?.pushViewController(chat, animated: true)
        }
    }
}

// MARK: - TableView

extension NearbyViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.peers.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell",
                                                       for: indexPath) as? PeerDiscoveryCell else {
            return UITableViewCell()
        }

        let peer = viewModel.peers[indexPath.row]
        cell.configure(with: peer, recognition: viewModel.recognition(for: peer))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard indexPath.row < viewModel.peers.count else {
            return
        }

        let peer = viewModel.peers[indexPath.row]

        switch peer.status {
        case .connected:
            openChat(with: peer)

        case .notConnected:
            connect(to: peer)

        case .connecting, .failed:
            break  // состояние написано в строке, повторять его нечем
        }
    }
}
