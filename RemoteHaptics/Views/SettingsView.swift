import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    var body: some View {
        NavigationStack {
            Form {
                Section("接続") {
                    LabeledContent("状態", value: stateLabel)
                    if model.connectionState == .connected {
                        LabeledContent("サーバー", value: "\(model.connectedHost):\(model.connectedPort)")
                    }
                    Button("切断", role: .destructive) {
                        model.disconnect()
                    }
                    .disabled(model.connectionState == .disconnected)
                }

                Section("トラックパッド") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("感度")
                            Spacer()
                            Text(String(format: "%.2f", model.sensitivity))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.sensitivity, in: 0.25...3.0, step: 0.05)
                    }
                    Toggle("触覚フィードバック", isOn: $model.hapticsEnabled)
                        .onChange(of: model.hapticsEnabled) { _, value in
                            InputHaptics.shared.isEnabled = value
                        }
                }

                Section("自動化") {
                    Toggle("自動再接続", isOn: $model.autoReconnect)
                    Toggle("サーバーを自動接続", isOn: $model.autoConnect)
                }

                Section("PIN") {
                    SecureField("PIN", text: $model.pin)
                        .keyboardType(.numberPad)
                    Text("サーバーと同じ PIN を設定してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("操作ガイド") {
                    Text("トラックパッド\n・1本指ドラッグ: カーソル移動\n・タップ: 左クリック\n・1本指長押し: 右クリック\n・2本指ドラッグ: スクロール\n・2本指タップ: 右クリック")
                    Text("キーボード\n・キー長押しで連続入力 (PC側がリピート)\n・Shift は押している間だけ有効\n・半/全・変換・無変換・かな・英数で IME 切替")
                }
            }
            .navigationTitle("設定")
        }
    }

    private var stateLabel: String {
        switch model.connectionState {
        case .connected: return "接続中"
        case .connecting: return "接続中…"
        case .disconnected: return "未接続"
        }
    }
}
