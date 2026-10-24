import Foundation

/// Import/export of customization presets (appearance + custom CSS, optionally scripts).
nonisolated struct CustomizationPreset: Codable, Equatable, Sendable {
    var format = "wisp-preset"
    var version = 1
    var name: String
    var exportedAt: Date
    var appearance: AppearanceSettings
    var customCSS: String
    var scripts: [CustomScript]?
}

nonisolated enum PresetIO {
    enum PresetError: LocalizedError {
        case notAPreset, unsupportedVersion(Int)
        var errorDescription: String? {
            switch self {
            case .notAPreset: "This file is not a Wisp preset."
            case .unsupportedVersion(let v): "Preset version \(v) is newer than this version of Wisp understands."
            }
        }
    }

    nonisolated static func encode(_ preset: CustomizationPreset) throws -> Data {
        try JSONEncoder.pretty.encode(preset)
    }

    nonisolated static func decode(_ data: Data) throws -> CustomizationPreset {
        let preset = try JSONDecoder.standard.decode(CustomizationPreset.self, from: data)
        guard preset.format == "wisp-preset" else { throw PresetError.notAPreset }
        guard preset.version <= 1 else { throw PresetError.unsupportedVersion(preset.version) }
        return preset
    }
}
