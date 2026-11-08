import Foundation
import UIKit

extension NavigationEngine {
    /// Reads a map link (or place name) from the clipboard and starts a route.
    @discardableResult
    func startFromClipboard() -> Bool {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            status = "Clipboard kosong"
            return false
        }
        guard let target = TargetParser.parse(text) else {
            status = "Clipboard bukan lokasi"
            return false
        }
        open(target)
        return true
    }
}
