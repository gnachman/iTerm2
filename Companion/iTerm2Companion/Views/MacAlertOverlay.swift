//
//  MacAlertOverlay.swift
//  iTerm2Companion
//
//  Shows a modal alert that is up on the paired Mac, and lets the user answer
//  it from here.
//
//  An alert on the Mac can stop it from serving anything until someone answers
//  it, so the card is presented in front of everything, in its own window. A
//  sheet attached to the root view would be hidden behind any sheet already up
//  (a conversation's composer, Settings), which is exactly when the user most
//  needs to see why nothing is responding.
//
//  The heading, body, and button titles are the Mac's own strings, already
//  localized there, so they are shown verbatim.
//

import SwiftUI
import UIKit
import CompanionProtocol

/// The card itself: what the Mac's alert says, and its buttons.
struct MacAlertCard: View {
    let alert: CompanionModalAlert
    let state: AppModel.MacAlertPresentation.CardState
    let onAnswer: (_ buttonIndex: Int, _ suppress: Bool, _ inputs: [String: String]) -> Void
    let onNotNow: () -> Void

    /// nil until the user touches the toggle, which starts where the Mac's
    /// checkbox is.
    @State private var chosenSuppress: Bool?
    private var suppress: Bool { chosenSuppress ?? alert.suppressionDefault }
    /// What the user has typed into each input, by id. An input that has not
    /// been touched is absent, and shows what the Mac's control holds.
    @State private var entered: [String: String] = [:]

    private var canAnswer: Bool { state == .ready }

    var body: some View {
        VStack(spacing: 14) {
            Label("On your Mac", systemImage: "macbook")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(verbatim: alert.heading)
                .font(.headline)
                .multilineTextAlignment(.center)

            if !alert.body.isEmpty {
                // Most alerts are a sentence or two and are shown whole. A long
                // one scrolls instead of pushing the buttons off the screen.
                ViewThatFits(in: .vertical) {
                    bodyText
                    ScrollView {
                        bodyText
                    }
                    .frame(maxHeight: 260)
                }
            }

            if alert.hasAccessory {
                Text("More details are shown on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(alert.inputs, id: \.id) { input in
                inputField(input)
            }

            if state == .answerOnMac {
                Label("Answer this on your Mac. Something else there is in front of it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let suppressionLabel = alert.suppressionLabel {
                // A checkbox, like the one it stands for on the Mac.
                Button {
                    chosenSuppress = !suppress
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: suppress ? "checkmark.square.fill" : "square")
                            .foregroundStyle(suppress ? Color.accentColor : Color.secondary)
                        Text(verbatim: suppressionLabel)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!canAnswer)
                .accessibilityAddTraits(suppress ? .isSelected : [])
            }

            VStack(spacing: 8) {
                // A button the Mac does not offer here keeps its place in the
                // numbering but is not shown.
                ForEach(Array(alert.buttons.enumerated()).filter { $0.element.offered }, id: \.offset) { index, button in
                    answerButton(index: index, button: button)
                }
            }

            if state == .sending {
                ProgressView()
            }

            Button("Not now") { onNotNow() }
                .font(.footnote)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(24)
    }

    private func text(for input: CompanionModalAlert.Input) -> Binding<String> {
        return Binding(get: { entered[input.id] ?? input.value },
                       set: { entered[input.id] = $0 })
    }

    /// The same value as a number, for the stepper. Reads through the rule the
    /// answer uses, so the stepper starts from what would actually be sent.
    private func number(for input: CompanionModalAlert.Input) -> Binding<Int> {
        return Binding(
            get: { Int(AppModel.valueToSend(for: input, entered: entered[input.id] ?? input.value)) ?? 0 },
            set: { entered[input.id] = String($0) })
    }

    @ViewBuilder
    private func inputField(_ input: CompanionModalAlert.Input) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = input.label, !label.isEmpty {
                Text(verbatim: label)
                    .font(.subheadline)
            }
            if input.kind == CompanionModalAlert.Input.integerKind {
                HStack(spacing: 12) {
                    TextField("", text: text(for: input))
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Stepper("", value: number(for: input),
                            in: (input.minimum ?? Int.min)...max(input.minimum ?? Int.min, input.maximum ?? Int.max))
                        .labelsHidden()
                    Spacer(minLength: 0)
                }
            } else if input.kind == CompanionModalAlert.Input.secretKind {
                SecureField("", text: text(for: input))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            } else {
                TextField("", text: text(for: input))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!canAnswer)
    }

    private var bodyText: some View {
        Text(verbatim: alert.body)
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func answerButton(index: Int, button: CompanionModalAlert.Button) -> some View {
        let label = Text(verbatim: button.title)
            .frame(maxWidth: .infinity)
        // Every input is sent, touched or not, so the Mac acts on exactly what
        // this card shows.
        let action = {
            var values: [String: String] = [:]
            for input in alert.inputs {
                values[input.id] = entered[input.id] ?? input.value
            }
            onAnswer(index, suppress, values)
        }
        // Index 0 is the Mac alert's default button.
        if index == 0 {
            Button(role: button.isDestructive ? .destructive : nil, action: action) { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canAnswer)
        } else {
            Button(role: button.isDestructive ? .destructive : nil, action: action) { label }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!canAnswer)
        }
    }
}

/// The content of the alert window: a dimmed backdrop and the card.
private struct MacAlertOverlayRoot: View {
    let model: AppModel

    var body: some View {
        if case .overlay(let alert, let state) = model.macAlertPresentation {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                MacAlertCard(alert: alert,
                             state: state,
                             // Named by id: the Mac may replace the alert between
                             // this card being drawn and the tap.
                             onAnswer: {
                                 model.answerMacAlert(buttonIndex: $0, suppress: $1, inputs: $2,
                                                      shownAlertID: alert.id)
                             },
                             onNotNow: { model.dismissMacAlert(shownAlertID: alert.id) })
                    // A different alert is a different card: start its toggle off.
                    .id(alert.id)
            }
        }
    }
}

/// Puts the card in a window above the app's own, so it shows over any sheet.
@MainActor
final class MacAlertWindowPresenter {
    static let shared = MacAlertWindowPresenter()

    private var window: UIWindow?
    /// The window that was key before the card took over, to hand key status
    /// back to.
    private weak var previousKeyWindow: UIWindow?

    /// Whether the card's window is on screen.
    var isShowing: Bool {
        return window != nil && window?.isHidden == false
    }

    /// Show or hide the card to match the model. Call whenever
    /// `macAlertPresentation` may have changed, and when the app becomes active.
    func update(model: AppModel) {
        if case .overlay(let alert, _) = model.macAlertPresentation {
            show(model: model, needsKeyboard: !alert.inputs.isEmpty)
        } else {
            hide()
        }
    }

    private func show(model: AppModel, needsKeyboard: Bool) {
        if window == nil {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                // No scene yet (launching, or in the background). update() runs
                // again when the app becomes active.
                companionLog("Mac alert: no window scene to show the card in yet")
                return
            }
            companionLog("Mac alert: showing the card")
            let host = UIHostingController(rootView: MacAlertOverlayRoot(model: model))
            host.view.backgroundColor = .clear
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert
            window.backgroundColor = .clear
            window.rootViewController = host
            self.window = window
            // The keyboard would cover the card.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }
        window?.isHidden = false
        // A text field only gets the keyboard in the key window. Take key status
        // only for a card that has one, and remember whom to give it back to.
        if needsKeyboard, let window, !window.isKeyWindow {
            previousKeyWindow = window.windowScene?.keyWindow
            window.makeKey()
        }
    }

    private func hide() {
        let wasKey = window?.isKeyWindow ?? false
        window?.isHidden = true
        window = nil
        if wasKey {
            previousKeyWindow?.makeKey()
        }
        previousKeyWindow = nil
    }
}
