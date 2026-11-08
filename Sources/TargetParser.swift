import Foundation
import CoreLocation
import MapKit

/// Destination extracted from a shared map link, a raw coordinate or a plain place name.
struct ParsedTarget {
    let coordinate: CLLocationCoordinate2D?
    let name: String?
    let query: String?
}

/// Accepts what Apple Maps / Google Maps actually put on the clipboard or in a share link:
/// `maps.apple.com/?q=..&ll=..&daddr=..`, `google.com/maps/place/Name/@lat,lon,17z`,
/// `comgooglemaps://?daddr=lat,lon`, a bare `lat,lon`, or just a place name.
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

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        func value(_ names: [String]) -> String? {
            for name in names {
                if let item = items.first(where: { $0.name.lowercased() == name }),
                   let value = item.value,
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        let rawLabel = value(["name", "q", "dname", "destination"])
            ?? urlName(url)
            ?? value(["address"])
        // `?q=-6.2,106.8` is a coordinate, not a place name.
        let label = rawLabel.flatMap { TargetParser.coordinate(from: $0) == nil ? $0 : nil }

        // daddr / destination are either "lat,lon" or a full address string.
        var coordinate: CLLocationCoordinate2D?
        if let daddr = value(["daddr", "destination"]), let parsed = TargetParser.coordinate(from: daddr) {
            coordinate = parsed
        }
        if coordinate == nil, let ll = value(["ll", "sll", "center", "q"]).flatMap(TargetParser.coordinate(from:)) {
            coordinate = ll
        }
        if coordinate == nil, let path = TargetParser.coordinateFromPath(url) {
            coordinate = path
        }

        if coordinate == nil, let query = label, !query.isEmpty {
            return ParsedTarget(coordinate: nil, name: query, query: query)
        }
        guard coordinate != nil || label != nil else { return nil }
        return ParsedTarget(coordinate: coordinate, name: label, query: nil)
    }

    private static func firstURL(in text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
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
