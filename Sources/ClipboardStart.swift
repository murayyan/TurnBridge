import Foundation
import UIKit

extension NavigationEngine {
    /// Reads a map link (or place name) from the clipboard and starts a route.
    ///
    /// Apple Maps "Copy" puts `maps.apple.com/place?address=..&coordinate=..&name=..` on the
    /// pasteboard; Google puts `maps.app.goo.gl/..` short links that have to be followed first.
    /// iOS 16+ shows the system "Allow Paste" prompt the first time, so a failure is reported
    /// visibly instead of silently doing nothing.
    @discardableResult
    func startFromClipboard() -> Bool {
        let pasteboard = UIPasteboard.general
        let url = pasteboard.url
        let raw = (pasteboard.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard url != nil || !raw.isEmpty else {
            clipboardPreview = ""
            status = "Clipboard kosong — salin tempat dulu di Apple Maps"
            needsManualInput = true
            return false
        }

        let preview = raw.isEmpty ? (url?.absoluteString ?? "") : raw
        clipboardPreview = String(preview.prefix(80)).replacingOccurrences(of: "\n", with: " ")

        guard let link = url ?? TargetParser.firstURL(in: raw) else {
            // Plain text: treat it as a place name and let MapKit search it.
            return startFromText(raw)
        }

        if TargetParser.isShortLink(link) {
            status = "Membuka link pendek…"
            resolve(link) { [weak self] resolved in
                guard let self else { return }
                self.finish(link: resolved ?? link, text: raw)
            }
            return true
        }

        return finish(link: link, text: raw)
    }

    /// Manual paste (or typed text) from the sheet shown when the clipboard cannot be read.
    @discardableResult
    func startFromText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Teks masih kosong"
            return false
        }
        needsManualInput = false
        clipboardPreview = String(trimmed.prefix(80)).replacingOccurrences(of: "\n", with: " ")

        if let link = TargetParser.firstURL(in: trimmed), TargetParser.isShortLink(link) {
            status = "Membuka link pendek…"
            resolve(link) { [weak self] resolved in
                guard let self else { return }
                self.finish(link: resolved ?? link, text: trimmed)
            }
            return true
        }

        guard let target = TargetParser.parse(trimmed) else {
            status = "Tidak terbaca — tempel link Apple/Google Maps"
            needsManualInput = true
            return false
        }
        needsManualInput = false
        open(target)
        return true
    }

    @discardableResult
    private func finish(link: URL, text: String) -> Bool {
        guard let target = TargetParser.parse(url: link, fallbackText: text) else {
            status = "Link tidak berisi lokasi"
            needsManualInput = true
            return false
        }
        needsManualInput = false
        open(target)
        return true
    }

    /// Follows `maps.app.goo.gl/..` redirects. Google answers with a 302 and no useful body,
    /// so the final `response.url` is what matters.
    private func resolve(_ url: URL, completion: @escaping (URL?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let finalURL = (response as? HTTPURLResponse)?.url
            let resolved: URL?
            if let finalURL, finalURL != url {
                resolved = finalURL
            } else if let data, let body = String(data: data, encoding: .utf8),
                      let found = TargetParser.firstURL(in: body),
                      !TargetParser.isShortLink(found) {
                resolved = found
            } else {
                resolved = nil
            }
            DispatchQueue.main.async {
                if resolved == nil, error != nil {
                    self.status = "Gagal membuka link pendek"
                }
                completion(resolved)
            }
        }.resume()
    }
}
