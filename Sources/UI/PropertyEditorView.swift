import SwiftUI

/// Renders WE `general.properties` as native controls, writing back into a
/// values dictionary keyed by property key.
struct PropertyEditorView: View {
    let properties: [WEProperty]
    @Binding var values: [String: JSONValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(properties) { prop in
                row(for: prop)
            }
        }
    }

    @ViewBuilder
    private func row(for prop: WEProperty) -> some View {
        switch prop.kind {
        case .slider:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(prop.label)
                    Spacer()
                    Text(String(format: "%.2f", doubleValue(prop)))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { doubleValue(prop) },
                        set: { values[prop.key] = .number($0) }
                    ),
                    in: (prop.min ?? 0)...(prop.max ?? 1),
                    step: prop.step ?? 0.01
                )
            }

        case .bool:
            Toggle(prop.label, isOn: Binding(
                get: { values[prop.key]?.boolValue ?? prop.defaultValue.boolValue ?? false },
                set: { values[prop.key] = .bool($0) }
            ))

        case .combo:
            HStack {
                Text(prop.label)
                Spacer()
                Picker("", selection: Binding(
                    get: { stringValue(prop) },
                    set: { values[prop.key] = .string($0) }
                )) {
                    ForEach(prop.options, id: \.label) { opt in
                        Text(opt.label).tag(opt.value.stringValue ?? "")
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

        case .color:
            ColorPicker(prop.label, selection: Binding(
                get: { color(from: stringValue(prop)) },
                set: { values[prop.key] = .string(weColorString(from: $0)) }
            ))

        case .textinput:
            HStack {
                Text(prop.label)
                TextField("", text: Binding(
                    get: { stringValue(prop) },
                    set: { values[prop.key] = .string($0) }
                ))
                .textFieldStyle(.roundedBorder)
            }

        case .file, .directory, .unknown:
            HStack {
                Text(prop.label)
                Spacer()
                Text("（此类型暂不支持编辑）")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Value helpers

    private func doubleValue(_ prop: WEProperty) -> Double {
        values[prop.key]?.doubleValue ?? prop.defaultValue.doubleValue ?? prop.min ?? 0
    }

    private func stringValue(_ prop: WEProperty) -> String {
        values[prop.key]?.stringValue ?? prop.defaultValue.stringValue ?? ""
    }

    /// WE stores colors as "r g b" normalized strings.
    private func color(from we: String) -> Color {
        let parts = we.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 3 else { return .white }
        return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2], opacity: 1)
    }

    private func weColorString(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return "\(ns.redComponent) \(ns.greenComponent) \(ns.blueComponent)"
    }
}
