import Foundation

/// Minimal, dependency-free RFC-4180-ish CSV parser.
/// Handles quoted fields, embedded commas, escaped quotes (""), and CRLF/CR/LF.
enum CSVParser {

    /// Parse CSV text into an array of `[header: value]` dictionaries.
    /// The first non-empty line is treated as the header row.
    static func parse(_ text: String) -> [[String: String]] {
        let rows = parseRows(text)
        guard let header = rows.first else { return [] }
        let keys = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        var result: [[String: String]] = []
        for row in rows.dropFirst() {
            // Skip fully empty lines.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            var dict: [String: String] = [:]
            for (i, key) in keys.enumerated() where !key.isEmpty {
                let value = i < row.count ? row[i] : ""
                dict[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result.append(dict)
        }
        return result
    }

    /// Parse raw CSV into rows of fields, respecting quotes.
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false

        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r":
                    // Treat CRLF and lone CR as line endings.
                    if i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                case "\n":
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        // Flush trailing field/row.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
