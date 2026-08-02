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
    /// 画面情報が届いたときに呼ばれる。
    var onStreamMeta: ((StreamMeta) -> Void)?
    /// JPEG フレームが届いたときに呼ばれる。
    var onScreenFrame: ((Data) -> Void)?
    /// コマンド実行結果が届いたときに呼ばれる。
    var onExecResult: ((Int, String) -> Void)?

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

    func moveto(x: Int, y: Int) {
        send(InputMessage.moveto(x: x, y: y))
    }

    func setStream(on: Bool, w: Int = 1280, q: Int = 60) {
        send(InputMessage.stream(on: on, w: w, q: q))
    }

    func execCommand(_ cmd: String) {
        send(InputMessage.exec(cmd: cmd))
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
        switch message {
        case .string(let s):
            handleText(s)
        case .data(let d):
            onScreenFrame?(d)
        @unknown default:
            break
        }
    }

    private func handleText(_ text: String) {
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
        case "stream_meta":
            if let meta = StreamMeta(obj) {
                onStreamMeta?(meta)
            }
        case "exec_out":
            let code = obj["code"] as? Int ?? -1
            let out = obj["out"] as? String ?? ""
            onExecResult?(code, out)
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
