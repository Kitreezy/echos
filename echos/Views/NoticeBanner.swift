//
//  NoticeBanner.swift
//  echos
//
//  Полоска сверху: пришло сообщение не в открытый чат.
//
//  Пушей у echos нет и не будет: рядом связь живёт только вместе с
//  приложением, а сервер о содержимом не знает — слать ему нечего. Зато
//  внутри приложения сообщение доходит на любом экране, и сказать о нём
//  можно самим. Баннер живёт в окне, поверх всего: главный экран, чужой
//  чат, стена — неважно. Нажал — открылся тот чат; смахнул вверх — ушёл;
//  не тронул — ушёл сам через несколько секунд.
//

import UIKit

@MainActor
final class NoticeBanner: UIView {

    /// Один баннер на окно. Новое сообщение заменяет текущий, а не
    /// становится в очередь: очередь из пяти баннеров хуже одного свежего.
    private static var current: NoticeBanner?

    static func show(_ notice: IncomingNotice, in window: UIWindow, onTap: @escaping () -> Void) {
        current?.dismiss()

        let banner = NoticeBanner(notice: notice, onTap: onTap)
        current = banner
        banner.present(in: window)
    }

    private let onTap: () -> Void
    private var topConstraint: NSLayoutConstraint?
    private var hideTask: Task<Void, Never>?

    private init(notice: IncomingNotice, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)

        backgroundColor = .surfaceRaised
        layer.cornerRadius = 14
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.hairline.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let name = UILabel()
        name.font = Typography.micro
        name.textColor = .inkMuted
        name.setTracked(notice.name, tracking: Typography.narrow)

        let column = UIStackView(arrangedSubviews: [name, content(for: notice)])
        column.axis = .vertical
        column.spacing = Space.hair
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: Space.tight + 2),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.step),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.step),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(Space.tight + 2))
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped))
        swipe.direction = .up
        addGestureRecognizer(swipe)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Текст — строкой, мозаика — сеткой поменьше: рисунок узнаётся
    /// и в полоске.
    private func content(for notice: IncomingNotice) -> UIView {
        if let mosaic = notice.mosaic {
            let grid = MosaicView()
            grid.cellSize = 14
            grid.show(mosaic)
            return grid
        }

        let label = UILabel()
        label.font = Typography.body
        label.textColor = .ink
        label.numberOfLines = 2
        label.text = notice.preview
        return label
    }

    // MARK: - Показ

    private func present(in window: UIWindow) {
        window.addSubview(self)
        window.bringSubviewToFront(self)
        let top = topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: -120)
        topConstraint = top
        NSLayoutConstraint.activate([
            top,
            leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: Space.step),
            trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -Space.step)
        ])
        window.layoutIfNeeded()

        top.constant = Space.tight
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0.6) {
            window.layoutIfNeeded()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            // Нажали или смахнули раньше — таймер отменён, и трогать
            // уже ушедший баннер незачем.
            guard !Task.isCancelled else {
                return
            }
            self?.dismiss()
        }
    }

    private func dismiss() {
        hideTask?.cancel()
        guard superview != nil else {
            return
        }
        topConstraint?.constant = -120
        UIView.animate(withDuration: 0.25, animations: {
            self.superview?.layoutIfNeeded()
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
            if Self.current === self {
                Self.current = nil
            }
        })
    }

    @objc
    private func tapped() {
        dismiss()
        onTap()
    }

    @objc
    private func swiped() {
        dismiss()
    }
}
