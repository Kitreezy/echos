//
//  SpringAnimation.swift
//  echos
//
//  Пружинные аниматоры в одном месте.
//
//  UIView.animate(usingSpringWithDamping:) удобен, но анонимен: бегущую
//  анимацию так не перехватишь. UIViewPropertyAnimator — объект, и у него
//  есть ручки: бегущую пружину разворачивают назад (isReversed +
//  startAnimation), а fractionComplete скраббит жестом (интерактивный
//  переход в чат). Одно ограничение держим железным: аниматор после
//  завершения отпускаем — pausesOnCompletion оставляет его висеть, и
//  приложение никогда не «успокаивается» (XCUI, фоновые механизмы).
//

import UIKit

@MainActor
enum SpringAnimation {

    /// Появление: собрано натянутой пружиной, чуть перелетает и садится.
    /// Ответ = damping 0.85, стартовая скорость — как у баннера раньше.
    static func appear(duration: TimeInterval = 0.45,
                       damping: CGFloat = 0.85,
                       velocity: CGFloat = 0.6,
                       animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        // velocity здесь — стартовая скорость пружины: передаём через
        // UISpringTimingParameters, у duration/dampingRatio-инициализатора
        // своей ручки для неё нет.
        let parameters = UISpringTimingParameters(dampingRatio: damping,
                                                  initialVelocity: CGVector(dx: velocity, dy: velocity))
        let animator = UIViewPropertyAnimator(duration: duration,
                                              timingParameters: parameters)
        animator.addAnimations(animations)
        return animator
    }

    /// Исчезновение: без перелёта, просто стекло в ноль.
    static func fadeOut(duration: TimeInterval = 0.2,
                        animations: @escaping () -> Void) -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: duration, curve: .easeOut, animations: animations)
    }
}
