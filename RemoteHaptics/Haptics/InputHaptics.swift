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
        guard isEnabled else { return }
        ensureSetup()
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            transientPlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
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

    /// キー入力: 軽い一瞬のフィードバック
    static func keyPress() {
        shared.play(intensity: 0.22, sharpness: 0.5)
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
