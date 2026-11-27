//
//  VoiceRecordingBar.swift
//  echos
//
//  Панель записи голосового — вместо поля ввода, пока пишем.
//
//  Сама ничего не записывает: спрашивает у контроллера время и уровень
//  и показывает кнопки. Контроллер владеет рекордером — одна голова
//  на экран, как у проигрывателя.
//

import UIKit

@MainActor
protocol VoiceRecordingBarDelegate: AnyObject {
    func recordingBarDidAskToSend(_ bar: VoiceRecordingBar)
    func recordingBarDidAskToCancel(_ bar: VoiceRecordingBar)
    func recordingBarDidTogglePause(_ bar: VoiceRecordingBar)
    /// Сколько уже записано, с учётом пауз.
    func recordingBarElapsedTime(_ bar: VoiceRecordingBar) -> TimeInterval
    /// Уровень для живой полоски, 0...1.
    func recordingBarLevel(_ bar: VoiceRecordingBar) -> Float
    /// Пишем ли сейчас (пауза меняет кнопку и цвет точки).
    func recordingBarIsRecording(_ bar: VoiceRecordingBar) -> Bool
}

/// Живая полоска уровня: тонкая волна, которая дышит за звуком.
final class VoiceRecordingBar: UIView {

    weak var delegate: VoiceRecordingBarDelegate?

    private let dotView: UIView = {
        let view = UIView()
        view.backgroundColor = .lost
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .ink
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let levelView = WaveformView()

    private let pauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        button.tintColor = .ink
        button.accessibilityLabel = String(localized: "Пауза записи")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .inkMuted
        button.accessibilityLabel = String(localized: "Отменить запись")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up"), for: .normal)
        button.tintColor = .own
        button.accessibilityLabel = String(localized: "Отправить голосовое")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Таймер обновления времени и полоски. Живёт, пока видна панель.
    private var ticker: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .surface

        levelView.translatesAutoresizingMaskIntoConstraints = false
        levelView.barWidth = 2
        levelView.barSpacing = 1.5
        addSubview(dotView)
        addSubview(timeLabel)
        addSubview(levelView)
        addSubview(pauseButton)
        addSubview(cancelButton)
        addSubview(sendButton)

        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.step),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            timeLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: Space.tight),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            levelView.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: Space.step),
            levelView.trailingAnchor.constraint(equalTo: pauseButton.leadingAnchor, constant: -Space.tight),
            levelView.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelView.heightAnchor.constraint(equalToConstant: 20),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.step),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),

            cancelButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -Space.hair),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 40),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            pauseButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -Space.hair),
            pauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pauseButton.widthAnchor.constraint(equalToConstant: 40),
            pauseButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startTicker()
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let delegate else {
            return
        }
        timeLabel.text = VoiceAttachment.format(duration: delegate.recordingBarElapsedTime(self))
        let level = delegate.recordingBarLevel(self)
        // Полоска — скользящее окно последних уровней: пишет слева направо.
        var samples = levelView.samples
        samples.append(level)
        if samples.count > 40 {
            samples.removeFirst(samples.count - 40)
        }
        levelView.samples = samples
        levelView.progress = 1
        pauseButton.setImage(UIImage(systemName: delegate.recordingBarIsRecording(self) ? "pause.fill" : "play.fill"),
                             for: .normal)
        dotView.backgroundColor = delegate.recordingBarIsRecording(self) ? .lost : .inkMuted
    }

    @objc
    private func pauseTapped() {
        delegate?.recordingBarDidTogglePause(self)
    }

    @objc
    private func cancelTapped() {
        delegate?.recordingBarDidAskToCancel(self)
    }

    @objc
    private func sendTapped() {
        delegate?.recordingBarDidAskToSend(self)
    }
}
