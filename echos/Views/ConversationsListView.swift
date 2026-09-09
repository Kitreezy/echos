//
//  ConversationsListView.swift
//  echos
//
//  Created by Artem Rodionov on 27.02.2026.
//

import SwiftUI

struct ConversationsListView: View {
    
    @Bindable var viewModel: ChatViewModel
    @State private var conversations: [ConversationSummary] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Загрузка чатов...")
            } else if conversations.isEmpty {
                emptyState
            } else {
                conversationsList
            }
        }
        .navigationTitle("Все чаты")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadConversations()
        }
    }
    
    // MARK: - Conversations List
    
    private var conversationsList: some View {
        List(conversations) { conversation in
            Button  {
                openConversation(conversation)
            } label: {
                ConversationRow(conversation: conversation)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет чатов", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Подключитесь к устройствам, чтобы начать общение.")
        }
    }
    
    // MARK: - Actions
    
    private func loadConversations() async {
        conversations = await viewModel.getAllConversations()
        isLoading = false
    }
    
    private func openConversation(_ conversation: ConversationSummary) {
        Task {
            await viewModel.switchToConversation(with: conversation.peerAddress,
                                                 named: conversation.peerName)
            dismiss()
        }
    }
}
