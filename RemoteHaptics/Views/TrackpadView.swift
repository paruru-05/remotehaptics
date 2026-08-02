import SwiftUI
import UIKit

/// マルチタッチ対応トラックパッド。
/// - 1 本指ドラッグ: カーソル移動
/// - タップ: 左クリック
/// - 1 本指長押し: 右クリック
/// - 2 本指ドラッグ: スクロール
/// - 2 本指タップ: 右クリック
struct TrackpadView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TrackpadSurface(model: model)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .padding(8)
                )
                .overlay(
                    Text("ドラッグ=移動 / タップ=左クリック / 2本指=スクロール\n長押し・2本指タップ=右クリック")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(6),
                    alignment: .bottom
                )
        }
    }

    private var statusBar: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.green)
            Text(model.connectedHost)
                .font(.footnote.monospaced())
            Spacer()
            Text(model.lastMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct TrackpadSurface: UIViewRepresentable {
    @ObservedObject var model: RemoteHapticsModel

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.model = model
        return view
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.model = model
    }
}

final class TrackpadUIView: UIView {
    weak var model: RemoteHapticsModel?

    private struct TouchInfo {
        var start: CGPoint
        var current: CGPoint
        var startTime: CFTimeInterval
        var moved = false
    }

    private var touchDict: [UITouch: TouchInfo] = [:]
    private var maxFingers = 0
    private var longPressTimer: Timer?
    private var longPressFired = false

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            touchDict[touch] = TouchInfo(
                start: location,
                current: location,
                startTime: CACurrentMediaTime()
            )
        }
        maxFingers = max(maxFingers, touchDict.count)

        if touchDict.count == 1, let first = touchDict.first {
            longPressFired = false
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self,
                      let info = self.touchDict[first.key],
                      !info.moved else { return }
                self.longPressFired = true
                self.withModel { model in
                    model.click(button: "right", down: true)
                    model.click(button: "right", down: false)
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for touch in touches {
            guard var info = touchDict[touch] else { continue }
            let location = touch.location(in: self)
            dx += location.x - info.current.x
            dy += location.y - info.current.y
            info.current = location
            if abs(location.x - info.start.x) > 5 || abs(location.y - info.start.y) > 5 {
                info.moved = true
            }
            touchDict[touch] = info
        }
        longPressTimer?.invalidate()

        switch touchDict.count {
        case 1:
            if dx != 0 || dy != 0 {
                withModel { $0.move(dx: dx, dy: dy) }
            }
        case 2:
            if dy != 0 {
                withModel { $0.scroll(dy: dy) }
            }
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            touchDict[touch] = nil
        }
        maxFingers = 0
        longPressTimer?.invalidate()
        longPressFired = false
    }

    private func finishTouches(_ touches: Set<UITouch>) {
        let now = CACurrentMediaTime()
        var anyTap = false
        for touch in touches {
            guard let info = touchDict[touch] else { continue }
            let wasTap = !info.moved && (now - info.startTime) < 0.35 && !longPressFired
            if wasTap {
                anyTap = true
            }
            touchDict[touch] = nil
        }
        longPressTimer?.invalidate()

        if anyTap {
            if maxFingers == 1 {
                withModel { model in
                    model.click(button: "left", down: true)
                    model.click(button: "left", down: false)
                }
            } else {
                withModel { model in
                    model.click(button: "right", down: true)
                    model.click(button: "right", down: false)
                }
            }
        }
        if touchDict.isEmpty {
            maxFingers = 0
            longPressFired = false
        }
    }

    private func withModel(_ action: (RemoteHapticsModel) -> Void) {
        guard let model else { return }
        MainActor.assumeIsolated {
            action(model)
        }
    }
}
