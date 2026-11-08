import Foundation
import CoreLocation
import MapKit

extension NavigationEngine {
    /// `turnbridge://route?daddr=-6.2,106.8&name=Cafe`
    func handleURL(_ url: URL) {
        guard let target = TargetParser.parse(url: url) else {
            status = "Link tidak dikenali"
            needsManualInput = true
            return
        }
        needsManualInput = false
        open(target)
    }

    func open(_ target: ParsedTarget) {
        if let coordinate = target.coordinate {
            log(String(format: "target: %.5f,%.5f (%@)", coordinate.latitude, coordinate.longitude, target.name ?? "-"))
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = target.name ?? "Tujuan"
            start(destination: item, transport: transport)
            return
        }

        guard let query = target.query else {
            log("target: query kosong")
            lastError = "Tujuan tidak terbaca dari link/teks"
            status = "Tujuan tidak terbaca"
            return
        }

        log("cari: \(query)")
        status = "Mencari \(query)…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.log("cari gagal: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                    self.status = "Pencarian gagal: \(error.localizedDescription)"
                    return
                }
                guard let item = response?.mapItems.first else {
                    self.log("cari: 0 hasil")
                    self.lastError = "Tidak ditemukan: \(query)"
                    self.status = "Tidak ditemukan: \(query)"
                    return
                }
                self.log("ditemukan: \(item.name ?? "-")")
                self.start(destination: item, transport: self.transport)
            }
        }
    }
}
