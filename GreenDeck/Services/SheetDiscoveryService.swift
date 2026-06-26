import Foundation

enum DiscoveryError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case noDecks

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a Google Sheets URL. Paste the link from your browser's address bar."
        case .downloadFailed(let m):
            return "Could not read the spreadsheet: \(m)"
        case .noDecks:
            return "No deck tabs found. Make sure the sheet is shared as 'Anyone with the link can view'."
        }
    }
}

/// Turns a Google Sheets URL into a list of selectable decks (one per visible
/// tab), without OAuth. Tabs are discovered from the spreadsheet's edit-page
/// tab bar; each deck is read later via the public gviz CSV exporter.
struct SheetDiscoveryService {

    /// Extract the spreadsheet ID from any Google Sheets URL form.
    static func spreadsheetID(from url: URL) -> String? {
        let s = url.absoluteString
        guard let range = s.range(of: #"/spreadsheets/d/([A-Za-z0-9_-]+)"#,
                                  options: .regularExpression) else { return nil }
        let match = String(s[range])
        return match.replacingOccurrences(of: "/spreadsheets/d/", with: "")
    }

    /// True when the URL already points at CSV output (paste-through support).
    static func looksLikeCSV(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        return s.contains("out:csv") || s.contains("output=csv") || s.hasSuffix(".csv")
    }

    /// Discover decks for the given URL.
    func discover(from url: URL) async throws -> [Deck] {
        // Direct CSV link → single deck, no discovery needed.
        if Self.looksLikeCSV(url) {
            return [Deck(rawCSVURL: url)]
        }
        guard let id = Self.spreadsheetID(from: url) else {
            // Not a spreadsheet URL; treat as a raw CSV endpoint.
            return [Deck(rawCSVURL: url)]
        }

        let editURL = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/edit")!
        let html = try await fetch(editURL)
        let names = Self.tabNames(in: html)
        let decks = names
            .filter { isDeckTab($0) }
            .map { Deck(spreadsheetID: id, name: $0) }

        guard !decks.isEmpty else { throw DiscoveryError.noDecks }
        return decks
    }

    // MARK: Parsing

    /// Extract ordered tab captions from the edit-page tab bar.
    static func tabNames(in html: String) -> [String] {
        let pattern = #"docs-sheet-tab-caption">([^<]+)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var names: [String] = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { return }
            names.append(decodeEntities(String(html[r])).trimmingCharacters(in: .whitespaces))
        }
        return names
    }

    /// Config/hidden tabs use a leading "." or "_" (e.g. "._config"); skip them.
    private func isDeckTab(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return false }
        return first != "." && first != "_"
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private func fetch(_ url: URL) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DiscoveryError.downloadFailed("HTTP \(http.statusCode)")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw DiscoveryError.downloadFailed("Could not decode page")
            }
            return text
        } catch let e as DiscoveryError {
            throw e
        } catch {
            throw DiscoveryError.downloadFailed(error.localizedDescription)
        }
    }
}
