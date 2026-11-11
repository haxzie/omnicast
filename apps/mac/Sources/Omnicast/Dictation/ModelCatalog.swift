import Foundation

/// A downloadable speech model. The catalog ships with the app and can be
/// refreshed from the Omnicast API so new models appear without an update.
struct SpeechModel: Identifiable, Codable, Hashable {
    enum Quality: String, Codable {
        case draft, balanced, accurate
    }

    let id: String
    let name: String
    let description: String
    let bytes: Int64
    let quality: Quality
    /// "en" or "multilingual".
    let languages: String
    let realtimeFactor: Double
    let url: URL
    var sha256: String?
    var recommended: Bool?

    var filename: String { "ggml-\(id).bin" }
    var isMultilingual: Bool { languages != "en" }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum ModelCatalog {
    private static let huggingFace = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    /// Kept in sync with `packages/shared/src/models.ts`.
    static let bundled: [SpeechModel] = [
        SpeechModel(
            id: "tiny.en-q5_1", name: "Tiny (English)",
            description: "Fastest option. Great for short commands on battery.",
            bytes: 32_600_000, quality: .draft, languages: "en", realtimeFactor: 32,
            url: URL(string: "\(huggingFace)/ggml-tiny.en-q5_1.bin")!),
        SpeechModel(
            id: "base.en-q5_1", name: "Base (English)",
            description: "Good accuracy for everyday dictation with a tiny footprint.",
            bytes: 59_700_000, quality: .balanced, languages: "en", realtimeFactor: 20,
            url: URL(string: "\(huggingFace)/ggml-base.en-q5_1.bin")!, recommended: true),
        SpeechModel(
            id: "small.en-q5_1", name: "Small (English)",
            description: "Noticeably better punctuation and proper nouns.",
            bytes: 181_000_000, quality: .accurate, languages: "en", realtimeFactor: 9,
            url: URL(string: "\(huggingFace)/ggml-small.en-q5_1.bin")!),
        SpeechModel(
            id: "medium-q5_0", name: "Medium (multilingual)",
            description: "99 languages, highest accuracy. Needs ~2 GB of RAM.",
            bytes: 539_000_000, quality: .accurate, languages: "multilingual", realtimeFactor: 3,
            url: URL(string: "\(huggingFace)/ggml-medium-q5_0.bin")!),
        SpeechModel(
            id: "large-v3-turbo-q5_0", name: "Large v3 Turbo",
            description: "Near large-v3 quality at a fraction of the cost.",
            bytes: 574_000_000, quality: .accurate, languages: "multilingual", realtimeFactor: 6,
            url: URL(string: "\(huggingFace)/ggml-large-v3-turbo-q5_0.bin")!),
    ]
}
