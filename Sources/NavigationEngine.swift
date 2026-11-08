import Foundation
import CoreLocation
import MapKit
import UserNotifications

/// One navigation step: the point where the maneuver happens and what to do there.
struct Maneuver {
    let coordinate: CLLocationCoordinate2D
    let instruction: String
    let distanceFromStart: Double
    let arriving: Bool
}

/// Drives route calculation, background location updates and the turn notifications the
/// phone mirrors to the watch. Not an @MainActor type: CoreLocation calls the delegate on
/// the main queue, and the published values are updated there explicitly.
final class NavigationEngine: NSObject, ObservableObject {
    @Published var status: String = "Siap"
    @Published var nextInstruction: String = "—"
    @Published var nextDistance: String = ""
    @Published var summary: String = ""
    @Published var isRunning = false
    @Published var authorizationText: String = ""

    private let manager = CLLocationManager()
    private let center = UNUserNotificationCenter.current()

    private var maneuvers: [Maneuver] = []
    private var alerted: Set<Int> = []
    private var index = 0
    private var lastAlertAt = Date.distantPast
    private var arrived = false
    private var transport: MKDirectionsTransportType = .automobile

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
            // Background navigation needs "Always"; iOS answers with a provisional grant.
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

    func start(destination: MKMapItem, transport: MKDirectionsTransportType) {
        stop()
        self.transport = transport
        status = "Menghitung rute…"

        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = destination
        request.transportType = transport
        request.requestsAlternateRoutes = false

        MKDirections(request: request).calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.status = "Rute gagal: \(error.localizedDescription)"
                    return
                }
                guard let route = response?.routes.first else {
                    self.status = "Rute tidak ditemukan"
                    return
                }
                self.load(route: route, destination: destination)
            }
        }
    }

    private func load(route: MKRoute, destination: MKMapItem) {
        var built: [Maneuver] = []
        for (offset, step) in route.steps.enumerated() {
            let points = step.polyline.coordinates
            guard let point = points.first, !step.instructions.isEmpty else { continue }
            built.append(
                Maneuver(
                    coordinate: point,
                    instruction: Self.clean(step.instructions),
                    distanceFromStart: 0,
                    arriving: offset == route.steps.count - 1
                )
            )
        }
        // Guard against routes without usable steps: still alert at the destination.
        if built.isEmpty {
            built = [Maneuver(coordinate: destination.placemark.coordinate, instruction: "Sampai di tujuan", distanceFromStart: 0, arriving: true)]
        }

        maneuvers = built
        alerted.removeAll()
        index = 0
        arrived = false
        lastAlertAt = .distantPast

        let km = route.distance / 1000
        let minutes = Int((route.expectedTravelTime / 60).rounded())
        summary = String(format: "%.1f km • %d mnt • %d belokan", km, minutes, max(0, built.count - 1))
        status = "Navigasi aktif"
        nextInstruction = built.first?.instruction ?? "—"
        nextDistance = ""

        isRunning = true
        manager.startUpdatingLocation()
        notify(title: "Navigasi dimulai", body: "\(summary). Layar boleh dikunci.")
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
        maneuvers = []
        index = 0
        arrived = false
        if status == "Navigasi aktif" { status = "Siap" }
    }

    // MARK: - Notifications

    func testNotification() {
        notify(title: "TurnBridge", body: "Tes: belok kanan ke Jl. Contoh dalam 80 m")
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func format(distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
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
        guard isRunning, !arrived, let location = locations.last else { return }
        guard index < maneuvers.count else { return }

        func target(_ i: Int) -> CLLocation {
            let c = maneuvers[i].coordinate
            return CLLocation(latitude: c.latitude, longitude: c.longitude)
        }

        // Self-heal: if the next maneuver is closer than the current one, the user already
        // passed the current point (GPS jump, tunnel, missed alert). Skip forward.
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
        nextDistance = format(distance: distance)
        nextInstruction = maneuvers[index].instruction

        let maneuver = maneuvers[index]
        let isArrival = maneuver.arriving || index == maneuvers.count - 1

        if distance <= (isArrival ? 120 : alertRadius), !alerted.contains(index), Date().timeIntervalSince(lastAlertAt) > 8 {
            alerted.insert(index)
            lastAlertAt = Date()

            if isArrival {
                notify(title: "Tujuan tercapai", body: maneuver.instruction)
                arrived = true
                status = "Sampai di tujuan"
                stop()
            } else {
                notify(
                    title: maneuver.instruction,
                    body: "dalam \(format(distance: distance)) • belokan \(index + 1)/\(max(1, maneuvers.count - 1))"
                )
                index += 1
                if index < maneuvers.count {
                    nextInstruction = maneuvers[index].instruction
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS error: \(error.localizedDescription)"
    }
}
