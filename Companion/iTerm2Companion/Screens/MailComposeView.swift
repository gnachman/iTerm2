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
        var attachedCount = 0
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else {
                companionLog("Could not read log attachment \(url.lastPathComponent); it will be missing from the email.")
                continue
            }
            let mimeType = url.pathExtension.lowercased() == "zip" ? "application/zip" : "text/plain"
            vc.addAttachmentData(data, mimeType: mimeType, fileName: url.lastPathComponent)
            attachedCount += 1
        }
        // With the single-zip design, a failed read here would otherwise open
        // a composer with no attachment and no error, so the user sends an
        // empty diagnostic email believing the logs went out. We can't abort
        // the already-presenting composer from here, but record it so the
        // failure is diagnosable. The caller should verify the archive is
        // readable before presenting this (see SettingsView's
        // archivePrepFailed path).
        if !attachments.isEmpty && attachedCount == 0 {
            companionLog("None of the \(attachments.count) log attachment(s) could be read; presenting an email with no logs attached.")
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
