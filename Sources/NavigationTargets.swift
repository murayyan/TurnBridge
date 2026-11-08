import Foundation
import CoreLocation
import MapKit

extension NavigationEngine {
    /// `turnbridge://route?daddr=-6.2,106.8&name=Cafe`
    func handleURL(_ url: URL) {
        let text = url.absoluteString
        guard let target = TargetParser.parse(text) else {
            status = "Link tidak dikenali"
            return
        }
        open(target)
    }

    func open(_ target: ParsedTarget) {
        if let coordinate = target.coordinate {
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = target.name ?? "Tujuan"
            start(destination: item, transport: .automobile)
            return
        }

        guard let query = target.query else {
            status = "Tujuan tidak terbaca"
            return
        }

        status = "Mencari \(query)…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.status = "Pencarian gagal: \(error.localizedDescription)"
                    return
                }
                guard let item = response?.mapItems.first else {
                    self.status = "Tidak ditemukan: \(query)"
                    return
                }
                self.start(destination: item, transport: .automobile)
            }
        }
    }
}
