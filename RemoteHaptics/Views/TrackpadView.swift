import SwiftUI
import UIKit

/// マルチタッチ対応トラックパッド。
/// - 1 本指ドラッグ: カーソル移動 (相対) / 画面座標へ移動 (絶対)
/// - 静止 0.5 秒: ドラッグ開始 (左ボタン保持)
/// - タップ: 左クリック
/// - 2 本指ドラッグ: スクロール
/// - 2 本指タップ: 右クリック (長押し右クリックは廃止)
struct TrackpadView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            modeSelector
            ZStack {
                background
                TrackpadSurface(model: model)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(8)
            guideText
        }
    }

    private var modeSelector: some View {
        Picker("モード", selection: Binding(
            get: { model.inputMode },
            set: { model.setInputMode($0) }
        )) {
            Text("相対").tag(RemoteHapticsModel.InputMode.relative)
            Text("絶対").tag(RemoteHapticsModel.InputMode.absolute)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var background: some View {
        if model.inputMode == .absolute, let image = model.screenImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color(uiColor: .secondarySystemBackground)
        }
    }

    private var guideText: some View {
        Text("1本指=移動 / 静止=ドラッグ / タップ=左 / 2本指=スクロール / 2本指タップ=右")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 6)
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

    private enum State {
        case idle
        case touching
        case dragging
        case twoFinger
    }

    private struct TouchInfo {
        var start: CGPoint
        var current: CGPoint
        var startTime: CFTimeInterval
        var moved = false
    }

    private var state: State = .idle
    private var touchDict: [UITouch: TouchInfo] = [:]
    private var dragTimer: Timer?
    private var singleStartTime: CFTimeInterval = 0
    private var singleMoved = false
    private var twoFingerStart: CFTimeInterval = 0
    private var twoFingerMoved = false

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dragTimer?.invalidate()
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        for touch in touches {
            let location = touch.location(in: self)
            touchDict[touch] = TouchInfo(
                start: location,
                current: location,
                startTime: now
            )
        }

        switch state {
        case .idle:
            state = .touching
            singleStartTime = now
            singleMoved = false
            startDragTimer()
            if isAbsoluteMode, let first = touchDict.values.first {
                sendMoveto(first.current)
            }
        case .touching:
            cancelDragTimer()
            enterTwoFinger(now)
        case .dragging:
            cancelDragTimer()
            endDrag()
            enterTwoFinger(now)
        case .twoFinger:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var movedAny = false
        for touch in touches {
            guard var info = touchDict[touch] else { continue }
            let location = touch.location(in: self)
            dx += location.x - info.current.x
            dy += location.y - info.current.y
            if abs(location.x - info.start.x) > 8 || abs(location.y - info.start.y) > 8 {
                info.moved = true
                movedAny = true
            }
            info.current = location
            touchDict[touch] = info
        }

        switch state {
        case .touching:
            if movedAny {
                singleMoved = true
                cancelDragTimer()
            }
            if isAbsoluteMode {
                if let first = touchDict.values.first {
                    sendMoveto(first.current)
                }
            } else if dx != 0 || dy != 0 {
                sendMove(dx: dx, dy: dy)
            }
        case .dragging:
            if isAbsoluteMode {
                if let first = touchDict.values.first {
                    sendMoveto(first.current)
                }
            } else if dx != 0 || dy != 0 {
                sendMove(dx: dx, dy: dy)
            }
        case .twoFinger:
            if movedAny {
                twoFingerMoved = true
            }
            if dy != 0 {
                sendScroll(dy)
            }
        case .idle:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishTouches(touches, cancelled: true)
    }

    // MARK: - State transitions

    private func enterTwoFinger(_ now: CFTimeInterval) {
        state = .twoFinger
        twoFingerStart = now
        twoFingerMoved = false
    }

    private func startDragTimer() {
        dragTimer?.invalidate()
        let delay = withModel { $0.dragDelay } ?? 0.5
        dragTimer = Timer.scheduledTimer(withTimeInterval: max(0.2, min(1.2, delay)), repeats: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.dragTimerFired()
            }
        }
    }

    private func cancelDragTimer() {
        dragTimer?.invalidate()
        dragTimer = nil
    }

    private func dragTimerFired() {
        guard state == .touching, !singleMoved else { return }
        state = .dragging
        sendLeftDown()
        InputHaptics.dragStart()
    }

    private func endDrag() {
        sendLeftUp()
        InputHaptics.dragEnd()
    }

    private func finishTouches(_ touches: Set<UITouch>, cancelled: Bool) {
        let now = CACurrentMediaTime()
        let prevState = state
        for touch in touches {
            touchDict[touch] = nil
        }
        cancelDragTimer()

        switch prevState {
        case .touching:
            if !cancelled {
                let wasTap = !singleMoved && (now - singleStartTime) < 0.35
                if wasTap {
                    sendLeftClick()
                }
            }
            state = .idle
        case .dragging:
            if !cancelled {
                endDrag()
            }
            state = .idle
        case .twoFinger:
            if !cancelled, touchDict.isEmpty {
                let wasTap = !twoFingerMoved && (now - twoFingerStart) < 0.35
                if wasTap {
                    sendRightClick()
                }
            }
            if touchDict.isEmpty {
                state = .idle
            }
        case .idle:
            break
        }
    }

    // MARK: - Sending

    private var isAbsoluteMode: Bool {
        withModel { $0.inputMode == .absolute } ?? false
    }

    private func sendMove(dx: CGFloat, dy: CGFloat) {
        withModel { $0.move(dx: dx, dy: dy) }
    }

    private func sendScroll(_ dy: CGFloat) {
        withModel { $0.scroll(dy: dy) }
    }

    private func sendLeftDown() {
        withModel { $0.click(button: "left", down: true) }
    }

    private func sendLeftUp() {
        withModel { $0.click(button: "left", down: false) }
    }

    private func sendLeftClick() {
        withModel { model in
            model.click(button: "left", down: true)
            model.click(button: "left", down: false)
        }
    }

    private func sendRightClick() {
        withModel { model in
            model.click(button: "right", down: true)
            model.click(button: "right", down: false)
        }
    }

    private func sendMoveto(_ point: CGPoint) {
        withModel { model in
            guard model.frameSize.width > 0, model.frameSize.height > 0,
                  model.screenSize.width > 0, model.screenSize.height > 0 else { return }
            let rect = aspectFitRect(imageSize: model.frameSize, in: bounds)
            guard rect.contains(point) else { return }
            let nx = (point.x - rect.minX) / rect.width
            let ny = (point.y - rect.minY) / rect.height
            let sx = Int(nx * model.screenSize.width)
            let sy = Int(ny * model.screenSize.height)
            model.moveto(x: sx, y: sy)
        }
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGRect) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: container.minX + (container.width - w) / 2,
            y: container.minY + (container.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func withModel<T>(_ action: (RemoteHapticsModel) -> T) -> T? {
        guard let model else { return nil }
        return MainActor.assumeIsolated {
            action(model)
        }
    }
}
