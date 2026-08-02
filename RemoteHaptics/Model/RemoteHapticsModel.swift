import Foundation
import SwiftUI
import UIKit

@MainActor
final class RemoteHapticsModel: ObservableObject {
    static let shared = RemoteHapticsModel()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    enum InputMode: String, CaseIterable, Identifiable {
        case relative
        case absolute
        var id: String { rawValue }
    }

    struct StreamQualityPreset {
        let label: String
        let w: Int
        let q: Int
    }

    static let qualityPresets = [
        StreamQualityPreset(label: "低", w: 960, q: 55),
        StreamQualityPreset(label: "中", w: 1280, q: 60),
        StreamQualityPreset(label: "高", w: 1600, q: 70)
    ]

    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var connectedHost = ""
    @Published var connectedPort: UInt16 = 8765
    @Published var lastMessage = ""
    @Published var isShiftActive = false

    // 画面中継
    @Published var inputMode: InputMode = .relative
    @Published var screenImage: UIImage?
    @Published var screenSize: CGSize = .zero
    @Published var frameSize: CGSize = .zero
    @Published var isStreaming = false

    // コマンド実行
    @Published var commandHistory: [CommandEntry] = []

    @AppStorage("rh_pin") var pin = "1234"
    @AppStorage("rh_sensitivity") var sensitivity: Double = 1.0
    @AppStorage("rh_haptics") var hapticsEnabled = true
    @AppStorage("rh_autoReconnect") var autoReconnect = true
    @AppStorage("rh_autoConnect") var autoConnect = true
    @AppStorage("rh_quality") var streamQualityIndex = 1
    @AppStorage("rh_dragDelay") var dragDelay: Double = 0.5

    var effectiveShift: Bool { isShiftActive }

    var streamQuality: StreamQualityPreset {
        RemoteHapticsModel.qualityPresets.indices.contains(streamQualityIndex)
            ? RemoteHapticsModel.qualityPresets[streamQualityIndex]
            : RemoteHapticsModel.qualityPresets[1]
    }

    private let discovery = BonjourDiscovery()
    private var client: InputClient?
    private var reconnectTask: Task<Void, Never>?
    private var scrollAccum: CGFloat = 0
    private var hasShownDiscoveryError = false
    private var pendingCmd = ""

    private init() {
        discovery.onServers = { [weak self] servers in
            Task { @MainActor in
                self?.discoveredServers = servers
                self?.autoConnectIfNeeded()
            }
        }
        discovery.start()
        InputHaptics.shared.isEnabled = hapticsEnabled
    }

    // MARK: - Connection

    func connect(to server: DiscoveredServer) {
        connect(host: server.host, port: server.port)
    }

    func connect(host: String, port: UInt16 = 8765) {
        reconnectTask?.cancel()
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastMessage = "ホストを入力してください"
            return
        }
        connectedHost = trimmed
        connectedPort = port

        let newClient = InputClient()
        newClient.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.apply(clientState: state)
            }
        }
        newClient.onAuthError = { [weak self] message in
            Task { @MainActor in
                self?.lastMessage = "認証エラー: \(message)"
            }
        }
        newClient.onUnexpectedDrop = { [weak self] in
            Task { @MainActor in
                self?.scheduleReconnect()
            }
        }
        newClient.onStreamMeta = { [weak self] meta in
            Task { @MainActor in
                guard let self else { return }
                self.screenSize = CGSize(width: CGFloat(meta.screenW), height: CGFloat(meta.screenH))
                self.frameSize = CGSize(width: CGFloat(meta.frameW), height: CGFloat(meta.frameH))
            }
        }
        newClient.onScreenFrame = { [weak self] data in
            guard let image = UIImage(data: data) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.screenImage = image
                self.frameSize = image.size
            }
        }
        newClient.onExecResult = { [weak self] code, out in
            Task { @MainActor in
                self?.appendCommandResult(cmd: self?.pendingCmd ?? "", code: code, output: out)
            }
        }
        client = newClient
        newClient.connect(host: trimmed, port: port, pin: pin)
        lastMessage = ""
    }

    func disconnect() {
        reconnectTask?.cancel()
        client?.disconnect()
        client = nil
        connectionState = .disconnected
        isStreaming = false
        screenImage = nil
        lastMessage = "切断しました"
    }

    private func apply(clientState: InputClient.State) {
        switch clientState {
        case .connecting:
            connectionState = .connecting
            lastMessage = "接続中…"
        case .connected:
            connectionState = .connected
            lastMessage = "\(connectedHost):\(connectedPort) に接続"
            InputHaptics.connected()
        case .disconnected:
            if connectionState == .connected {
                lastMessage = "接続が切れました"
            }
            connectionState = .disconnected
            isStreaming = false
            screenImage = nil
        }
    }

    private func scheduleReconnect() {
        guard autoReconnect else {
            lastMessage = "接続が切れました"
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.connectionState != .connected, self.client != nil else { return }
            self.lastMessage = "再接続中…"
            self.client?.connect(host: self.connectedHost, port: self.connectedPort, pin: self.pin)
        }
    }

    private func autoConnectIfNeeded() {
        guard autoConnect,
              connectionState == .disconnected,
              client == nil,
              let first = discoveredServers.first else { return }
        lastMessage = "自動接続: \(first.display)"
        connect(to: first)
    }

    // MARK: - Trackpad

    func move(dx: CGFloat, dy: CGFloat) {
        guard connectionState == .connected else { return }
        let s = CGFloat(sensitivity)
        client?.send(InputMessage.move(dx: Int(dx * s), dy: Int(dy * s)))
    }

    func scroll(dy: CGFloat) {
        guard connectionState == .connected else { return }
        // dy>0 = 指を下へ → コンテンツ上方向 → REL_WHEEL 正
        let wheel = Int(-dy * CGFloat(sensitivity))
        guard wheel != 0 else { return }
        client?.send(InputMessage.scroll(dy: wheel))
        scrollAccum += CGFloat(abs(wheel))
        if scrollAccum >= 10 {
            InputHaptics.scrollTick()
            scrollAccum = 0
        }
    }

    func click(button: String, down: Bool) {
        guard connectionState == .connected else { return }
        client?.send(InputMessage.click(button: button, down: down))
        if down {
            if button == "left" {
                InputHaptics.leftClick()
            } else {
                InputHaptics.rightClick()
            }
        }
    }

    func moveto(x: Int, y: Int) {
        guard connectionState == .connected, screenSize.width > 0, screenSize.height > 0 else { return }
        client?.send(InputMessage.moveto(x: x, y: y))
    }

    // MARK: - Screen Streaming

    func setInputMode(_ mode: InputMode) {
        inputMode = mode
        if mode == .absolute {
            startStream()
        } else {
            stopStream()
        }
    }

    func startStream() {
        guard connectionState == .connected, !isStreaming else { return }
        let preset = streamQuality
        client?.setStream(on: true, w: preset.w, q: preset.q)
        isStreaming = true
    }

    func stopStream() {
        guard isStreaming else { return }
        client?.setStream(on: false, w: 0, q: 0)
        isStreaming = false
        screenImage = nil
    }

    func applyStreamQualityChange() {
        guard isStreaming, inputMode == .absolute else { return }
        stopStream()
        startStream()
    }

    // MARK: - Command

    func runCommand(_ cmd: String) {
        guard connectionState == .connected else {
            lastMessage = "未接続"
            return
        }
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingCmd = trimmed
        client?.execCommand(trimmed)
    }

    func clearCommandHistory() {
        commandHistory.removeAll()
    }

    private func appendCommandResult(cmd: String, code: Int, output: String) {
        let entry = CommandEntry(cmd: cmd, code: code, output: output, date: Date())
        commandHistory.append(entry)
        if commandHistory.count > 50 {
            commandHistory.removeFirst(commandHistory.count - 50)
        }
    }

    // MARK: - Keyboard

    func keyDown(_ def: KeyDef) {
        guard connectionState == .connected else { return }
        if def.isModifier, def.id == "shiftL" || def.id == "shiftR" {
            isShiftActive = true
            syncShift()
            InputHaptics.modifierPress()
            return
        }
        client?.send(InputMessage.key(code: def.code, down: true))
        InputHaptics.keyPress(strong: def.id == "space" || def.id == "enter" || def.id == "backspace")
    }

    func keyUp(_ def: KeyDef) {
        guard connectionState == .connected else { return }
        if def.isModifier, def.id == "shiftL" || def.id == "shiftR" {
            isShiftActive = false
            syncShift()
            return
        }
        client?.send(InputMessage.key(code: def.code, down: false))
    }

    private func syncShift() {
        client?.send(InputMessage.key(code: "KEY_LEFTSHIFT", down: isShiftActive))
    }
}

/// コマンド実行の履歴 1 件。
struct CommandEntry: Identifiable, Equatable {
    let id = UUID()
    let cmd: String
    let code: Int
    let output: String
    let date: Date
}
