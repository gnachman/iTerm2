//
//  MailComposeView.swift
//  iTerm2 Companion
//
//  A thin SwiftUI wrapper over the system mail composer, used to email the
//  diagnostic log files. Present it in a .sheet; callers should first check
//  MFMailComposeViewController.canSendMail().
//

import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let to: [String]
    let subject: String
    let body: String
    let attachments: [URL]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for url in attachments {
            if let data = try? Data(contentsOf: url) {
                vc.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
            }
        }
        return vc
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish()
        }
    }
}
