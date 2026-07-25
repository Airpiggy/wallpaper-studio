import Foundation

/// A single user-customizable property from WE `general.properties`.
struct WEProperty: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case slider, bool, combo, color, textinput, file, directory, unknown
    }

    struct Option: Codable, Equatable {
        let label: String
        let value: JSONValue
    }

    let key: String          // the property's dictionary key (stable id)
    let kind: Kind
    let label: String        // "text" in WE json
    let defaultValue: JSONValue
    let order: Int
    let min: Double?
    let max: Double?
    let step: Double?
    let options: [Option]

    var id: String { key }
}

/// A tolerant model of Wallpaper Engine's `project.json`. Built by mapping a
/// `JSONValue` tree rather than via synthesized `Codable`, because WE files are
/// loosely typed (numbers-as-strings, mixed casing, missing fields). Conforms to
/// `Codable` for our own persistence, where we control the format.
struct WEProject: Codable, Equatable {
    var title: String
    var type: String          // lowercased: "video" / "web" / "scene" / "application" / ""
    var file: String?
    var preview: String?
    var descriptionText: String?
    var tags: [String]
    var properties: [WEProperty]

    /// Parse from raw `project.json` data. Never throws — returns nil only if the
    /// bytes aren't JSON at all.
    static func parse(data: Data) -> WEProject? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let obj = root.objectValue else { return nil }

        let title = obj["title"]?.stringValue ?? "未命名壁纸"
        let type = (obj["type"]?.stringValue ?? "").lowercased()
        let file = obj["file"]?.stringValue
        let preview = obj["preview"]?.stringValue
        let desc = obj["description"]?.stringValue

        var tags: [String] = []
        if let arr = obj["tags"]?.arrayValue {
            tags = arr.compactMap { $0.stringValue }
        }

        var properties: [WEProperty] = []
        if let props = obj["general"]?.objectValue?["properties"]?.objectValue {
            for (key, raw) in props {
                guard let p = raw.objectValue else { continue }
                let kind = WEProperty.Kind(rawValue: (p["type"]?.stringValue ?? "").lowercased()) ?? .unknown
                let label = p["text"]?.stringValue ?? key
                let value = p["value"] ?? .null
                let order = Int(p["order"]?.doubleValue ?? 0)
                let min = p["min"]?.doubleValue
                let max = p["max"]?.doubleValue
                let step = p["step"]?.doubleValue
                var options: [WEProperty.Option] = []
                if let optArr = p["options"]?.arrayValue {
                    for o in optArr {
                        guard let oo = o.objectValue else { continue }
                        let ol = oo["label"]?.stringValue ?? oo["text"]?.stringValue ?? ""
                        let ov = oo["value"] ?? .null
                        options.append(.init(label: ol, value: ov))
                    }
                }
                properties.append(WEProperty(
                    key: key, kind: kind, label: label, defaultValue: value,
                    order: order, min: min, max: max, step: step, options: options
                ))
            }
            properties.sort { $0.order < $1.order }
        }

        return WEProject(
            title: title, type: type, file: file, preview: preview,
            descriptionText: desc, tags: tags, properties: properties
        )
    }
}
