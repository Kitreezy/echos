//
//  ChatTransitionTests.swift
//  echosTests
//
//  Unit: переход список ↔ чат — кастомный аниматор отвечает только на
//  свою пару экранов, остальные переходы остаются дефолтными.
//

import Testing
import UIKit
@testable import echos

@MainActor
struct ChatTransitionTests {

    @Test func push_listToChat_usesCustomTransition() {
        let direction = ChatTransitionAnimator.direction(
            operation: .push,
            from: DiscoveryViewController(viewModel: ChatViewModel()),
            to: ChatViewController(viewModel: ChatViewModel())
        )
        #expect(direction == .push)
    }

    @Test func pop_chatToList_usesCustomTransition() {
        let direction = ChatTransitionAnimator.direction(
            operation: .pop,
            from: ChatViewController(viewModel: ChatViewModel()),
            to: DiscoveryViewController(viewModel: ChatViewModel())
        )
        #expect(direction == .pop)
    }

    @Test func otherTransitions_stayDefault() {
        let list = DiscoveryViewController(viewModel: ChatViewModel())
        let chat = ChatViewController(viewModel: ChatViewModel())
        let nearby = NearbyHostingController(rootView: NearbyView(viewModel: ChatViewModel()))

        // Соседние экраны — дефолтная анимация навигации.
        #expect(ChatTransitionAnimator.direction(operation: .push, from: list, to: nearby) == nil)
        #expect(ChatTransitionAnimator.direction(operation: .push, from: nearby, to: chat) == nil)
        #expect(ChatTransitionAnimator.direction(operation: .pop, from: nearby, to: list) == nil)
        // Не push и не pop — не наш случай вообще.
        #expect(ChatTransitionAnimator.direction(operation: .none, from: list, to: chat) == nil)
    }

    @Test func animator_durationIsPositive() {
        let animator = ChatTransitionAnimator(direction: .push)
        #expect(animator.transitionDuration(using: nil) > 0)
    }
}
