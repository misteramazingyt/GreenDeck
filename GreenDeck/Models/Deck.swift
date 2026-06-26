import Foundation

/// A deck corresponds to a single tab (worksheet) within a Google Spreadsheet.
/// Each deck has its own set of background images.
struct Deck: Identifiable, Codable, Hashable {
    /// Stable id: "{spreadsheetID}:{tab name}".
    var id: String
    var spreadsheetID: String
    var name: String
    /// Optional grid id; present when discovered from a real spreadsheet tab.
    var gid: String?
    /// Set when the user pasted a direct CSV URL instead of a spreadsheet link.
    var rawCSVURL: URL?

    init(spreadsheetID: String, name: String, gid: String? = nil) {
        self.id = "\(spreadsheetID):\(name)"
        self.spreadsheetID = spreadsheetID
        self.name = name
        self.gid = gid
        self.rawCSVURL = nil
    }

    /// A standalone deck backed directly by a CSV URL (no tab discovery).
    init(rawCSVURL: URL, name: String = "Sheet") {
        self.id = "raw:\(rawCSVURL.absoluteString)"
        self.spreadsheetID = ""
        self.name = name
        self.gid = nil
        self.rawCSVURL = rawCSVURL
    }

    /// CSV endpoint for this deck (gviz exporter for tabs, or the raw URL).
    var csvURL: URL {
        if let rawCSVURL { return rawCSVURL }
        var comps = URLComponents(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/gviz/tq")!
        comps.queryItems = [
            URLQueryItem(name: "tqx", value: "out:csv"),
            URLQueryItem(name: "sheet", value: name)
        ]
        return comps.url!
    }
}
