import Foundation

struct HabitLog: Codable, Identifiable {
    var id: UUID = UUID()
    var user_id: UUID?
    var habit_type: String
    var value: Double
    var unit: String
    var logged_at: String // ISO8601 string
    var metadata: String?
}

// MARK: - Safe Decodable Helpers for Remote Aggregations

public struct FlexibleDouble: Decodable {
    public let value: Double
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let i = try? container.decode(Int.self) {
            self.value = Double(i)
        } else if let s = try? container.decode(String.self), let d = Double(s) {
            self.value = d
        } else {
            self.value = 0.0
        }
    }
}

public enum AnyCodableScalar: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else {
            self = .string("")
        }
    }
    
    public var asString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        }
    }
}

public struct HabitLogMetadataHelper: Decodable {
    public let rawString: String
    
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self.rawString = ""
                return
            }
            if let str = try? container.decode(String.self) {
                self.rawString = str
                return
            }
            if let dict = try? container.decode([String: AnyCodableScalar].self) {
                self.rawString = dict.map { "\($0.key):\($0.value.asString)" }.joined(separator: ",")
                return
            }
        }
        self.rawString = ""
    }
    
    public func contains(_ substring: String) -> Bool {
        rawString.localizedCaseInsensitiveContains(substring)
    }
}

public enum HabitDateParser {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private static let posixWithMicros: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        return f
    }()
    
    private static let posixWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return f
    }()

    private static let posixStandard: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return f
    }()
    
    private static let posixSpace: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ssZZZZZ"
        return f
    }()

    private static let posixSpaceNoTz: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func parse(_ raw: String) -> Date? {
        if let d = isoFractional.date(from: raw) { return d }
        if let d = isoStandard.date(from: raw) { return d }
        
        let tString = raw.replacingOccurrences(of: " ", with: "T")
        if let d = isoFractional.date(from: tString) { return d }
        if let d = isoStandard.date(from: tString) { return d }
        
        if let d = posixWithMicros.date(from: tString) { return d }
        if let d = posixWithMillis.date(from: tString) { return d }
        if let d = posixStandard.date(from: tString) { return d }
        if let d = posixSpace.date(from: raw) { return d }
        if let d = posixSpaceNoTz.date(from: raw) { return d }

        let afterDate = tString.count > 10 ? String(tString.suffix(tString.count - 10)) : tString
        if !afterDate.contains("Z") && !afterDate.contains("+") && !afterDate.contains("-") {
            let zString = tString + "Z"
            if let d = isoFractional.date(from: zString) ?? isoStandard.date(from: zString) {
                return d
            }
        }
        
        if #available(watchOS 8.0, *) {
            if let d = try? Date(tString, strategy: .iso8601) { return d }
        }
        
        return nil
    }
}
