//
//  ChatTransitionAnimator.swift
//  echos
//
//  Переход между списком разговоров и чатом на пружине.
//
//  Для интерактивного скраббинга аниматор обязан жить отдельным объектом —
//  поэтому реализован interruptibleAnimator(using:): UIKit и жест
//  получают ОДИН UIViewPropertyAnimator, жест двигает его fractionComplete,
//  отпускание продолжает пружиной до конца или разворачивает назад.
//

import UIKit

@MainActor
final class ChatTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    enum Direction {
        case push
        case pop
    }

    let direction: Direction

    /// Единый аниматор перехода. Создаётся лениво, переиспользуется
    /// интерактивным жестом через interruptibleAnimator.
    private(set) var propertyAnimator: UIViewPropertyAnimator?

    init(direction: Direction) {
        self.direction = direction
    }

    /// Каким направлением ответить на пару экранов. `nil` — не наш
    /// переход, пусть UINavigationController рисует дефолт.
    static func direction(operation: UINavigationController.Operation,
                          from: UIViewController,
                          to: UIViewController) -> Direction? {
        switch operation {
        case .push where from is DiscoveryViewController && to is ChatViewController:
            return .push
        case .pop where from is ChatViewController && to is DiscoveryViewController:
            return .pop
        default:
            return nil
        }
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.45
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: context).startAnimation()
    }

    func interruptibleAnimator(using context: UIViewControllerContextTransitioning) -> UIViewPropertyAnimator {
        if let propertyAnimator {
            return propertyAnimator
        }

        guard let from = context.viewController(forKey: .from),
              let to = context.viewController(forKey: .to) else {
            context.completeTransition(true)
            return UIViewPropertyAnimator(duration: 0, curve: .linear, animations: {})
        }

        let container = context.containerView
        let width = container.bounds.width
        container.addSubview(to.view)

        // Чат въезжает справа; список под ним уходит медленнее —
        // параллакс, глубина без единого 3D-слоя.
        switch direction {
        case .push:
            to.view.frame = container.bounds.offsetBy(dx: width, dy: 0)
            from.view.frame = container.bounds
        case .pop:
            container.insertSubview(to.view, belowSubview: from.view)
            to.view.frame = container.bounds.offsetBy(dx: -width * 0.3, dy: 0)
            to.view.alpha = 0.7
            from.view.frame = container.bounds
        }

        // Свежий аниматор без pausesOnCompletion: переход обязан
        // завершиться — иначе UIKit будет ждать его бесконечно. Разворот
        // после завершения здесь не нужен: отмену жест разворачивает до
        // конца, а ушедший экран всё равно снимается.
        let parameters = UISpringTimingParameters(dampingRatio: 0.95)
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context),
                                              timingParameters: parameters)
        animator.addAnimations {
            switch self.direction {
            case .push:
                to.view.frame = container.bounds
                from.view.frame = container.bounds.offsetBy(dx: -width * 0.3, dy: 0)
                from.view.alpha = 0.7
            case .pop:
                to.view.frame = container.bounds
                to.view.alpha = 1
                from.view.frame = container.bounds.offsetBy(dx: width, dy: 0)
            }
        }

        animator.addCompletion { [weak self] position in
            // Отмену жест разворачивает сам: сюда приходим в .start
            // или в .end, и конец — это всегда переход состоявшийся.
            context.completeTransition(position == .end)
            self?.restore(from: from, to: to, in: container)
        }

        propertyAnimator = animator
        return animator
    }

    /// После перехода (или отмены) оставляем вью в честных состояниях:
    /// UIKit сам снимает лишнее, а вот alpha и сдвинутые фреймы
    /// поправить некому.
    private func restore(from: UIViewController, to: UIViewController, in container: UIView) {
        to.view.alpha = 1
        from.view.alpha = 1
        to.view.frame = container.bounds
        from.view.frame = container.bounds
        propertyAnimator = nil
    }
}
