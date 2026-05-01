//
//  SessionView+CodeReviewPromptOverlay.swift
//  iTerm2SharedARC
//
//  Owns the lifecycle of the in-session Code Review prompt overlay so
//  the rest of the codebase doesn't reach into SessionView's subview
//  tree directly.
//

import AppKit

extension SessionView {
    @objc(presentCodeReviewPromptOverlayWithDefaultPrompt:onStart:)
    func presentCodeReviewPromptOverlay(defaultPrompt: String?,
                                         onStart: @escaping (String) -> Void) {
        // Drop any existing overlay so a rapid reload-on-reload doesn't
        // stack two prompt views.
        codeReviewPromptOverlay?.removeFromSuperview()

        let promptView = CodeReviewPromptView(frame: scrollview.frame)
        promptView.frameProvider = { [weak self] in
            guard let self else { return .zero }
            var rect = self.scrollview.frame
            rect.size.width = max(0, rect.size.width - self.actualPanelReservation)
            return rect
        }
        if let defaultPrompt {
            promptView.text = defaultPrompt
        }
        weak var weakPromptView = promptView
        promptView.onStart = { text in
            onStart(text)
            weakPromptView?.removeFromSuperview()
        }
        codeReviewPromptOverlay = promptView
        addSubview(belowFind: promptView)
    }
}
