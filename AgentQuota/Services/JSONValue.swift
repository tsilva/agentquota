import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum DecodedJSONRPCLine: Equatable, Sendable {
    case text(String)
    case invalidUTF8
}

struct JSONRPCLineDecoder: Sendable {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [DecodedJSONRPCLine] {
        buffer.append(data)
        var lines: [DecodedJSONRPCLine] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)

            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }

            guard !lineData.isEmpty else {
                continue
            }

            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(.text(line))
            } else {
                lines.append(.invalidUTF8)
            }
        }

        return lines
    }

    mutating func finish() -> [DecodedJSONRPCLine] {
        guard !buffer.isEmpty else {
            return []
        }
        defer { buffer.removeAll(keepingCapacity: false) }
        if let line = String(data: buffer, encoding: .utf8) {
            return [.text(line)]
        }
        return [.invalidUTF8]
    }
}
