import CoreHaptics
import Foundation

/// 入力操作に対する触覚フィードバックを一元管理する。
final class InputHaptics {
    static let shared = InputHaptics()

    var isEnabled = true

    private var engine: CHHapticEngine?
    private var isSetup = false
    private var lastTickAt = Date.distantPast
    private var transientPlayer: CHHapticPatternPlayer?

    private init() {}

    func ensureSetup() {
        guard !isSetup else { return }
        isSetup = true
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                self?.engine = nil
                self?.isSetup = false
                self?.ensureSetup()
            }
            engine.stoppedHandler = { [weak self] reason in
                self?.transientPlayer = nil
            }
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    private func play(intensity: Float, sharpness: Float) {
        playPattern([
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0
            )
        ])
    }

    /// 2 連パルスの触覚 (キー入力など)。
    private func playDouble(intensity: Float, sharpness: Float, gap: TimeInterval) {
        let p: (Float, Float, TimeInterval) -> CHHapticEvent = { i, s, t in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: s)
                ],
                relativeTime: t
            )
        }
        playPattern([
            p(intensity, sharpness, 0),
            p(intensity, sharpness, gap)
        ])
    }

    private func playPattern(_ events: [CHHapticEvent]) {
        guard isEnabled else { return }
        ensureSetup()
        guard let engine else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            transientPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.transientPlayer === player {
                    self?.transientPlayer = nil
                }
            }
        } catch {
            // ハプティクスは失敗しても操作を妨げない
        }
    }

    /// 左クリック: はっきりとした一発
    static func leftClick() {
        shared.play(intensity: 0.9, sharpness: 0.7)
    }

    /// 右クリック: 少し柔らかい一発
    static func rightClick() {
        shared.play(intensity: 0.65, sharpness: 0.35)
    }

    /// キー入力: 強めの単発パルス。
    /// `strong` は Space / Enter / Backspace など多用するキー。
    static func keyPress(strong: Bool = false) {
        if strong {
            shared.play(intensity: 0.9, sharpness: 0.75)
        } else {
            shared.play(intensity: 0.6, sharpness: 0.65)
        }
    }

    /// ドラッグ開始: 強い 2 連パルス
    static func dragStart() {
        shared.playDouble(intensity: 1.0, sharpness: 0.9, gap: 0.03)
    }

    /// ドラッグ終了: 軽い一発
    static func dragEnd() {
        shared.play(intensity: 0.5, sharpness: 0.5)
    }

    /// モディファイア押下: 中程度
    static func modifierPress() {
        shared.play(intensity: 0.4, sharpness: 0.3)
    }

    /// スクロール: しきい値で間引いて連続ティック
    static func scrollTick() {
        let now = Date()
        guard now.timeIntervalSince(shared.lastTickAt) > 0.06 else { return }
        shared.lastTickAt = now
        shared.play(intensity: 0.3, sharpness: 0.6)
    }

    static func connected() {
        shared.play(intensity: 0.7, sharpness: 0.9)
    }
}
