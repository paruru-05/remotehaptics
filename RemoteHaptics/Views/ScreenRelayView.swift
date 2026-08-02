import SwiftUI

/// PC 画面の中継 (表示のみ) タブ。操作は行わない。
struct ScreenRelayView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            ZStack {
                Color.black
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = model.screenImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isStreaming {
            VStack(spacing: 12) {
                ProgressView()
                Text("画面を受信中…")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "display")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("PC 画面の中継を開始します")
                    .foregroundStyle(.secondary)
                Button {
                    model.startStream()
                } label: {
                    Label("中継を開始", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    private var statusBar: some View {
        HStack {
            Image(systemName: "display")
                .foregroundStyle(.green)
            Text(model.connectedHost)
                .font(.footnote.monospaced())
            Spacer()
            if model.isStreaming {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("配信中")
                        .font(.caption)
                }
            } else {
                Text("停止中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                if model.isStreaming {
                    model.stopStream()
                } else {
                    model.startStream()
                }
            } label: {
                Image(systemName: model.isStreaming ? "stop.circle" : "play.circle")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
