//
//  iTermBrowserFavicon.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import WebKit
import AppKit

struct FaviconError: Error {}

@MainActor
func detectFavicon(
    webView: iTermBrowserWebView,
    appearance: NSAppearance,
    isRetina: Bool
) async throws -> Either<NSImage, URL> {
    guard let currentURL = webView.url else {
        throw FaviconError()
    }

    // Internal pages → app icon
    if currentURL.absoluteString.hasPrefix(iTermBrowserSchemes.about + ":") {
        return .left(NSApp.applicationIconImage)
    }

    // file: URLs → system file icon
    if currentURL.scheme == "file",
       let path = currentURL.path.removingPercentEncoding {
        let fileIcon = NSWorkspace.shared.icon(forFile: path)
        return .left(fileIcon)
    }

    let script = iTermBrowserTemplateLoader
        .loadTemplate(named: "detect-favicon", type: "js", substitutions: [:])
    let result = try await webView.safelyEvaluateJavaScript(script, contentWorld: .page)

    guard let rawArray = result as? [[String: Any]] else {
        throw FaviconError()
    }

    struct Candidate {
        let url: URL
        let media: String
        let colorHex: String
        let isMask: Bool
        let index: Int
        let area: Int
    }

    let candidates: [Candidate] = rawArray
        .enumerated()
        .compactMap { idx, dict in
            guard
                let href = dict["href"] as? String,
                let url = URL(string: href, relativeTo: currentURL),
                let media = dict["media"] as? String
            else { return nil }
            let isMask = (dict["isMask"] as? NSNumber)?.boolValue ?? false
            let colorHex = dict["color"] as? String ?? ""
            let area = (dict["area"] as? NSNumber)?.intValue ?? 0
            return Candidate(url: url,
                             media: media,
                             colorHex: colorHex,
                             isMask: isMask,
                             index: idx,
                             area: area)
        }

    // Fallback
    if candidates.isEmpty {
        guard let fallback = URL(string: "/favicon.ico", relativeTo: currentURL) else {
            throw FaviconError()
        }
        return .right(fallback)
    }

    let isDark = appearance
        .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

    // Score by color-scheme & resolution
    let scored = candidates.map { c -> (Candidate, Int) in
        var score = 0
        let m = c.media.lowercased()

        if m.contains("prefers-color-scheme") {
            if isDark && m.contains("dark") {
                score += 2
            } else if !isDark && m.contains("light") {
                score += 2
            } else {
                score -= 1_000
            }
        }

        if m.contains("resolution") || m.contains("dppx") {
            if isRetina {
                score += 1
            } else {
                score -= 1_000
            }
        }

        return (c, score)
    }

    let best = scored
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.area != $1.0.area { return $0.0.area > $1.0.area }
            return $0.0.index < $1.0.index
        }
        .first!.0

    // If a mask-icon with color, load & tint it
    if best.isMask,
       !best.colorHex.isEmpty,
       let tintColor = NSColor(fromHexString: (best.colorHex.hasPrefix("#") ? "" : "#") + best.colorHex),
       let rawImage = NSImage(contentsOf: best.url) {
        rawImage.isTemplate = true
        let tinted = rawImage.it_image(withTintColor: tintColor)
        return .left(tinted)
    }

    return .right(best.url)
}
