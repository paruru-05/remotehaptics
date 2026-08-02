import SwiftUI

struct KeyboardView: View {
    @EnvironmentObject var model: RemoteHapticsModel

    private let rowCount = JISKeyboard.allRows.count
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            GeometryReader { geo in
                let rowHeight = (geo.size.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)
                VStack(spacing: spacing) {
                    ForEach(Array(JISKeyboard.allRows.enumerated()), id: \.offset) { _, row in
                        KeyRowView(row: row, height: rowHeight)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var statusBar: some View {
        HStack {
            Image(systemName: "keyboard")
                .foregroundStyle(.green)
            Text(model.connectedHost)
                .font(.footnote.monospaced())
            Spacer()
            if model.isShiftActive {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct KeyRowView: View {
    let row: [KeyDef]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(row) { def in
                    let unit = (geo.size.width - CGFloat(row.count - 1) * 4) / totalUnits
                    KeyButton(def: def, width: unit * def.width, height: height)
                }
            }
        }
        .frame(height: height)
    }

    private var totalUnits: CGFloat {
        row.reduce(0) { $0 + $1.width }
    }
}

private struct KeyButton: View {
    let def: KeyDef
    let width: CGFloat
    let height: CGFloat

    @EnvironmentObject var model: RemoteHapticsModel
    @State private var pressed = false
    @State private var fired = false

    private var displayLabel: String {
        model.effectiveShift ? (def.shiftedLabel ?? def.label) : def.label
    }

    private var fontSize: CGFloat {
        switch displayLabel.count {
        case 1: return 18
        case 2: return 14
        default: return 11
        }
    }

    private var background: Color {
        if def.isModifier || def.isSpecial {
            return Color(uiColor: .tertiarySystemFill)
        }
        return Color(uiColor: .systemBackground)
    }

    var body: some View {
        Text(displayLabel)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(pressed ? Color.accentColor : Color.primary)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 7).fill(background))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
            )
            .scaleEffect(pressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !fired else { return }
                        fired = true
                        pressed = true
                        model.keyDown(def)
                    }
                    .onEnded { _ in
                        guard fired else { return }
                        fired = false
                        pressed = false
                        model.keyUp(def)
                    }
            )
    }
}
