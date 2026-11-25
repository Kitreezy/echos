//
//  NearbyView.swift
//  echos
//
//  Кто здесь сейчас — на SwiftUI.
//
//  Демонстрация интеграции SwiftUI в UIKit: экран целиком живёт во вью,
//  UIKit остаётся рамкой — UIHostingController в стеке координатора.
//  Обмен состоянием с существующей VM ничего нового не требует:
//  ChatViewModel — @Observable, SwiftUI наблюдает его напрямую (@Bindable),
//  а действия идут теми же вызовами, что раньше шли из UITableViewDelegate.
//  Назад в UIKit вью возвращает события через замыкание, а не через
//  навигационные объекты: SwiftUI не знает про координатор.
//

import OSLog
import SwiftUI

/// Те, кто рядом (или на связи — зависит от способа связи в настройках).
struct NearbyView: View {

    /// Та самая модель чата: наблюдается напрямую, без адаптера и Combine.
    @Bindable var viewModel: ChatViewModel

    /// Открытый чат с собеседником — событие наружу, в UIKit-навигацию.
    var onOpenChat: (Peer) -> Void = { _ in }

    private var title: String {
        UserSettings.usesRelay ? String(localized: "кто на связи") : String(localized: "кто рядом")
    }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            if viewModel.peers.isEmpty {
                empty
            } else {
                list
            }
        }
        .accessibilityLabel(String(localized: "Кто рядом"))
    }

    // MARK: - Содержимое

    private var empty: some View {
        Text("Пока никого.\nЭкран сам оживёт, когда кто-нибудь появится.")
            .font(Typography.captionText)
            .foregroundStyle(Color.inkMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Typography.microText)
                    .tracking(Typography.wide)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.horizontal, Space.margin)
                    .padding(.top, Space.room)
                    .padding(.bottom, Space.ma)

                ForEach(viewModel.peers) { peer in
                    PeerRow(peer: peer, recognition: viewModel.recognition(for: peer))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            select(peer)
                        }
                        .accessibilityHint(tapHint(for: peer))
                }
            }
        }
    }

    // MARK: - Действия

    /// Та же развилка, что была в UITableViewDelegate: подключённому —
    /// чат, свободному — приглашение, остальное — ждать.
    private func select(_ peer: Peer) {
        switch peer.status {
        case .connected:
            onOpenChat(peer)
        case .notConnected:
            connect(to: peer)
        case .connecting, .failed:
            break  // состояние написано в строке, повторять его нечем
        }
    }

    private func connect(to peer: Peer) {
        Task {
            do {
                try await viewModel.multipeerService?.connectToPeer(address: peer.address)
            } catch {
                Logger.screens.error("Nearby: failed to connect: \(error, privacy: .public)")
            }
        }
    }

    private func tapHint(for peer: Peer) -> String {
        switch peer.status {
        case .connected:
            return String(localized: "Открывает чат")
        case .notConnected:
            return String(localized: "Подключается")
        case .connecting, .failed:
            return ""
        }
    }
}

// MARK: - Hosting

/// Рамка, в которую вью сажается в UIKit-навигацию. Обязанности —
/// те, что SwiftUI изнутри вью не видит: панель навигации (радар её
/// прячет, а здесь без неё не вернуться) и имя кнопки возврата.
final class NearbyHostingController: UIHostingController<NearbyView> {

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backButtonTitle = String(localized: "Назад")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}
