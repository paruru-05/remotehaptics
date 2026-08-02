import Foundation
import SwiftUI

@MainActor
final class RemoteHapticsModel: ObservableObject {
    static let shared = RemoteHapticsModel()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var connectedHost = ""
    @Published var connectedPort: UInt16 = 8765
    @Published var lastMessage = ""
    @Published var isShiftActive = false

    @AppStorage("rh_pin") var pin = "1234"
    @AppStorage("rh_sensitivity") var sensitivity: Double = 1.0
    @AppStorage("rh_haptics") var hapticsEnabled = true
    @AppStorage("rh_autoReconnect") var autoReconnect = true
    @AppStorage("rh_autoConnect") var autoConnect = true

    var effectiveShift: Bool { isShiftActive }

    private let discovery = BonjourDiscovery()
    private var client: InputClient?
    private var reconnectTask: Task<Void, Never>?
    private var scrollAccum: CGFloat = 0
    private var hasShownDiscoveryError = false

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
        client = newClient
        newClient.connect(host: trimmed, port: port, pin: pin)
        lastMessage = ""
    }

    func disconnect() {
        reconnectTask?.cancel()
        client?.disconnect()
        client = nil
        connectionState = .disconnected
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
        InputHaptics.keyPress()
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
