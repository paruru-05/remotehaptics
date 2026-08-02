import SwiftUI

/// PC 上でコマンドを実行し、結果を受け取る画面。
struct CommandView: View {
    @EnvironmentObject var model: RemoteHapticsModel
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("コマンド (例: ls)", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { run() }
                    Button("実行") {
                        run()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)

                List {
                    if model.commandHistory.isEmpty {
                        Text("まだ実行履歴はありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(model.commandHistory) { entry in
                            CommandEntryView(entry: entry)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("コマンド")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去") {
                        model.clearCommandHistory()
                    }
                    .disabled(model.commandHistory.isEmpty)
                }
            }
        }
    }

    private func run() {
        let cmd = input
        input = ""
        model.runCommand(cmd)
    }
}

private struct CommandEntryView: View {
    let entry: CommandEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("$ \(entry.cmd)")
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("exit \(entry.code)")
                    .font(.caption.monospaced())
                    .foregroundStyle(entry.code == 0 ? Color.green : Color.red)
            }
            if !entry.output.isEmpty {
                Text(entry.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
