import Foundation

/// Hands a capture to the public benchmark through a pre-filled GitHub issue form.
struct Submission {
    static let maxURLLength = 7500
    private static let newIssueEndpoint = "https://github.com/Umer9538/pocketroofline/issues/new"

    /// The URL to open, and whether the capture fit inside it. When it doesn't, the
    /// user pastes it from the clipboard instead.
    let url: URL
    let embedsCapture: Bool
    let compactJSON: String

    init(capture: Capture) throws {
        compactJSON = String(decoding: try capture.compactJSON(), as: UTF8.self)

        var query = [
            ("template", "device-capture.yml"),
            ("title", "\(capture.device.model) capture"),
        ]
        let withoutCapture = Self.issueURL(query)
        query.append(("capture", compactJSON))
        let withCapture = Self.issueURL(query)

        embedsCapture = withCapture.absoluteString.count < Self.maxURLLength
        url = embedsCapture ? withCapture : withoutCapture
    }

    /// `URLComponents` leaves `+` unencoded, which form handlers read as a space, so values are
    /// encoded by hand against RFC 3986's unreserved set.
    private static func issueURL(_ items: [(String, String)]) -> URL {
        let query = items
            .map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        return URL(string: "\(newIssueEndpoint)?\(query)")!
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
