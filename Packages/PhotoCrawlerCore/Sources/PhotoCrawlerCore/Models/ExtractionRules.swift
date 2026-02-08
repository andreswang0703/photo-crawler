import Foundation

/// User-defined category rule for extraction + writing.
public struct ExtractionCategoryRule: Codable, Sendable, Equatable {
    public var name: String
    public var hint: String?
    public var extractionRules: String
    public var writeRule: String

    public init(
        name: String,
        hint: String? = nil,
        extractionRules: String,
        writeRule: String
    ) {
        self.name = name
        self.hint = hint
        self.extractionRules = extractionRules
        self.writeRule = writeRule
    }

    enum CodingKeys: String, CodingKey {
        case name
        case hint
        case extractionRules = "extraction_rules"
        case writeRule = "write_rule"
    }
}

/// Default/fallback rules when no category is configured or matched.
public struct ExtractionDefaultRule: Codable, Sendable, Equatable {
    public var extractionRules: String
    public var writeRule: String

    public init(extractionRules: String, writeRule: String) {
        self.extractionRules = extractionRules
        self.writeRule = writeRule
    }

    enum CodingKeys: String, CodingKey {
        case extractionRules = "extraction_rules"
        case writeRule = "write_rule"
    }
}

/// Where and how to write a note.
public struct WritePlan: Codable, Sendable, Equatable {
    public var mode: WriteMode
    public var path: String
    public var appendTo: String?

    public init(mode: WriteMode, path: String, appendTo: String? = nil) {
        self.mode = mode
        self.path = path
        self.appendTo = appendTo
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case path
        case appendTo = "append_to"
    }
}

public enum WriteMode: String, Codable, Sendable {
    case create
    case append
    case upsert
    case skip

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = WriteMode(rawValue: raw.lowercased()) ?? .create
    }
}
