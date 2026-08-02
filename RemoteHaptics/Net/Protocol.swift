import Foundation

/// RemoteHaptics サーバーとの WebSocket JSON プロトコル定義。
///
/// 送信メッセージは常に `t` フィールドを含む辞書。
/// - auth:    {"t":"auth","pin":"1234"}          → {"t":"ok"} / {"t":"err"}
/// - move:    {"t":"move","dx":int,"dy":int}     相対カーソル移動
/// - moveto:  {"t":"moveto","x":int,"y":int}     絶対座標へカーソル移動
/// - scroll:  {"t":"scroll","dy":int}            縦スクロール (上=正)
/// - click:   {"t":"click","btn":"left","down":bool}
/// - key:     {"t":"key","code":"KEY_A","down":bool}
/// - stream:  {"t":"stream","on":bool,"w","q"}   画面配信開始/停止 → stream_meta + JPEG バイナリ
/// - exec:    {"t":"exec","cmd":String}          コマンド実行 → {"t":"exec_out","code","out"}
/// - ping:    {"t":"ping"}                        → {"t":"pong"}
enum InputMessage {
    static func auth(pin: String) -> [String: Any] {
        ["t": "auth", "pin": pin]
    }

    static func move(dx: Int, dy: Int) -> [String: Any] {
        ["t": "move", "dx": dx, "dy": dy]
    }

    static func moveto(x: Int, y: Int) -> [String: Any] {
        ["t": "moveto", "x": x, "y": y]
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

    static func stream(on: Bool, w: Int = 1280, q: Int = 60) -> [String: Any] {
        ["t": "stream", "on": on, "w": w, "q": q]
    }

    static func exec(cmd: String) -> [String: Any] {
        ["t": "exec", "cmd": cmd]
    }

    static func ping() -> [String: Any] {
        ["t": "ping"]
    }

    static func jsonData(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}

/// サーバーからの画面情報メッセージ。
/// - w/h: PC 画面全体のサイズ
/// - fw/fh: 送られてくる JPEG フレームのサイズ
struct StreamMeta {
    let screenW: Int
    let screenH: Int
    let frameW: Int
    let frameH: Int

    init?(_ obj: [String: Any]) {
        guard let sw = obj["w"] as? Int, let sh = obj["h"] as? Int,
              let fw = obj["fw"] as? Int, let fh = obj["fh"] as? Int else { return nil }
        screenW = sw
        screenH = sh
        frameW = fw
        frameH = fh
    }
}
