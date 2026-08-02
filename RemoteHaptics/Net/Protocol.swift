import Foundation

/// RemoteHaptics サーバーとの WebSocket JSON プロトコル定義。
///
/// 送信メッセージは常に `t` フィールドを含む辞書。
/// - auth:    {"t":"auth","pin":"1234"}          → {"t":"ok"} / {"t":"err"}
/// - move:    {"t":"move","dx":int,"dy":int}     相対カーソル移動
/// - scroll:  {"t":"scroll","dy":int}            縦スクロール (上=正)
/// - click:   {"t":"click","btn":"left","down":bool}
/// - key:     {"t":"key","code":"KEY_A","down":bool}
/// - ping:    {"t":"ping"}                        → {"t":"pong"}
enum InputMessage {
    static func auth(pin: String) -> [String: Any] {
        ["t": "auth", "pin": pin]
    }

    static func move(dx: Int, dy: Int) -> [String: Any] {
        ["t": "move", "dx": dx, "dy": dy]
    }

    static func scroll(dy: Int) -> [String: Any] {
        ["t": "scroll", "dy": dy]
    }

    static func click(button: String, down: Bool) -> [String: Any] {
        ["t": "click", "btn": button, "down": down]
    }

    static func key(code: String, down: Bool) -> [String: Any] {
        ["t": "key", "code": code, "down": down]
    }

    static func ping() -> [String: Any] {
        ["t": "ping"]
    }

    static func jsonData(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}
