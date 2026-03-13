//
//  ConversationRow.swift
//  echos
//
//  Created by Artem Rodionov on 27.02.2026.
//

import SwiftUI

struct ConversationRow: View {
    
    let conversation: ConversationSummary
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(conversation.isActive ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Text(String(conversation.peerName.prefix(1)))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(conversation.isActive ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.peerName)
                        .font(.headline)
                    
                    if conversation.isActive {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                    }
                    
                    Spacer()
                    
                    Text(conversation.lastMessageTime, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(conversation.lastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ConversationsListView(viewModel: ChatViewModel())
    }
}
