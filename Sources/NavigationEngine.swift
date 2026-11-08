import Foundation
import CoreLocation
import MapKit
import UserNotifications

enum ManeuverKind: Equatable {
    case straight
    case turnRight
    case turnLeft
    case sharpRight
    case sharpLeft
    case slightRight
    case slightLeft
    case uTurn
    case roundabout(Int)
    case ramp
    case merge
    case arrive
    case other
}

struct Maneuver {
    let coordinate: CLLocationCoordinate2D
    let kind: ManeuverKind
    let street: String?
    let raw: String
    let stepDistance: Double
    let distanceFromStart: Double
    let arriving: Bool
}

final class NavigationEngine: NSObject, ObservableObject {
    @Published var status: String = "Siap"
    @Published var nextInstruction: String = "—"
    @Published var nextDistance: String = ""
    @Published var remainingText: String = ""
    @Published var summary: String = ""
    @Published var isRunning = false
    @Published var authorizationText: String = ""
    /// First 80 characters of whatever was on the pasteboard, shown so the user can see
    /// what TurnBridge actually received when parsing fails.
    @Published var clipboardPreview: String = ""
    /// Set when the clipboard (or a typed link) could not be understood: the UI opens a
    /// manual paste sheet instead of leaving the button dead.
    @Published var needsManualInput = false
    /// 1-based maneuver list of the current route, shown in the app so the user can see the
    /// turn-by-turn directions even before the first notification fires.
    @Published var steps: [String] = []
    /// Last route/search error, kept separate from `status` so it can be shown in red.
    @Published var lastError: String?
    /// Rolling on-screen diagnostics: what was pasted, what was parsed, what MapKit answered.
    @Published var debugLines: [String] = []

    private let manager = CLLocationManager()
    private let center = UNUserNotificationCenter.current()

    private var maneuvers: [Maneuver] = []
    private var alerted: Set<Int> = []
    private var index = 0
    private var lastAlertAt = Date.distantPast
    private var arrived = false
    var transport: MKDirectionsTransportType = .automobile
    private var totalDistance: Double = 0
    private var totalTime: Double = 0
    private var pendingDestination: MKMapItem?
    private var retryStage = 0

    func log(_ line: String) {
        let stamp = Self.clock.string(from: Date())
        debugLines.append("\(stamp) \(line)")
        if debugLines.count > 14 { debugLines.removeFirst(debugLines.count - 14) }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        refreshAuthorization()
    }

    // MARK: - Permissions

    func refreshAuthorization() {
        let status = manager.authorizationStatus
        authorizationText = Self.describe(status)
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "Lokasi: selalu"
        case .authorizedWhenInUse: return "Lokasi: saat dipakai (butuh Selalu)"
        case .denied, .restricted: return "Lokasi ditolak"
        case .notDetermined: return "Lokasi: belum diizinkan"
        @unknown default: return "Lokasi: tidak diketahui"
        }
    }

    // MARK: - Route

    func start(destination: MKMapItem, transport: MKDirectionsTransportType, source: CLLocationCoordinate2D? = nil) {
        stop()
        self.transport = transport
        status = "Menghitung rute…"
        lastError = nil
        if source == nil { retryStage = 0 }

        let target = destination.placemark.coordinate
        log(String(format: "rute ke %@ @ %.5f,%.5f", destination.name ?? "-", target.latitude, target.longitude))

        let request = MKDirections.Request()
        if let source {
            log(String(format: "sumber GPS @ %.5f,%.5f", source.latitude, source.longitude))
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        } else {
            request.source = .forCurrentLocation()
        }
        request.destination = destination
        request.transportType = transport
        request.requestsAlternateRoutes = false

        MKDirections(request: request).calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.fail(error, destination: destination, hadSource: source != nil)
                    return
                }
                guard let route = response?.routes.first else {
                    self.log("MapKit: 0 rute")
                    self.lastError = "Rute tidak ditemukan"
                    self.status = "Rute tidak ditemukan"
                    return
                }
                self.load(route: route, destination: destination)
            }
        }
    }

    /// MKDirections with `.forCurrentLocation()` fails when the phone has no GPS fix yet
    /// (a cold start or a fresh install). Ask for one location, then retry with an explicit
    /// source coordinate instead of leaving the screen stuck at "Rute gagal".
    private func fail(_ error: Error, destination: MKMapItem, hadSource: Bool) {
        let message = error.localizedDescription
        log("rute gagal: \(message)")
        lastError = message
        if !hadSource, retryStage == 0 {
            retryStage = 1
            pendingDestination = destination
            status = "Menunggu GPS, lalu coba lagi…"
            manager.requestLocation()
            return
        }
        if retryStage < 2 {
            retryStage = 2
            retryBySearch(destination, message: message)
            return
        }
        status = "Rute gagal: \(message)"
    }

    /// Last resort: a coordinate that MKDirections cannot route (middle of a building, a
    /// closed road, a pin dropped in water) is searched again through MKLocalSearch, which
    /// snaps it to the nearest routable place.
    private func retryBySearch(_ destination: MKMapItem, message: String) {
        let c = destination.placemark.coordinate
        let query = String(format: "%.5f,%.5f", c.latitude, c.longitude)
        log("cari ulang: \(query)")
        status = "Cari ulang titik tujuan…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let item = response?.mapItems.first else {
                    self.log("cari ulang: 0 hasil")
                    self.lastError = message
                    self.status = "Rute gagal: \(message)"
                    return
                }
                self.log("cari ulang: \(item.name ?? "-")")
                self.start(
                    destination: item,
                    transport: self.transport,
                    source: self.manager.location?.coordinate
                )
            }
        }
    }

    private func load(route: MKRoute, destination: MKMapItem) {
        var built: [Maneuver] = []
        var cumulative: Double = 0

        for step in route.steps {
            defer { cumulative += step.distance }
            guard let point = step.polyline.coordinates.first, !step.instructions.isEmpty else { continue }
            let kind = Self.classify(step.instructions)
            built.append(
                Maneuver(
                    coordinate: point,
                    kind: kind,
                    street: Self.streetName(from: step.instructions),
                    raw: Self.clean(step.instructions),
                    stepDistance: step.distance,
                    distanceFromStart: cumulative,
                    arriving: kind == .arrive
                )
            )
        }

        if built.isEmpty {
            built = [
                Maneuver(
                    coordinate: destination.placemark.coordinate,
                    kind: .arrive,
                    street: destination.name,
                    raw: "Sampai di tujuan",
                    stepDistance: 0,
                    distanceFromStart: 0,
                    arriving: true
                )
            ]
        }

        maneuvers = built
        alerted.removeAll()
        index = 0
        arrived = false
        lastAlertAt = .distantPast
        totalDistance = route.distance
        totalTime = route.expectedTravelTime

        let km = route.distance / 1000
        let minutes = Int((route.expectedTravelTime / 60).rounded())
        summary = String(format: "%.1f km • %d mnt • %d belokan", km, minutes, max(0, built.count - 1))
        status = "Navigasi aktif"
        nextInstruction = headline(for: built[0], distance: 0, includeDistance: false)
        nextDistance = ""
        remainingText = "Sisa \(format(distance: route.distance))"
        steps = built.enumerated().map { offset, maneuver in
            "\(offset + 1). \(stepText(for: maneuver))"
        }
        lastError = nil
        pendingDestination = nil
        log("rute ok: \(built.count) langkah, \(String(format: "%.1f", km)) km")

        isRunning = true
        manager.startUpdatingLocation()
        notify(
            title: "Navigasi dimulai",
            body: "Sisa \(format(distance: route.distance)) lagi sampai tujuan • ±\(minutes) mnt"
        )
    }

    /// One line per route step, e.g. "2. Belok kanan ke Jl. X • 300 m".
    private func stepText(for maneuver: Maneuver) -> String {
        switch maneuver.kind {
        case .arrive:
            let place = maneuver.street.map { " di \($0)" } ?? ""
            return "Tiba\(place)"
        case .straight:
            let street = maneuver.street.map { " ke \($0)" } ?? ""
            return "Lurus sejauh \(format(distance: maneuver.stepDistance))\(street)"
        default:
            let title = headline(for: maneuver, distance: 0, includeDistance: false)
            return maneuver.stepDistance > 0 ? "\(title) • \(format(distance: maneuver.stepDistance))" : title
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
        maneuvers = []
        steps = []
        index = 0
        arrived = false
        remainingText = ""
        pendingDestination = nil
        if status == "Navigasi aktif" { status = "Siap" }
    }

    // MARK: - Wording Formatters

    /// Judul Notifikasi:
    /// - "Belok kanan dalam 80 m" / "Belok kanan ke Jl. Sudirman dalam 80 m"
    /// - "Lurus sejauh 1,2 km"
    /// - "Tiba di tujuan"
    private func headline(for maneuver: Maneuver, distance: Double, includeDistance: Bool = true) -> String {
        switch maneuver.kind {
        case .arrive:
            return "Tiba di tujuan"

        case .straight:
            var text = "Lurus sejauh \(format(distance: maneuver.stepDistance))"
            if let street = maneuver.street { text += " ke \(street)" }
            return text

        case .roundabout(let exit):
            let text = "Bundaran, ambil exit ke-\(exit)" + (maneuver.street.map { " ke \($0)" } ?? "")
            return withDistance(text, distance, includeDistance)

        case .turnRight:
            return withDistance(withStreet("Belok kanan", maneuver.street), distance, includeDistance)
        case .turnLeft:
            return withDistance(withStreet("Belok kiri", maneuver.street), distance, includeDistance)
        case .sharpRight:
            return withDistance(withStreet("Belok tajam kanan", maneuver.street), distance, includeDistance)
        case .sharpLeft:
            return withDistance(withStreet("Belok tajam kiri", maneuver.street), distance, includeDistance)
        case .slightRight:
            return withDistance(withStreet("Agak ke kanan", maneuver.street), distance, includeDistance)
        case .slightLeft:
            return withDistance(withStreet("Agak ke kiri", maneuver.street), distance, includeDistance)
        case .uTurn:
            return withDistance("Putar balik", distance, includeDistance)
        case .ramp:
            return withDistance(withStreet("Ambil jalur", maneuver.street), distance, includeDistance)
        case .merge:
            return withDistance(withStreet("Gabung jalur", maneuver.street), distance, includeDistance)
        case .other:
            let base = maneuver.raw.isEmpty ? "Lanjutkan" : maneuver.raw
            return withDistance(base, distance, includeDistance)
        }
    }

    private func withStreet(_ base: String, _ street: String?) -> String {
        guard let street, !street.isEmpty else { return base }
        return "\(base) ke \(street)"
    }

    private func withDistance(_ text: String, _ distance: Double, _ include: Bool) -> String {
        guard include, distance > 0 else { return text }
        return "\(text) dalam \(format(distance: distance))"
    }

    /// Deskripsi Notifikasi:
    /// Memberikan informasi sisa jarak dan perkiraan menit sampai tujuan
    /// Contoh: "Sisa 3,4 km lagi sampai tujuan • ±8 mnt"
    private func detail(for maneuver: Maneuver, distance: Double) -> String {
        let remaining = max(0, totalDistance - maneuver.distanceFromStart + distance)
        var text = "Sisa \(format(distance: remaining)) lagi sampai tujuan"
        if totalDistance > 0, totalTime > 0 {
            let minutes = Int((totalTime * remaining / totalDistance / 60).rounded())
            if minutes > 0 { text += " • ±\(minutes) mnt" }
        }
        return text
    }

    // MARK: - Notifications

    func testNotification() {
        notify(
            title: "Belok kanan ke Jl. Sudirman dalam 80 m",
            body: "Sisa 3,4 km lagi sampai tujuan • ±8 mnt",
            after: 5
        )
    }

    private func notify(title: String, body: String, after: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = after > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false) : nil
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
    }

    // MARK: - Parsing

    static func classify(_ instruction: String) -> ManeuverKind {
        let text = instruction.lowercased()

        if text.contains("arrive") || text.contains("tiba") || text.contains("sampai di tujuan") {
            return .arrive
        }
        if text.contains("roundabout") || text.contains("bundaran") {
            return .roundabout(roundaboutExit(text))
        }
        if text.contains("u-turn") || text.contains("uturn") || text.contains("putar balik") {
            return .uTurn
        }
        if text.contains("sharp right") || text.contains("tajam kanan") {
            return .sharpRight
        }
        if text.contains("sharp left") || text.contains("tajam kiri") {
            return .sharpLeft
        }
        if text.contains("slight right") || text.contains("keep right") || text.contains("bear right") || text.contains("agak ke kanan") {
            return .slightRight
        }
        if text.contains("slight left") || text.contains("keep left") || text.contains("bear left") || text.contains("agak ke kiri") {
            return .slightLeft
        }
        if text.contains("turn right") || text.contains("belok kanan") {
            return .turnRight
        }
        if text.contains("turn left") || text.contains("belok kiri") {
            return .turnLeft
        }
        if text.contains("take the ramp") || text.contains("exit") || text.contains("ambil jalur") {
            return .ramp
        }
        if text.contains("merge") || text.contains("gabung") {
            return .merge
        }
        if text.contains("head") || text.contains("continue") || text.contains("go straight")
            || text.contains("lurus") || text.contains("terus") || text.contains("lanjut") {
            return .straight
        }
        return .other
    }

    private static func roundaboutExit(_ text: String) -> Int {
        if let marker = text.range(of: "exit") ?? text.range(of: "keluar") {
            let before = text[..<marker.lowerBound].suffix(12)
            if let num = before.compactMap({ $0.wholeNumberValue }).last { return num }
            let after = text[marker.upperBound...].prefix(12)
            if let num = after.compactMap({ $0.wholeNumberValue }).first { return num }
        }
        return 1
    }

    static func streetName(from instruction: String) -> String? {
        let separators = [" onto ", " ke ", " menuju ", " toward ", " to ", " on ", " at ", " di "]
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in separators {
            guard let range = trimmed.range(of: separator, options: .caseInsensitive) else { continue }
            let suffix = trimmed[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
            let lower = suffix.lowercased()
            if lower.hasPrefix("the right") || lower.hasPrefix("the left") || lower.hasPrefix("kanan") || lower.hasPrefix("kiri") {
                continue
            }
            if !suffix.isEmpty { return suffix }
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func format(distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000).replacingOccurrences(of: ".", with: ",")
        }
        let rounded = max(10, Int((distance / 10).rounded()) * 10)
        return "\(rounded) m"
    }

    private var alertRadius: Double {
        switch transport {
        case .walking: return 45
        case .transit: return 90
        default: return 170
        }
    }
}

// MARK: - Location

extension NavigationEngine: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationText = Self.describe(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let pending = pendingDestination {
            log(String(format: "GPS fix: %.5f,%.5f, ulang hitung", location.coordinate.latitude, location.coordinate.longitude))
            pendingDestination = nil
            start(destination: pending, transport: transport, source: location.coordinate)
            return
        }

        guard isRunning, !arrived, index < maneuvers.count else { return }

        func target(_ i: Int) -> CLLocation {
            let c = maneuvers[i].coordinate
            return CLLocation(latitude: c.latitude, longitude: c.longitude)
        }

        var guardCount = 0
        while index + 1 < maneuvers.count, guardCount < maneuvers.count {
            if location.distance(from: target(index + 1)) < location.distance(from: target(index)) {
                index += 1
                guardCount += 1
            } else {
                break
            }
        }

        let distance = location.distance(from: target(index))
        let maneuver = maneuvers[index]
        nextDistance = format(distance: distance)
        nextInstruction = headline(for: maneuver, distance: distance, includeDistance: false)

        let remaining = max(0, totalDistance - maneuver.distanceFromStart + distance)
        remainingText = "Sisa \(format(distance: remaining)) lagi sampai tujuan"

        let isArrival = maneuver.arriving || index == maneuvers.count - 1

        if distance <= (isArrival ? 120 : alertRadius), !alerted.contains(index), Date().timeIntervalSince(lastAlertAt) > 8 {
            alerted.insert(index)
            lastAlertAt = Date()

            if isArrival {
                notify(
                    title: "Tiba di tujuan",
                    body: maneuver.street ?? "Selamat sampai di lokasi tujuan"
                )
                arrived = true
                status = "Sampai di tujuan"
                stop()
            } else {
                notify(
                    title: headline(for: maneuver, distance: distance),
                    body: detail(for: maneuver, distance: distance)
                )
                index += 1
                if index < maneuvers.count {
                    nextInstruction = headline(for: maneuvers[index], distance: distance, includeDistance: false)
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log("gps: \(error.localizedDescription)")
        if pendingDestination != nil {
            pendingDestination = nil
            lastError = "GPS tidak tersedia: \(error.localizedDescription)"
        }
        status = "GPS error: \(error.localizedDescription)"
    }
}
