import Foundation

/// WebSocket 接続・認証・送信を管理する。
/// コールバックはすべてメインスレッドで呼ばれる。
final class InputClient {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
    }

    var onStateChange: ((State) -> Void)?
    var onAuthError: ((String) -> Void)?
    /// 接続中に意図せず切断された場合に呼ばれる (自動再接続用)。
    var onUnexpectedDrop: (() -> Void)?

    private(set) var state: State = .disconnected

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var isReceiving = false
    private var shouldBeConnected = false

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    func connect(host: String, port: UInt16, pin: String) {
        disconnect()
        guard let url = URL(string: "ws://\(host):\(port)") else {
            setState(.disconnected)
            return
        }
        shouldBeConnected = true
        setState(.connecting)

        let task = session.webSocketTask(with: url)
        task.resume()
        self.task = task
        sendRaw(InputMessage.auth(pin: pin))
        startPing()
        receiveLoop(task: task)
    }

    func disconnect() {
        shouldBeConnected = false
        stopPing()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isReceiving = false
        setState(.disconnected)
    }

    func send(_ dict: [String: Any]) {
        guard let task, let data = InputMessage.jsonData(dict) else { return }
        task.send(.data(data)) { _ in }
    }

    // MARK: - private

    private func sendRaw(_ dict: [String: Any]) {
        send(dict)
    }

    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.send(InputMessage.ping())
        }
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        guard isReceiving == false, task === self.task else { return }
        isReceiving = true
        receiveNext(task: task)
    }

    private func receiveNext(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.task === task else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveNext(task: task)
            case .failure:
                self.handleDrop(task: task)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:
            return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String else { return }

        switch t {
        case "ok":
            setState(.connected)
        case "err":
            let msg = obj["msg"] as? String ?? "認証エラー"
            shouldBeConnected = false
            stopPing()
            onAuthError?(msg)
            task?.cancel(with: .protocolError, reason: nil)
            task = nil
            isReceiving = false
            setState(.disconnected)
        default:
            break
        }
    }

    private func handleDrop(task: URLSessionWebSocketTask) {
        isReceiving = false
        guard self.task === task else { return }
        stopPing()
        let wasConnected = state == .connected
        self.task = nil
        setState(.disconnected)
        if shouldBeConnected, wasConnected {
            onUnexpectedDrop?()
        }
        shouldBeConnected = false
    }
}
