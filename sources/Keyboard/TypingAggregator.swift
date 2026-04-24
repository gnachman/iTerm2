//
//  TypingAggregator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/21.
//

import Foundation

/// Interposes a control text editing delegate and delays and aggregates controlTextDidEndEditing notifications.
/// `text field ---delegate---> TypingAggregator  ---delegate---> your object`
@objc(iTermTypingAggregator)
class TypingAggregator: NSObject, NSControlTextEditingDelegate {
    private let interval = TimeInterval(0.5)
    @IBOutlet weak var delegate: NSControlTextEditingDelegate?
    private var lastChange = Date.distantPast
    private var timer: Timer? = nil
    private var lastControlTextDidChangeNotification: Notification? = nil

    @objc func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field.stringValue.isEmpty {
            lastControlTextDidChangeNotification = notification
            updateIfNeeded()
            return
        }
        scheduleTimer()
        lastControlTextDidChangeNotification = notification
    }

    @objc func controlTextDidEndEditing(_ notification: Notification) {
        updateIfNeeded()
        delegate?.controlTextDidEndEditing?(notification)
    }

    @objc func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        return delegate?.control?(control,
                                  textView: textView,
                                  completions: words,
                                  forPartialWordRange: charRange,
                                  indexOfSelectedItem: index) ?? []
    }

    @objc func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        updateIfNeeded()
        return delegate?.control?(control, textView: textView, doCommandBy: commandSelector) ?? false
    }

    @objc func controlTextDidBeginEditing(_ notification: Notification) {
        updateIfNeeded()
        delegate?.controlTextDidBeginEditing?(notification)
    }

    @objc func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        return delegate?.control?(control, textShouldBeginEditing: fieldEditor) ?? true
    }

    @objc func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        updateIfNeeded()
        return delegate?.control?(control, textShouldEndEditing: fieldEditor) ?? true
    }

    @objc func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool {
        return delegate?.control?(control, didFailToFormatString: string, errorDescription: error) ?? false
    }

    @objc func control(_ control: NSControl, didFailToValidatePartialString string: String, errorDescription error: String?) {
        delegate?.control?(control, didFailToValidatePartialString: string, errorDescription: error)
    }

    @objc func control(_ control: NSControl, isValidObject obj: Any?) -> Bool {
        return delegate?.control?(control, isValidObject: obj) ?? true
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        cancelTimer()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false, block: { [weak self] timer in
            self?.timerDidFire()
        })
    }

    private func timerDidFire() {
        timer = nil
        updateIfNeeded()
    }

    private func updateIfNeeded() {
        cancelTimer()
        guard let notification = lastControlTextDidChangeNotification else {
            return
        }
        lastControlTextDidChangeNotification = nil
        delegate?.controlTextDidChange?(notification)
    }
}
