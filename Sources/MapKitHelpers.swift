import MapKit

extension MKPolyline {
    /// All points of the polyline in order.
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
