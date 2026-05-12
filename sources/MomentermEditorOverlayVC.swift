//
//  MomentermEditorOverlayVC.swift
//  iTerm2
//
//  Full-terminal editor overlay: appears on top of the tab view, allows editing,
//  save via button or Cmd+S, close via X (unsaved-changes check).
//  Rules: no Auto Layout, autoresizingMask only, it_fatalError not fatalError.
//

import AppKit
import WebKit

private final class HandCursorButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@objc final class MomentermEditorOverlayVC: NSViewController {

    /// Posted on the default NotificationCenter when the overlay closes itself.
    @objc static let didCloseNotification =
        NSNotification.Name("MomentermEditorOverlayVCDidClose")

    private let fileURL: URL
    private var titleLabel: NSTextField!
    private var saveBtn: NSButton!
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var isDirty = false
    private var previewBtn: NSButton?
    private var webView: WKWebView?
    private var isPreviewMode = false
    private var isMarkdown: Bool { fileURL.pathExtension.lowercased() == "md" }

    // SF Symbol helpers
    private static func iconBtn(symbol: String, desc: String, size: CGFloat = 14) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: desc)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    @objc(initWithURL:) init(url: URL) {
        self.fileURL = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = v
        buildSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.string = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        isDirty = false
    }

    // MARK: - Build

    private func buildSubviews() {
        let w = view.bounds.width
        let h = view.bounds.height
        let barH: CGFloat = 44

        // ── Top bar ─────────────────────────────────────────────
        let bar = NSView(frame: NSRect(x: 0, y: h - barH, width: w, height: barH))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bar.autoresizingMask = [.width, .minYMargin]

        // Layout (right → left): [X close 20] [10] [save btn 48] [10] [preview 20 if .md] [10] [label fills rest]
        let iconSz: CGFloat = 20
        let saveBtnW: CGFloat = 48
        let btnH: CGFloat = 22
        let pad: CGFloat = 10
        var nextX = w - pad - iconSz   // X close

        // X close button (rightmost)
        let closeBtn = Self.iconBtn(symbol: "xmark.circle.fill", desc: "닫기", size: 14)
        closeBtn.frame = NSRect(x: nextX, y: (barH - iconSz) / 2, width: iconSz, height: iconSz)
        closeBtn.autoresizingMask = .minXMargin
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        bar.addSubview(closeBtn)
        nextX -= pad + saveBtnW

        // Save text button
        let saveBtnView = HandCursorButton(frame: NSRect(x: nextX, y: (barH - btnH) / 2, width: saveBtnW, height: btnH))
        saveBtnView.title = "저장"
        saveBtnView.bezelStyle = .rounded
        saveBtnView.autoresizingMask = .minXMargin
        saveBtnView.keyEquivalent = "s"
        saveBtnView.keyEquivalentModifierMask = [.command]
        saveBtnView.target = self
        saveBtnView.action = #selector(saveTapped)
        bar.addSubview(saveBtnView)
        saveBtn = saveBtnView
        nextX -= pad + iconSz

        // Preview icon button (eye) — .md files only
        if isMarkdown {
            let pvBtn = Self.iconBtn(symbol: "doc.text.magnifyingglass", desc: "미리보기", size: 14)
            pvBtn.frame = NSRect(x: nextX, y: (barH - iconSz) / 2, width: iconSz, height: iconSz)
            pvBtn.autoresizingMask = .minXMargin
            pvBtn.target = self
            pvBtn.action = #selector(togglePreview)
            bar.addSubview(pvBtn)
            previewBtn = pvBtn
            nextX -= pad + iconSz
        }

        // Filename label (fills remaining left space)
        let fnLabel = NSTextField(labelWithString: fileURL.lastPathComponent)
        fnLabel.frame = NSRect(x: 8, y: (barH - 20) / 2, width: nextX - 8, height: 20)
        fnLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fnLabel.lineBreakMode = .byTruncatingMiddle
        fnLabel.autoresizingMask = .width
        bar.addSubview(fnLabel)
        titleLabel = fnLabel

        view.addSubview(bar)

        // ── Separator ────────────────────────────────────────────
        let sep = NSBox(frame: NSRect(x: 0, y: h - barH - 1, width: w, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width, .minYMargin]
        view.addSubview(sep)

        // ── Scroll + TextView ────────────────────────────────────
        let tvH = h - barH - 1
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: tvH))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: w, height: tvH))
        tv.autoresizingMask = [.width, .height]
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: tvH)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        scrollView.documentView = tv
        view.addSubview(scrollView)
        textView = tv
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        saveFile()
    }

    private func saveFile() {
        do {
            try textView.string.write(to: fileURL, atomically: true, encoding: .utf8)
            isDirty = false
            // Brief checkmark feedback
            saveBtn.title = "✓ 저장됨"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.saveBtn.title = "저장"
            }
        } catch {
            let a = NSAlert()
            a.messageText = "저장 실패"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func closeTapped() {
        if isDirty {
            let a = NSAlert()
            a.messageText = "저장하지 않은 내용이 있습니다."
            a.informativeText = "\u{201C}\(fileURL.lastPathComponent)\u{201D}의 변경 내용을 저장하시겠습니까?"
            a.addButton(withTitle: "저장")
            a.addButton(withTitle: "버리기")
            a.addButton(withTitle: "취소")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { saveFile() }
            else if r == .alertThirdButtonReturn { return }
            isDirty = false
        }
        view.removeFromSuperview()
        NotificationCenter.default.post(
            name: MomentermEditorOverlayVC.didCloseNotification, object: self)
    }

    @objc private func togglePreview() {
        guard isMarkdown else { return }
        isPreviewMode.toggle()
        // Swap icon: eye = "click to preview", pencil = "click to edit"
        previewBtn?.image = NSImage(systemSymbolName: isPreviewMode ? "square.and.pencil" : "doc.text.magnifyingglass",
                                    accessibilityDescription: isPreviewMode ? "편집" : "미리보기")
        isPreviewMode ? showWebPreview() : hideWebPreview()
    }

    private func showWebPreview() {
        let wv = WKWebView(frame: scrollView.frame)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        view.addSubview(wv)
        let html = iTermBrowserTemplateLoader.load(template: "MomentermMarkdownTemplate.html")
        wv.loadHTMLString(html, baseURL: nil)
        scrollView.isHidden = true
        webView = wv
    }

    private func hideWebPreview() {
        webView?.removeFromSuperview()
        webView = nil
        scrollView.isHidden = false
    }

    private func injectMarkdownContent(_ wv: WKWebView) {
        guard let d = try? JSONEncoder().encode(textView.string),
              let s = String(data: d, encoding: .utf8) else { return }
        wv.evaluateJavaScript("window.__setContent(\(s))", completionHandler: nil)
    }
}

// MARK: - NSTextViewDelegate

extension MomentermEditorOverlayVC: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        isDirty = true
    }
}

// MARK: - WKNavigationDelegate

extension MomentermEditorOverlayVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectMarkdownContent(webView)
    }
}
