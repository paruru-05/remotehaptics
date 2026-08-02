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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("ドラッグ開始までの静止時間")
                            Spacer()
                            Text(String(format: "%.1f 秒", model.dragDelay))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.dragDelay, in: 0.2...1.2, step: 0.1)
                    }
                    Toggle("触覚フィードバック", isOn: $model.hapticsEnabled)
                        .onChange(of: model.hapticsEnabled) { _, value in
                            InputHaptics.shared.isEnabled = value
                        }
                }

                Section("画面中継") {
                    Picker("画質", selection: $model.streamQualityIndex) {
                        ForEach(RemoteHapticsModel.qualityPresets.indices, id: \.self) { i in
                            Text(RemoteHapticsModel.qualityPresets[i].label).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.streamQualityIndex) { _, _ in
                        model.applyStreamQualityChange()
                    }
                    Text("「絶対」モードで PC 画面を配信します。高画質ほどフレームレートが下がります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("トラックパッド (相対)\n・1本指ドラッグ: カーソル移動\n・1本指静止 0.5 秒: ドラッグ開始\n・タップ: 左クリック\n・2本指ドラッグ: スクロール\n・2本指タップ: 右クリック")
                    Text("トラックパッド (絶対)\n・PC 画面が背景に表示されます\n・指を置いた位置にカーソルが移動\n・静止 0.5 秒でドラッグ開始")
                    Text("キーボード\n・キー長押しで連続入力 (PC側がリピート)\n・Shift は押している間だけ有効\n・半/全・変換・無変換・かな・英数で IME 切替")
                    Text("コマンド\n・PC で任意のコマンドを実行し結果を表示\n・実行は接続した PC 上で行われます")
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
