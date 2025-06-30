//
//  iTermBrowserContextMenuHandler.swift
//  iTerm2
//
//  Created by Claude on 6/23/25.
//

import Foundation
import WebKit

@available(macOS 11.0, *)
class iTermBrowserContextMenuHandler {
    private let webView: WKWebView
    private weak var parentWindow: NSWindow?
    
    init(webView: WKWebView, parentWindow: NSWindow?) {
        self.webView = webView
        self.parentWindow = parentWindow
    }
    
    func savePageAs() {
        guard let url = webView.url, let window = parentWindow else { return }
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = sanitizeFilename(url.host ?? "page")
        savePanel.title = "Save Page As"
        savePanel.message = "Choose a folder to save the page and its resources"
        
        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let folderURL = savePanel.url else { return }
            
            Task {
                await self.performPageSave(url: url, to: folderURL)
            }
        }
    }
    
    private func performPageSave(url: URL, to folderURL: URL) async {
        let pageSaver = iTermBrowserPageSaver(webView: webView, baseURL: url)
        
        do {
            try await pageSaver.savePageWithResources(to: folderURL)
            
            await MainActor.run {
                let htmlFile = folderURL.appendingPathComponent("index.html")
                NSWorkspace.shared.selectFile(htmlFile.path, inFileViewerRootedAtPath: folderURL.path)
            }
        } catch {
            DLog("Error saving page: \(error)")
            await showSaveError(error)
        }
    }
    
    @MainActor
    private func showSaveError(_ error: Error) {
        guard let window = parentWindow else { return }
        
        let alert = NSAlert()
        alert.messageText = "Save Failed"
        alert.informativeText = "Could not save the page: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
