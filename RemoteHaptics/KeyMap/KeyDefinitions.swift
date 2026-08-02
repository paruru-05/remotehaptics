import CoreGraphics
import Foundation

/// 仮想キーボードのキー定義。
/// `code` はサーバー側 evdev のコード名 (例: "KEY_A")。サーバーが `e.keys` で引く。
struct KeyDef: Identifiable, Hashable {
    let id: String
    let label: String
    let shiftedLabel: String?
    let code: String
    var width: CGFloat = 1.0
    var isModifier: Bool = false
    var isSpecial: Bool = false

    init(id: String, label: String, shiftedLabel: String? = nil, code: String,
         width: CGFloat = 1.0, isModifier: Bool = false, isSpecial: Bool = false) {
        self.id = id
        self.label = label
        self.shiftedLabel = shiftedLabel
        self.code = code
        self.width = width
        self.isModifier = isModifier
        self.isSpecial = isSpecial
    }

    static func char(_ id: String, _ label: String, _ shifted: String?, _ code: String) -> KeyDef {
        KeyDef(id: id, label: label, shiftedLabel: shifted, code: code)
    }

    static let shift = KeyDef(id: "shiftL", label: "Shift", code: "KEY_LEFTSHIFT", width: 1.6, isModifier: true)
    static let ctrlL = KeyDef(id: "ctrlL", label: "Ctrl", code: "KEY_LEFTCTRL", isModifier: true)
    static let ctrlR = KeyDef(id: "ctrlR", label: "Ctrl", code: "KEY_RIGHTCTRL", isModifier: true)
    static let altL = KeyDef(id: "altL", label: "Alt", code: "KEY_LEFTALT", isModifier: true)
    static let altR = KeyDef(id: "altR", label: "Alt", code: "KEY_RIGHTALT", isModifier: true)
    static let winL = KeyDef(id: "winL", label: "Win", code: "KEY_LEFTMETA", isModifier: true)
}

/// JIS かななし配列。キーコードは対象 PC (jp レイアウト) で実測検証済み。
enum JISKeyboard {
    // 1 段目: 半角/全角 | 数字 | 記号 | Backspace
    static let topRow: [KeyDef] = [
        KeyDef(id: "z_h", label: "半/全", code: "KEY_GRAVE", width: 1.6, isSpecial: true),
        KeyDef.char("n1", "1", "!", "KEY_1"),
        KeyDef.char("n2", "2", "\"", "KEY_2"),
        KeyDef.char("n3", "3", "#", "KEY_3"),
        KeyDef.char("n4", "4", "$", "KEY_4"),
        KeyDef.char("n5", "5", "%", "KEY_5"),
        KeyDef.char("n6", "6", "&", "KEY_6"),
        KeyDef.char("n7", "7", "'", "KEY_7"),
        KeyDef.char("n8", "8", "(", "KEY_8"),
        KeyDef.char("n9", "9", ")", "KEY_9"),
        KeyDef.char("n0", "0", "~", "KEY_0"),
        KeyDef.char("minus", "-", "=", "KEY_MINUS"),
        KeyDef.char("circ", "^", "~", "KEY_EQUAL"),
        KeyDef(id: "yen", label: "¥", shiftedLabel: "|", code: "KEY_YEN", width: 1.3),
        KeyDef(id: "backspace", label: "⌫", code: "KEY_BACKSPACE", width: 1.7)
    ]

    // 2 段目: Tab | Q..P | @ | [ | Enter
    static let secondRow: [KeyDef] = [
        KeyDef(id: "tab", label: "Tab", code: "KEY_TAB", width: 1.4),
        KeyDef.char("q", "Q", "Q", "KEY_Q"),
        KeyDef.char("w", "W", "W", "KEY_W"),
        KeyDef.char("e", "E", "E", "KEY_E"),
        KeyDef.char("r", "R", "R", "KEY_R"),
        KeyDef.char("t", "T", "T", "KEY_T"),
        KeyDef.char("y", "Y", "Y", "KEY_Y"),
        KeyDef.char("u", "U", "U", "KEY_U"),
        KeyDef.char("i", "I", "I", "KEY_I"),
        KeyDef.char("o", "O", "O", "KEY_O"),
        KeyDef.char("p", "P", "P", "KEY_P"),
        KeyDef.char("at", "@", "`", "KEY_LEFTBRACE"),
        KeyDef.char("bracketL", "[", "{", "KEY_RIGHTBRACE"),
        KeyDef(id: "enter", label: "Enter", code: "KEY_ENTER", width: 1.5, isSpecial: true)
    ]

    // 3 段目: 英数 | A..L | ; | : | ]
    static let thirdRow: [KeyDef] = [
        KeyDef(id: "eisu", label: "英数", code: "KEY_CAPSLOCK", width: 1.4, isSpecial: true),
        KeyDef.char("a", "A", "A", "KEY_A"),
        KeyDef.char("s", "S", "S", "KEY_S"),
        KeyDef.char("d", "D", "D", "KEY_D"),
        KeyDef.char("f", "F", "F", "KEY_F"),
        KeyDef.char("g", "G", "G", "KEY_G"),
        KeyDef.char("h", "H", "H", "KEY_H"),
        KeyDef.char("j", "J", "J", "KEY_J"),
        KeyDef.char("k", "K", "K", "KEY_K"),
        KeyDef.char("l", "L", "L", "KEY_L"),
        KeyDef.char("semi", ";", "+", "KEY_SEMICOLON"),
        KeyDef.char("colon", ":", "*", "KEY_APOSTROPHE"),
        KeyDef.char("bracketR", "]", "}", "KEY_BACKSLASH")
    ]

    // 4 段目: Shift | Z..M | , | . | / | \ | Shift
    static let fourthRow: [KeyDef] = [
        KeyDef.shift,
        KeyDef.char("z", "Z", "Z", "KEY_Z"),
        KeyDef.char("x", "X", "X", "KEY_X"),
        KeyDef.char("c", "C", "C", "KEY_C"),
        KeyDef.char("v", "V", "V", "KEY_V"),
        KeyDef.char("b", "B", "B", "KEY_B"),
        KeyDef.char("n", "N", "N", "KEY_N"),
        KeyDef.char("m", "M", "M", "KEY_M"),
        KeyDef.char("comma", ",", "<", "KEY_COMMA"),
        KeyDef.char("dot", ".", ">", "KEY_DOT"),
        KeyDef.char("slash", "/", "?", "KEY_SLASH"),
        KeyDef.char("ro", "\\", "_", "KEY_RO"),
        KeyDef(id: "shiftR", label: "Shift", code: "KEY_RIGHTSHIFT", width: 1.6, isModifier: true)
    ]

    // 5 段目: Ctrl | Win | Alt | 無変換 | Space | 変換 | かな | Alt | Ctrl
    static let bottomRow: [KeyDef] = [
        KeyDef.ctrlL,
        KeyDef.winL,
        KeyDef.altL,
        KeyDef(id: "muhenkan", label: "無変", code: "KEY_MUHENKAN", isSpecial: true),
        KeyDef(id: "space", label: "Space", code: "KEY_SPACE", width: 6.0),
        KeyDef(id: "henkan", label: "変換", code: "KEY_HENKAN", isSpecial: true),
        KeyDef(id: "kana", label: "かな", code: "KEY_KATAKANAHIRAGANA", isSpecial: true),
        KeyDef.altR,
        KeyDef.ctrlR
    ]

    // ファンクション段: Esc | F1..F12 | 矢印
    static let functionRow: [KeyDef] = {
        var keys: [KeyDef] = [
            KeyDef(id: "esc", label: "Esc", code: "KEY_ESC", width: 0.9)
        ]
        for i in 1...12 {
            keys.append(KeyDef(id: "f\(i)", label: "F\(i)", code: "KEY_F\(i)", width: 0.75))
        }
        keys.append(contentsOf: [
            KeyDef(id: "left", label: "◀", code: "KEY_LEFT", width: 0.7),
            KeyDef(id: "up", label: "▲", code: "KEY_UP", width: 0.7),
            KeyDef(id: "down", label: "▼", code: "KEY_DOWN", width: 0.7),
            KeyDef(id: "right", label: "▶", code: "KEY_RIGHT", width: 0.7)
        ])
        return keys
    }()

    static let allRows: [[KeyDef]] = [
        functionRow, topRow, secondRow, thirdRow, fourthRow, bottomRow
    ]
}
