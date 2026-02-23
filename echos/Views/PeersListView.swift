//
//  PeersListView.swift
//  echos
//
//  Created by Artem Rodionov on 24.02.2026.
//

import SwiftUI

struct PeersListView: View {
    
    @Bindable var viewModel: ChatViewModel
    
    var body: some View {
        List(viewModel.peers) { peer in
            HStack {
                Image(systemName: peer.statusIcon)
                    .foregroundStyle(peer.statusColor)
                
                VStack(alignment: .leading) {
                    Text(peer.displayName)
                        .font(.headline)
                    Text(peer.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Устройства рядом")
        .navigationBarTitleDisplayMode(.inline)
    }
}
