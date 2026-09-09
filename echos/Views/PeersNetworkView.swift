//
//  PeersNetworkView.swift
//  echos
//
//  Created by Artem Rodionov on 13.03.2026.
//

import SwiftUI

struct PeersNetworkView: View {
    
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var activePeers: [Peer] {
        viewModel.peers.filter { $0.status == .connected }
    }
    
    var lostPeers: [Peer] {
        // TODO: Добавить логику для "потерянных" peers
        []
    }
    
    var knownPeers: [Peer] {
        viewModel.peers.filter { $0.status == .notConnected }
    }
    
    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(Color.own)
                    
                    Text("EKKO // PEER_NETWORK")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.own)
                    
                    Spacer()
                    
                    Button {
                        // Settings
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Color.own)
                    }
                }
                .padding()
                .background(Color.surface)
                
                Divider()
                    .background(Color.own.opacity(0.3))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Active Transmissions
                        if !activePeers.isEmpty {
                            SectionHeader(
                                icon: "■",
                                title: "ACTIVE TRANSMISSIONS",
                                color: Color.own
                            )
                            
                            VStack(spacing: 12) {
                                ForEach(activePeers) { peer in
                                    PeerNetworkCard(
                                        peer: peer,
                                        type: .active,
                                        onTap: {
                                            openChat(with: peer)
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Lost Contacts
                        if !lostPeers.isEmpty {
                            SectionHeader(
                                icon: "■",
                                title: "LOST CONTACTS",
                                color: Color.lost
                            )
                            
                            VStack(spacing: 12) {
                                ForEach(lostPeers) { peer in
                                    PeerNetworkCard(
                                        peer: peer,
                                        type: .lost,
                                        onTap: {}
                                    )
                                }
                            }
                        }
                        
                        // Known Frequency
                        if !knownPeers.isEmpty {
                            SectionHeader(
                                icon: "■",
                                title: "KNOWN FREQUENCY",
                                color: Color.inkMuted
                            )
                            
                            VStack(spacing: 12) {
                                ForEach(knownPeers) { peer in
                                    PeerNetworkCard(
                                        peer: peer,
                                        type: .known,
                                        onTap: {}
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Bottom Button
                Button {
                    dismiss()
                } label: {
                    Text("START NEW SCAN")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.surface)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.own)
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
    }
    
    private func openChat(with peer: Peer) {
        Task {
            await viewModel.switchToConversation(with: peer.displayName)
            dismiss()
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.top, 8)
    }
}

// MARK: - Peer Network Card

enum PeerCardType {
    case active
    case lost
    case known
    
    var color: Color {
        switch self {
        case .active: return Color.own
        case .lost: return Color.lost
        case .known: return Color.inkMuted
        }
    }
}

struct PeerNetworkCard: View {
    let peer: Peer
    let type: PeerCardType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Side bar
                Rectangle()
                    .fill(type.color)
                    .frame(width: 4)
                
                HStack {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(type.color, lineWidth: 1)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "person.fill")
                            .foregroundColor(type.color)
                    }
                    .padding(.leading, 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.displayName.uppercased())
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(type.color)
                        
                        Text(type == .active ? "SYNC: 100% // 12M AWAY" : "OFFLINE // ENCRYPTED HISTORY ONLY")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(type.color.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    if type == .active {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(type.color)
                            .padding(.trailing, 12)
                    }
                }
                .frame(height: 68)
            }
            .background(Color.surfaceRaised)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(type.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
