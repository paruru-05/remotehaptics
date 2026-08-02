import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var model: RemoteHapticsModel
    @State private var manualHost = ""
    @State private var showManual = false
    @State private var isInitialized = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    pinField
                    if showManual {
                        manualField
                    }
                    serverList
                    if model.discoveredServers.isEmpty {
                        scanningLabel
                    }
                    if !model.lastMessage.isEmpty {
                        statusLabel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("RemoteHaptics")
                .font(.title.bold())
            Text("iPhone をトラックパッド＆キーボードとして使う")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.bottom, 24)
    }

    private var pinField: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            SecureField("PIN", text: $model.pin)
                .keyboardType(.numberPad)
                .textContentType(.password)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var manualField: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                TextField("ホスト (例: 192.168.1.14)", text: $manualHost)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))

            Button {
                model.connect(host: manualHost)
            } label: {
                Label("手動接続", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
    }

    private var serverList: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation { showManual.toggle() }
            } label: {
                HStack {
                    Image(systemName: showManual ? "chevron.down.circle" : "chevron.up.circle")
                    Text(showManual ? "自動検出を表示" : "自動検出されたサーバー")
                    Spacer()
                    Text("\(model.discoveredServers.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }

            if !showManual {
                ForEach(model.discoveredServers) { server in
                    Button {
                        model.connect(to: server)
                    } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.headline)
                                Text(server.display)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.connectionState == .connecting {
                                ProgressView()
                            } else {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scanningLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("サーバーを検索中…")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var statusLabel: some View {
        Text(model.lastMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
