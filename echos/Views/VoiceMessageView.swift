//
//  VoiceMessageView.swift
//  echos
//
//  Форма волны и ячейка голосового сообщения.
//

import UIKit

/// Волна: столбики амплитуд, сыгранное — цветом своих, остальное — тихим.
/// Прогресс — доля 0...1, обновляется во время проигрывания.
final class WaveformView: UIView {

    var samples: [Float] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Доля сыгранного: левее — активным цветом, правее — приглушённым.
    var progress: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    /// Ширина бара и промежуток между ними.
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 2

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !samples.isEmpty else {
            return
        }
        let total = CGFloat(samples.count)
        let slot = barWidth + barSpacing
        let waveHeight = bounds.height

        for (index, amplitude) in samples.enumerated() {
            let played = (CGFloat(index) + 0.5) / total <= progress
            let barHeight = max(barWidth, waveHeight * CGFloat(amplitude))
            let x = CGFloat(index) * slot
            let y = (waveHeight - barHeight) / 2
            let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                                    cornerRadius: barWidth / 2)
            context.setFillColor((played ? UIColor.own : UIColor.inkMuted).cgColor)
            path.fill()
        }
    }

    /// Ширина волны при текущем числе баров — нужна раскладке ячейки.
    var naturalWidth: CGFloat {
        guard !samples.isEmpty else { return 0 }
        return CGFloat(samples.count) * barWidth + CGFloat(samples.count - 1) * barSpacing
    }
}

/// Голосовое сообщение в ленте: кнопка, волна, длительность.
final class VoiceMessageView: UIView {

    /// Нажали на кнопку проигрывания. Состоянием владеет контроллер:
    /// ячейек много, проигрыватель один.
    var onPlayToggle: (() -> Void)?

    let playButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)
        button.tintColor = .ink
        button.accessibilityLabel = String(localized: "Прослушать голосовое")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let waveform = WaveformView()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = Typography.caption
        label.textColor = .inkMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var widthConstraint = waveform.widthAnchor.constraint(equalToConstant: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playButton)
        addSubview(waveform)
        addSubview(durationLabel)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 32),
            playButton.heightAnchor.constraint(equalToConstant: 32),

            waveform.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: Space.step),
            waveform.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 28),
            widthConstraint,

            durationLabel.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: Space.step),
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(duration: TimeInterval, samples: [Float]) {
        waveform.samples = samples
        widthConstraint.constant = waveform.naturalWidth
        durationLabel.text = VoiceAttachment.format(duration: duration)
    }

    /// Состояние проигрывания приезжает снаружи: у ячейки нет плеера.
    func setPlaying(_ playing: Bool, progress: CGFloat) {
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = playing
            ? String(localized: "Остановить голосовое")
            : String(localized: "Прослушать голосовое")
        waveform.progress = progress
    }

    @objc
    private func playTapped() {
        onPlayToggle?()
    }
}
