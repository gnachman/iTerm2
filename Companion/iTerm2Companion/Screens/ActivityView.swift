//
//  ActivityView.swift
//  iTerm2 Companion
//
//  A thin SwiftUI wrapper over UIActivityViewController, used to hand a file to
//  the system share sheet (AirDrop, etc.). Present it in a .sheet.
//

import SwiftUI
import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return vc
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
