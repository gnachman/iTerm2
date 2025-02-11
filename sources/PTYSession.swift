//
//  PTYSession.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

extension PTYSession {
    private func promptUserForAIExplanationQuestion(regarding subjectMatter: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Enter a question about \(subjectMatter), or leave it empty to annotate it with explanations. Press ⇧⏎ to send."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = ShiftEnterTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        input.isRichText = false
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = .width
        input.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        input.textContainer?.widthTracksTextView = true
        input.textContainerInset = NSSize(width: 4, height: 4)

        weak var weakAlert = alert
        input.shiftEnterPressed = {
            weakAlert?.buttons.first?.performClick(nil)
        }

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = input
        scrollView.borderType = .lineBorder

        alert.accessoryView = scrollView
        alert.window.initialFirstResponder = input
        DispatchQueue.main.async {
            input.window?.makeFirstResponder(input)
        }

        let button = alert.runModal()
        return button == .alertFirstButtonReturn ? input.string : nil
    }

    private func add(aiAnnotations annotations: AIAnnotationCollection,
                     baseOffset: Int64) {
        let width = screen.width()
        let offset = baseOffset - screen.totalScrollbackOverflow()
        for aiAnnotation in annotations.values {
            let y = Int64(aiAnnotation.run.origin.y) + offset
            guard y >= 0 else {
                continue
            }
            let note = PTYAnnotation()
            note.stringValue = aiAnnotation.note
            var end = aiAnnotation.run.origin
            end.x += aiAnnotation.run.length - 1
            if end.x >= width {
                end.y += end.x / width
                end.x %= width
            }
            end.x += 1
            let range = VT100GridCoordRangeMake(aiAnnotation.run.origin.x,
                                                aiAnnotation.run.origin.y,
                                                end.x,
                                                end.y)
            screen.addNote(note, in: range, focus: false)
        }
    }

    @objc(explainSelectionWithAI:snapshot:command:subjectMatter:)
    func explainWithAI(selection: iTermSelection,
                       snapshot: TerminalContentSnapshot,
                       command: String?,
                       subjectMatter: String) {
        guard let question = promptUserForAIExplanationQuestion(regarding: subjectMatter) else {
            return
        }
        guard let window = genericView?.window else {
            return
        }
        removeAITerm()

        let baseOffset = screen.totalScrollbackOverflow()
        var done = false
        let aiterm = AITermControllerObjC.explain(command: command,
                                                  snapshot: snapshot,
                                                  question: question,
                                                  selection: selection,
                                                  scope: self.genericScope,
                                                  window: window) { [weak self] result in
            guard let self else {
                return
            }
            done = true
            result.whenFirst { annotations in
                self.add(aiAnnotations: annotations, baseOffset: baseOffset)
                if let mainResponse = annotations.mainResponse {
                    let chatWindowController = ChatWindowController(title: "Chat about \(subjectMatter)")
                    chatWindowController.showChatWindow()
                    chatWindowController.chatViewController.appendUserMessage(text: question)
                    chatWindowController.chatViewController.appendAgentMessage(text: mainResponse)
                    chatWindowController.chatViewController.commit()
                    chatWindowController.chatViewController.delegate = self
                }
            } second: { error in
                if error.domain == iTermAIError.domain && error.code == iTermAIError.ErrorType.requestTooLarge.rawValue {
                    iTermWarning.show(withTitle: "The text to analyze was too long. Select a portion of it and try again.",
                                      actions: ["OK"],
                                      accessory: nil,
                                      identifier: nil,
                                      silenceable: .kiTermWarningTypePersistent,
                                      heading: "Problem Sending Request",
                                      window: window)
                } else {
                    iTermWarning.show(withTitle: error.localizedDescription,
                                      actions: ["OK"],
                                      accessory: nil,
                                      identifier: nil,
                                      silenceable: .kiTermWarningTypePersistent,
                                      heading: "AI Error",
                                      window: window)
                }
                    }
            removeAITerm()
        }
        if !done {
            setAITerm(aiterm)
        }
    }
}

extension PTYSession: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, didSendMessage text: String) {
        DLog("\(text)")
    }

}
