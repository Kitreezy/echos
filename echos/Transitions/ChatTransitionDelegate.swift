//
//  ChatTransitionDelegate.swift
//  echos
//
//  Навигационный делегат для перехода список ↔ чат.
//
//  Даёт кастомный аниматор только для этой пары; соседние переходы
//  (кто рядом, стена) рисуются дефолтом. С левого края чата тянуть назад
//  можно жестом: UIScreenEdgePanGestureRecognizer скраббит тот же
//  UIViewPropertyAnimator через UIPercentDrivenInteractiveTransition —
//  пружина едет за пальцем, отпускание доезжает или разворачивается,
//  от скорости, а не от порога.
//

import UIKit

@MainActor
final class ChatTransitionDelegate: NSObject, UINavigationControllerDelegate {

    private(set) var interaction: UIPercentDrivenInteractiveTransition?
    private weak var navigationController: UINavigationController?

    /// Подключиться к навигации и повесить жест возврата.
    func attach(to navigationController: UINavigationController) {
        self.navigationController = navigationController
        navigationController.delegate = self

        let swipeBack = UIScreenEdgePanGestureRecognizer(target: self,
                                                         action: #selector(handleBackSwipe(_:)))
        swipeBack.edges = .left
        navigationController.view.addGestureRecognizer(swipeBack)
    }

    // MARK: - UINavigationControllerDelegate

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let direction = ChatTransitionAnimator.direction(operation: operation,
                                                               from: fromVC,
                                                               to: toVC) else {
            return nil
        }
        return ChatTransitionAnimator(direction: direction)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        interaction
    }

    // MARK: - Жест

    @objc
    private func handleBackSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard let navigationController else {
            return
        }
        // Тянуть назад можно только с чата: жест живёт на навигации
        // целиком, а не на самом чате.
        guard navigationController.topViewController is ChatViewController else {
            return
        }

        let width = navigationController.view.bounds.width
        let progress = max(0, min(1, recognizer.translation(in: navigationController.view).x / width))

        switch recognizer.state {
        case .began:
            let interaction = UIPercentDrivenInteractiveTransition()
            self.interaction = interaction
            // popViewController спросит interactionControllerFor — вернём
            // только что созданный, и дальше жест ведёт его сам.
            navigationController.popViewController(animated: true)

        case .changed:
            interaction?.update(progress)

        case .ended:
            // Финиш — от скорости: дёрнул резко — доедет даже с малого
            // прогресса; вёз медленно — вернётся, не долетев до трети.
            let velocity = recognizer.velocity(in: navigationController.view).x
            if progress > 0.35 || velocity > 800 {
                interaction?.finish()
            } else {
                interaction?.cancel()
            }
            interaction = nil

        default:
            interaction?.cancel()
            interaction = nil
        }
    }
}
