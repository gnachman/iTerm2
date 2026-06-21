//
//  MentionComposerView.swift
//  iTerm2 Companion
//
//  The conversation's message input field. It is a UITextView (not a SwiftUI
//  TextField) so an inserted @-mention can be an atomic NSTextAttachment
//  token, drawn as a link-blue terminal glyph plus name that selects and
//  deletes as one entity, exactly like the Mac compose field's
//  ChatSessionMentionAttachment. On send the attributed contents serialize
//  back to plain text with each token as "@<guid>" (the Mac's
//  chatMentionSerialized() contract).
//

import SwiftUI
import UIKit

/// One @-mention token. Carries the session guid it stands for; renders as a
/// baked image so the text system treats it as a single character.
final class MentionTextAttachment: NSTextAttachment {
    let guid: String
    let displayName: String

    init(guid: String, displayName: String, font: UIFont, color: UIColor) {
        self.guid = guid
        self.displayName = displayName
        super.init(data: nil, ofType: nil)
        let rendered = Self.render(name: displayName, font: font, color: color)
        image = rendered
        bounds = CGRect(x: 0,
                        y: font.descender,
                        width: rendered.size.width,
                        height: rendered.size.height)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    /// Terminal glyph, thin space, underlined name: the same shape mention
    /// links have in message bubbles.
    private static func render(name: String, font: UIFont, color: UIColor) -> UIImage {
        let icon = UIImage(systemName: "terminal",
                           withConfiguration: UIImage.SymbolConfiguration(font: font))?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        let text = NSAttributedString(string: name, attributes: [
            .font: font,
            .foregroundColor: color,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: color,
        ])
        let textSize = text.size()
        let iconSize = icon?.size ?? .zero
        let spacing: CGFloat = icon == nil ? 0 : 3
        let size = CGSize(width: ceil(iconSize.width + spacing + textSize.width),
                          height: ceil(max(textSize.height, iconSize.height)))
        return UIGraphicsImageRenderer(size: size).image { _ in
            icon?.draw(at: CGPoint(x: 0, y: (size.height - iconSize.height) / 2))
            text.draw(at: CGPoint(x: iconSize.width + spacing,
                                  y: (size.height - textSize.height) / 2))
        }
    }
}

/// The composer's imperative surface: the SwiftUI layer holds one of these to
/// insert tokens at the cursor, read the serialized draft, and clear it.
@MainActor
final class MentionComposerController {
    fileprivate weak var textView: UITextView?

    private static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
    fileprivate static var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: UIColor.label]
    }

    /// The draft as the wire sees it: token attachments become "@<guid>".
    var serializedText: String {
        guard let attributed = textView?.attributedText else { return "" }
        var result = ""
        let ns = attributed.string as NSString
        attributed.enumerateAttribute(.attachment,
                                      in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let mention = value as? MentionTextAttachment {
                result += "@" + mention.guid
            } else if value == nil {
                result += ns.substring(with: range)
            }
        }
        return result
    }

    var isEmpty: Bool {
        serializedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Insert a mention token (plus a trailing space) at the cursor.
    func insertMention(guid: String, displayName: String) {
        guard let textView else { return }
        let attachment = MentionTextAttachment(guid: guid,
                                               displayName: displayName,
                                               font: Self.bodyFont,
                                               color: textView.tintColor ?? .systemBlue)
        let token = NSMutableAttributedString(attachment: attachment)
        token.addAttribute(.font, value: Self.bodyFont,
                           range: NSRange(location: 0, length: token.length))
        token.append(NSAttributedString(string: " ", attributes: Self.typingAttributes))

        let selection = textView.selectedRange
        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        updated.replaceCharacters(in: selection, with: token)
        textView.attributedText = updated
        textView.selectedRange = NSRange(location: selection.location + token.length, length: 0)
        textView.typingAttributes = Self.typingAttributes
        textView.delegate?.textViewDidChange?(textView)
    }

    func clear() {
        guard let textView else { return }
        textView.attributedText = NSAttributedString(string: "", attributes: Self.typingAttributes)
        textView.typingAttributes = Self.typingAttributes
        textView.delegate?.textViewDidChange?(textView)
        liveRange = nil
        liveNeedsLeadingSpace = false
    }

    // MARK: - Live dictation

    /// The span of text currently owned by live dictation, so successive partial
    /// transcripts overwrite it instead of appending. nil when not dictating.
    private var liveRange: NSRange?
    /// Whether to prefix the transcript with a space, so dictation that starts
    /// right after existing non-whitespace text reads as a new word rather than
    /// being glued on ("note:" + "fix this" -> "note: fix this").
    private var liveNeedsLeadingSpace = false

    /// Mark the cursor position as the start of a live dictation segment.
    func beginLiveTranscript() {
        guard let textView else { return }
        let location = textView.selectedRange.location
        liveRange = NSRange(location: location, length: 0)
        let contents = textView.attributedText.string as NSString
        if location > 0, location <= contents.length {
            let preceding = contents.substring(with: NSRange(location: location - 1, length: 1))
            liveNeedsLeadingSpace = preceding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } else {
            liveNeedsLeadingSpace = false
        }
    }

    /// Replace the live segment with the latest partial transcript, leaving any
    /// text the user typed before it untouched.
    func updateLiveTranscript(_ text: String) {
        guard let textView, let range = liveRange else { return }
        let prefix = (liveNeedsLeadingSpace && !text.isEmpty) ? " " : ""
        let replacement = NSAttributedString(string: prefix + text, attributes: Self.typingAttributes)
        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        // Guard against the range falling outside the current contents (e.g. the
        // field was cleared underneath us).
        guard range.location + range.length <= updated.length else {
            liveRange = nil
            return
        }
        updated.replaceCharacters(in: range, with: replacement)
        textView.attributedText = updated
        let newRange = NSRange(location: range.location, length: replacement.length)
        liveRange = newRange
        textView.selectedRange = NSRange(location: newRange.location + newRange.length, length: 0)
        textView.typingAttributes = Self.typingAttributes
        textView.delegate?.textViewDidChange?(textView)
        // Keep the newest transcribed text in view. Deferred so it runs after the
        // self-sizing layout caps the height and enables scrolling; scrolling
        // synchronously here would be a no-op (the view is still full height).
        let caret = textView.selectedRange
        DispatchQueue.main.async { [weak textView] in
            textView?.scrollRangeToVisible(caret)
        }
    }

    /// Finish dictation: leave the inserted text in place as ordinary, editable
    /// composer content.
    func endLiveTranscript() {
        liveRange = nil
        liveNeedsLeadingSpace = false
    }

    /// Apply the definitive final transcript and finish. Called directly with the
    /// value returned by VoiceCaptureController.stop(), rather than relying on the
    /// asynchronous liveText observer - which fires in a later update pass, after
    /// the caller has already cleared liveRange or read the draft, dropping the
    /// final words.
    func commitLiveTranscript(_ text: String) {
        updateLiveTranscript(text)
        liveRange = nil
        liveNeedsLeadingSpace = false
    }
}

struct MentionComposerView: UIViewRepresentable {
    let controller: MentionComposerController
    @Binding var isFocused: Bool
    let placeholder: String
    /// Bumped by the caller on every edit. Carried here so SwiftUI sees a
    /// changed view value and re-runs sizeThatFits as the draft grows.
    let revision: Int
    /// While dictating, manual editing is disabled. The live-transcript segment
    /// is tracked by a fixed range; letting the user edit text before it would
    /// shift that range and corrupt the field, so editing is locked until
    /// dictation ends.
    let isDictating: Bool
    /// Fired on every edit so the caller can refresh its send-button state.
    let onChange: () -> Void

    func makeUIView(context: Context) -> SelfSizingTextView {
        let textView = SelfSizingTextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.typingAttributes = MentionComposerController.typingAttributes
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        textView.addSubview(placeholderLabel)
        textView.placeholderLabel = placeholderLabel

        controller.textView = textView
        return textView
    }

    func updateUIView(_ textView: SelfSizingTextView, context: Context) {
        context.coordinator.parent = self
        // Honor SwiftUI's .disabled, which doesn't reach UIKit views on its
        // own through a representable.
        let enabled = context.environment.isEnabled
        textView.isEditable = enabled && !isDictating
        textView.isUserInteractionEnabled = enabled
        if isFocused, !textView.isFirstResponder, enabled {
            textView.becomeFirstResponder()
        } else if (!isFocused || !enabled), textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Without this, SwiftUI gives the text view (a UIScrollView subclass)
    /// every point of height the layout proposes. Answer with the content
    /// height instead, capped at the line limit.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: SelfSizingTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else {
            return nil
        }
        return CGSize(width: width, height: uiView.preferredHeight(forWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MentionComposerView

        init(parent: MentionComposerView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? SelfSizingTextView)?.refreshPlaceholder()
            parent.onChange()
        }

        // Focus changes land outside SwiftUI's update; defer the state write
        // a tick so it never mutates state mid render pass.
        func textViewDidBeginEditing(_ textView: UITextView) {
            Task { @MainActor [parent] in
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            Task { @MainActor [parent] in
                parent.isFocused = false
            }
        }
    }
}

/// Grows with its contents up to a line cap (then scrolls), like the
/// vertical-axis TextField it replaces.
final class SelfSizingTextView: UITextView {
    fileprivate var placeholderLabel: UILabel?
    private let maxLines = 5

    /// Content height for the given width, capped at the line limit (with
    /// scrolling enabled only past the cap).
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let lineHeight = (font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let fitting = sizeThatFits(CGSize(width: width,
                                          height: .greatestFiniteMagnitude))
        let cap = ceil(lineHeight * CGFloat(maxLines))
            + textContainerInset.top + textContainerInset.bottom
        isScrollEnabled = fitting.height > cap
        return max(min(fitting.height, cap), ceil(lineHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel?.frame = CGRect(origin: .zero, size: bounds.size)
        refreshPlaceholder()
    }

    fileprivate func refreshPlaceholder() {
        placeholderLabel?.isHidden = attributedText.length > 0
    }
}
