//
//  SessionKeyboardAccessory.swift
//  iTerm2 Companion
//
//  The on-screen keyboard's input accessory bar for a live session: a compact row
//  of the most-used terminal keys (Esc, ^C, Tab, arrows) plus an expandable tray of
//  sticky modifier dead-keys (Ctrl / left+right Option) and the less-common keys
//  (F1-F12, Home/End/PgUp/PgDn, Del).
//
//  All key presses - accessory buttons AND ordinary characters typed on the system
//  keyboard (routed here from the UIKeyInput container) - funnel through
//  SessionKeyboardController, so an armed dead-key modifies whatever key comes next,
//  wherever it comes from. The controller builds the wire-level CompanionKeyEvent and
//  hands it to `send`; the Mac re-encodes it through the target session's own key
//  mapper (so Option behavior honors the profile).
//

import SwiftUI
import UIKit

/// The state of a sticky modifier dead-key. `armed` applies to exactly the next key
/// then auto-releases (one-shot); `locked` persists until tapped off.
enum SessionKeyModifierState {
    case off
    case armed
    case locked

    var isActive: Bool { self != .off }
}

@MainActor
final class SessionKeyboardController: ObservableObject {
    enum Modifier { case control, leftOption, rightOption }

    @Published var control: SessionKeyModifierState = .off
    @Published var leftOption: SessionKeyModifierState = .off
    @Published var rightOption: SessionKeyModifierState = .off
    /// Whether the expanded tray (dead-keys, function keys, navigation) is showing.
    @Published var expanded = false

    /// Emits a fully-formed key event to send to the session. Set by the canvas
    /// coordinator to route into AppModel.sendKey.
    var send: ((CompanionKeyEvent) -> Void)?
    /// Dismisses the on-screen keyboard (resigns the container's first responder).
    var dismiss: (() -> Void)?
    /// Notifies the host that the accessory's height changed (the tray expanded or
    /// collapsed) so it can resize the input accessory view.
    var onExpandedChanged: ((Bool) -> Void)?

    // MARK: Sending

    private func currentModifiers() -> CompanionKeyModifiers {
        // Shift is intentionally omitted: the system keyboard already delivers
        // shifted characters as their shifted form, and none of the accessory keys
        // need it.
        CompanionKeyModifiers(control: control.isActive,
                              shift: false,
                              leftOption: leftOption.isActive,
                              rightOption: rightOption.isActive)
    }

    /// Release any one-shot (armed) modifiers after a key was sent; locked ones stay.
    private func consumeArmedModifiers() {
        if control == .armed { control = .off }
        if leftOption == .armed { leftOption = .off }
        if rightOption == .armed { rightOption = .off }
    }

    /// Send literal typed text (from the system keyboard's insertText). Usually a
    /// single character, but the system can deliver several at once (dictation,
    /// predictive/paste insertion, a composed multi-scalar string). A one-shot
    /// (armed) modifier must apply to ONLY the first character - "armed Ctrl + the"
    /// is ^t then h, e - so split the run: the first character carries the full
    /// modifiers, the remainder carries only what stays (locked modifiers).
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        let armed = control == .armed || leftOption == .armed || rightOption == .armed
        if armed, text.count > 1 {
            send?(CompanionKeyEvent(key: .text(String(text.first!)), modifiers: currentModifiers()))
            consumeArmedModifiers()
            send?(CompanionKeyEvent(key: .text(String(text.dropFirst())), modifiers: currentModifiers()))
            return
        }
        send?(CompanionKeyEvent(key: .text(text), modifiers: currentModifiers()))
        consumeArmedModifiers()
    }

    /// Send a named special key, honoring any armed/locked modifier (e.g. Ctrl+arrow).
    func sendSpecial(_ key: CompanionSpecialKey) {
        send?(CompanionKeyEvent(key: .special(key), modifiers: currentModifiers()))
        consumeArmedModifiers()
    }

    /// The system keyboard's delete-left key.
    func sendBackspace() {
        sendSpecial(.backspace)
    }

    /// The dedicated interrupt button: always Control+C regardless of what's armed
    /// (an explicit control modifier, not the armed state). It still consumes any armed
    /// one-shot modifier, so pressing ^C counts as "the next key" and doesn't leave a
    /// stray modifier to contaminate the following keystroke.
    func sendControlC() {
        send?(CompanionKeyEvent(key: .text("c"), modifiers: CompanionKeyModifiers(control: true)))
        consumeArmedModifiers()
    }

    // MARK: Modifier dead-keys

    private func state(_ modifier: Modifier) -> SessionKeyModifierState {
        switch modifier {
        case .control: return control
        case .leftOption: return leftOption
        case .rightOption: return rightOption
        }
    }

    private func setState(_ modifier: Modifier, _ newValue: SessionKeyModifierState) {
        switch modifier {
        case .control: control = newValue
        case .leftOption: leftOption = newValue
        case .rightOption: rightOption = newValue
        }
    }

    /// Single tap: off -> armed (one-shot); armed/locked -> off.
    func tapModifier(_ modifier: Modifier) {
        let newValue: SessionKeyModifierState = state(modifier) == .off ? .armed : .off
        setState(modifier, newValue)
        if newValue != .off {
            clearOppositeOption(of: modifier)
        }
    }

    /// Double tap: lock until tapped off.
    func lockModifier(_ modifier: Modifier) {
        setState(modifier, .locked)
        clearOppositeOption(of: modifier)
    }

    /// Left and right Option are mutually exclusive: the standard key mapper reads only
    /// one Option side (both device bits set reads as right-Option), so arming both
    /// would silently apply just one side's profile behavior. Turning one Option side on
    /// clears the other so the active side is always unambiguous. Control is independent.
    private func clearOppositeOption(of modifier: Modifier) {
        switch modifier {
        case .leftOption: rightOption = .off
        case .rightOption: leftOption = .off
        case .control: break
        }
    }

    func toggleExpanded() {
        expanded.toggle()
        onExpandedChanged?(expanded)
    }

    /// Clear all transient input state (armed/locked modifiers and the expanded tray).
    /// Called when the canvas is reused in place for a different session, so an armed
    /// Ctrl (or a locked modifier, or an open tray) from the previous session can't
    /// leak onto the next one's first keystroke.
    func reset() {
        control = .off
        leftOption = .off
        rightOption = .off
        if expanded {
            expanded = false
            onExpandedChanged?(false)
        }
    }
}

/// Layout constants shared between the SwiftUI accessory and the UIInputView that
/// hosts it, so the fixed input-accessory height always matches the real content and
/// the two can't drift (an under-tall input accessory silently clips its bottom row).
/// The view below references these same constants for its key height, row spacing, and
/// padding, so the height formulas stay honest.
enum SessionKeyboardAccessoryMetrics {
    static let keyHeight: CGFloat = 38
    static let rowSpacing: CGFloat = 8
    static let verticalPadding: CGFloat = 6
    static let dividerHeight: CGFloat = 1
    /// A little slack so sub-pixel rounding never clips the bottom row.
    static let slack: CGFloat = 2

    /// Compact = vertical padding (top+bottom) + one key row.
    static let compactHeight: CGFloat = verticalPadding * 2 + keyHeight + slack

    /// Expanded adds, under the compact row: a row gap, the divider, another row gap,
    /// and the 4-row tray (4 key rows with 3 gaps between them).
    static let expandedHeight: CGFloat = compactHeight
        + rowSpacing + dividerHeight + rowSpacing
        + (keyHeight * 4 + rowSpacing * 3)
}

struct SessionKeyboardAccessory: View {
    @ObservedObject var controller: SessionKeyboardController

    private typealias Metrics = SessionKeyboardAccessoryMetrics

    var body: some View {
        VStack(spacing: Metrics.rowSpacing) {
            compactRow
            if controller.expanded {
                Divider()
                expandedTray
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: Compact row

    private var compactRow: some View {
        HStack(spacing: 6) {
            keyCap("esc") { controller.sendSpecial(.escape) }
            keyCap("^C") { controller.sendControlC() }
            keyCap("tab") { controller.sendSpecial(.tab) }
            Spacer(minLength: 4)
            keyCap(systemImage: "arrow.left") { controller.sendSpecial(.left) }
            keyCap(systemImage: "arrow.down") { controller.sendSpecial(.down) }
            keyCap(systemImage: "arrow.up") { controller.sendSpecial(.up) }
            keyCap(systemImage: "arrow.right") { controller.sendSpecial(.right) }
            Spacer(minLength: 4)
            keyCap(systemImage: controller.expanded ? "chevron.down" : "chevron.up") {
                controller.toggleExpanded()
            }
            keyCap(systemImage: "keyboard.chevron.compact.down") { controller.dismiss?() }
        }
    }

    // MARK: Expanded tray

    private var expandedTray: some View {
        VStack(spacing: Metrics.rowSpacing) {
            HStack(spacing: 6) {
                modifierKey(glyph: "⌃", caption: "ctrl", .control, state: controller.control)
                modifierKey(glyph: "⌥", caption: "Left", .leftOption, state: controller.leftOption)
                modifierKey(glyph: "⌥", caption: "Right", .rightOption, state: controller.rightOption)
                Spacer(minLength: 4)
                keyCap("home") { controller.sendSpecial(.home) }
                keyCap("end") { controller.sendSpecial(.end) }
                keyCap("del") { controller.sendSpecial(.forwardDelete) }
            }
            HStack(spacing: 6) {
                keyCap("PgUp") { controller.sendSpecial(.pageUp) }
                keyCap("PgDn") { controller.sendSpecial(.pageDown) }
                Spacer(minLength: 4)
            }
            functionKeyRow(keys: [.f1, .f2, .f3, .f4, .f5, .f6])
            functionKeyRow(keys: [.f7, .f8, .f9, .f10, .f11, .f12])
        }
    }

    private func functionKeyRow(keys: [CompanionSpecialKey]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                keyCap(functionLabel(key)) { controller.sendSpecial(key) }
            }
        }
    }

    private func functionLabel(_ key: CompanionSpecialKey) -> String {
        String(key.rawValue.uppercased())   // f5 -> "F5"
    }

    // MARK: Key caps

    /// The standard iOS keyboard click, played only when the user has key clicks
    /// enabled (the accessory's UIInputView opts in via enableInputClicksWhenVisible).
    private func click() {
        UIDevice.current.playInputClick()
    }

    /// The shared key-cap button: click feedback, standard sizing, and cap styling.
    /// Every cap (text or glyph) routes through here so future changes (haptics,
    /// disabled state, sizing) are made once.
    private func keyCap<Label: View>(action: @escaping () -> Void,
                                     @ViewBuilder label: () -> Label) -> some View {
        Button {
            click()
            action()
        } label: {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.keyHeight)
        }
        .buttonStyle(SessionKeyCapStyle(active: false))
    }

    private func keyCap(_ title: String, action: @escaping () -> Void) -> some View {
        keyCap(action: action) {
            Text(title).font(.system(size: 15, weight: .medium, design: .rounded))
        }
    }

    private func keyCap(systemImage: String, action: @escaping () -> Void) -> some View {
        keyCap(action: action) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .medium))
        }
    }

    /// A sticky modifier dead-key: a glyph over a small caption (so "⌥ / Left" and
    /// "⌥ / Right" read unambiguously), tinted while armed or locked, with a lock
    /// badge when locked.
    private func modifierKey(glyph: String,
                             caption: String,
                             _ modifier: SessionKeyboardController.Modifier,
                             state: SessionKeyModifierState) -> some View {
        // Not a Button: a Button's own tap plus a separate double-tap gesture aren't
        // arbitrated, so a genuine double tap could fire BOTH (lock, then the single-tap
        // toggles it right back off). Two onTapGesture(count:) on the same view ARE
        // mutually exclusive - SwiftUI runs the single-tap only if the double-tap fails
        // to recognize - so lock is reliable. Count 2 is registered first so it wins.
        VStack(spacing: 0) {
            Text(glyph)
                .font(.system(size: 15, weight: .semibold))
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.keyHeight)
        .overlay(alignment: .topTrailing) {
            if state == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
                    .padding(2)
            }
        }
        .modifier(SessionKeyCapLook(active: state.isActive))
        .onTapGesture(count: 2) {
            click()
            controller.lockModifier(modifier)
        }
        .onTapGesture(count: 1) {
            click()
            controller.tapModifier(modifier)
        }
    }
}

/// The rounded key-cap look (tinted when armed/locked), shared by the momentary
/// key-cap Button and the sticky modifier keys so they stay visually identical.
private struct SessionKeyCapLook: ViewModifier {
    var active: Bool
    var pressed: Bool = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var background: Color {
        if active {
            return Color.accentColor.opacity(pressed ? 0.7 : 1.0)
        }
        return Color.primary.opacity(pressed ? 0.22 : 0.1)
    }
}

/// A rounded key-cap look that tints when its modifier is armed/locked.
private struct SessionKeyCapStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SessionKeyCapLook(active: active, pressed: configuration.isPressed))
    }
}
