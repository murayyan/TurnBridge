import Foundation
import CoreLocation
import MapKit

/// Destination extracted from a shared map link, a raw coordinate or a plain place name.
struct ParsedTarget {
    let coordinate: CLLocationCoordinate2D?
    let name: String?
    let query: String?
}

/// Handles what Apple Maps and Google Maps actually hand over:
///
/// - `maps.apple.com/place?address=..&coordinate=-6.2,106.8&name=Cafe` (iOS 16+ share)
/// - `maps.apple.com/?q=Cafe&ll=-6.2,106.8`, `?daddr=..`, `?saddr=..`
/// - `google.com/maps/place/Name/@-6.2,106.8,17z`, `?q=lat,lon`, `?ll=..`
/// - `comgooglemaps://?daddr=lat,lon`
/// - `maps.app.goo.gl/xxxx` (short link, resolved over the network)
/// - a bare `lat,lon`, or just a place name
enum TargetParser {
    static func parse(_ raw: String) -> ParsedTarget? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let coordinate = coordinate(from: text) {
            return ParsedTarget(coordinate: coordinate, name: nil, query: nil)
        }

        guard let url = firstURL(in: text) else {
            return ParsedTarget(coordinate: nil, name: text, query: text)
        }
        return parse(url: url, fallbackText: text)
    }

    static func parse(url: URL, fallbackText: String? = nil) -> ParsedTarget? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func value(_ names: [String]) -> String? {
            for name in names {
                if let item = items.first(where: { $0.name.lowercased() == name }),
                   let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        // `coordinate` is the parameter Apple Maps uses when sharing a single place.
        let coordinateText = value(["coordinate", "ll", "sll", "center", "daddr", "destination", "q", "o"])
        let coordinate = coordinateText.flatMap(TargetParser.coordinate(from:)) ?? coordinateFromPath(url)

        // Apple share text is "Place name\nStreet address\nhttps://maps.apple.com/place?..",
        // so the first line beats the generic `address` parameter.
        let fallbackName = fallbackText.flatMap(firstMeaningfulLine)
        let rawName = value(["name"])
            ?? urlName(url)
            ?? fallbackName
            ?? value(["q", "dname", "destination", "address"])

        // `?q=-6.2,106.8` is a coordinate, not a place name.
        let name = rawName.flatMap { TargetParser.coordinate(from: $0) == nil ? $0 : nil }

        if let coordinate {
            return ParsedTarget(coordinate: coordinate, name: name, query: nil)
        }
        if let name {
            return ParsedTarget(coordinate: nil, name: name, query: name)
        }
        if let fallbackName {
            return ParsedTarget(coordinate: nil, name: fallbackName, query: fallbackName)
        }
        return nil
    }

    /// `maps.app.goo.gl/..`, `goo.gl/maps/..`
    static func isShortLink(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host == "goo.gl" || host.hasSuffix(".goo.gl") || host == "g.co"
    }

    static func firstURL(in text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil, url.host != nil { return url }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range),
              let urlRange = Range(match.range, in: text) else { return nil }
        return URL(string: String(text[urlRange]))
    }

    /// "1.23,4.56" / "-6.2, 106.8" / "1.23,4.56,17z"
    static func coordinate(from text: String) -> CLLocationCoordinate2D? {
        let cleaned = text
            .replacingOccurrences(of: "loc:", with: "")
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ",").map(String.init)
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              abs(lat) <= 90,
              abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func firstMeaningfulLine(_ text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().contains("http") { continue }
            return trimmed
        }
        return nil
    }

    /// Google puts the map centre in the path: `/maps/place/Name/@-6.2,106.8,17z`
    private static func coordinateFromPath(_ url: URL) -> CLLocationCoordinate2D? {
        let path = url.path
        guard let at = path.firstIndex(of: "@") else { return nil }
        let tail = path[path.index(after: at)...]
        return coordinate(from: String(tail))
    }

    private static func urlName(_ url: URL) -> String? {
        let components = url.path.split(separator: "/").map(String.init)
        if let index = components.firstIndex(of: "place"), index + 1 < components.count {
            return components[index + 1].replacingOccurrences(of: "+", with: " ")
        }
        if let index = components.firstIndex(of: "search"), index + 1 < components.count {
            return components[index + 1].replacingOccurrences(of: "+", with: " ")
        }
        return nil
    }
}
