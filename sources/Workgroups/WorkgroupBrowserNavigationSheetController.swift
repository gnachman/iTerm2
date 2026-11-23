//
//  WorkgroupBrowserNavigationSheetController.swift
//  iTerm2
//
//  Explains and sets up showing pages in a workgroup's browser member from
//  an agent. One sheet serves three entry points: the Claude Code installer,
//  the one-time offer to existing Claude Code users, and the workgroup
//  editor in Settings.
//

import AppKit

final class WorkgroupBrowserNavigationSheetController: NSWindowController, NSWindowDelegate {
    enum Mode {
        /// The Claude Code workgroup: a checklist that sets everything up.
        /// `location` is where the Claude that will use it reads its settings
        /// and CLAUDE.md, on this Mac or a remote host.
        case claudeCode(location: ClaudeCodeConfigLocation)
        /// Any other workgroup's browser member: steps to follow by hand.
        /// `useDefaultVariable` sets the member's URL to the default variable.
        case workgroup(config: iTermWorkgroupSessionConfig,
                       useDefaultVariable: (() -> iTermWorkgroupSessionConfig?)?)
    }

    private static var open = [WorkgroupBrowserNavigationSheetController]()

    private var mode: Mode
    /// Called when the sheet closes, with whether the Claude Code setup is
    /// complete (see isComplete).
    private let onClose: ((Bool) -> Void)?
    private let width: CGFloat = 580
    private let stack = NSStackView()
    private var instructionsTextView: NSTextView?
    /// Set when the user clicks Add Rule here. The step is never checked
    /// without that, even if the settings file already has the rule.
    private var allowRuleApproved = false
    /// Set when the user copies the instructions, to paste into a skill.
    private var instructionsCopied = false
    /// The instructions shown, which the text view displays read-only.
    private var generatedInstructions: String?
    /// Whether the settings file already has the allow rule; nil until
    /// looked at, which for a remote host takes a round trip.
    private var allowRuleFound: Bool?
    /// While a step changes files, which on a remote host takes a while, its
    /// buttons are disabled so it isn't started twice.
    private var busy = false
    private var finished = false

    // MARK: - Presenting

    /// Lets the Claude Code integration open this sheet without depending on
    /// it, which would make a cycle, since the sheet uses the integration.
    @objc static func installClaudeCodePresenter() {
        ClaudeCodeBrowserNavigation.presentSetup = { parent, location, onClose in
            present(mode: .claudeCode(location: location), parent: parent, onClose: onClose)
        }
    }

    static func showWorkgroupHelp(config: iTermWorkgroupSessionConfig,
                                  workgroup: iTermWorkgroup,
                                  parent: NSWindow?,
                                  useDefaultVariable: (() -> iTermWorkgroupSessionConfig?)?) {
        // The Claude Code checklist sets up the workgroup's first bound
        // member, adding one if there is none. For any other member, such as
        // a browser added by hand, it would add a second browser and leave
        // this one alone, so that member gets the same help as in any
        // workgroup, which can bind it. Once bound, it gets the checklist.
        // `config` may have edits the workgroup doesn't have yet.
        let firstBound = workgroup.sessions.first { member in
            let current = member.uniqueIdentifier == config.uniqueIdentifier ? config : member
            return WorkgroupBrowserNavigation.target(for: current) != nil
        }
        if workgroup.uniqueIdentifier == ClaudeCodeWorkgroupTemplate.ID.workgroup,
           firstBound?.uniqueIdentifier == config.uniqueIdentifier {
            // No session here, so it's for the Claude in a running Claude
            // Code workgroup, wherever that runs, or else this Mac's.
            ClaudeCodeBrowserNavigation.showSetup(near: parent, session: nil)
        } else {
            present(mode: .workgroup(config: config, useDefaultVariable: useDefaultVariable),
                    parent: parent,
                    onClose: nil)
        }
    }

    private static func present(mode: Mode, parent: NSWindow?, onClose: ((Bool) -> Void)?) {
        let controller = WorkgroupBrowserNavigationSheetController(mode: mode, onClose: onClose)
        guard let window = controller.window else {
            RLog("WorkgroupBrowserNavigationSheetController: no window to show")
            onClose?(false)
            return
        }
        open.append(controller)
        if let parent {
            // Also when the sheet ends without closing its window, as when
            // its parent closes, so onClose still runs.
            parent.beginSheet(window) { [weak controller] _ in
                controller?.finish()
            }
        } else {
            window.center()
            controller.showWindow(nil)
        }
    }

    private init(mode: Mode, onClose: ((Bool) -> Void)?) {
        self.mode = mode
        self.onClose = onClose
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: true)
        panel.title = String(localized: "WorkgroupBrowserNavigation.WindowTitle",
                             defaultValue: "Show Pages in a Browser",
                             comment: "Title of the window that sets up showing web pages in a workgroup’s browser session")
        super.init(window: panel)
        panel.delegate = self
        rebuild()
        refreshAllowRuleFound()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content

    private func rebuild() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: outerMargin, left: outerMargin, bottom: 20, right: outerMargin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        instructionsTextView = nil
        switch mode {
        case .claudeCode(let location):
            buildClaudeCode(location: location)
        case .workgroup(let config, let useDefaultVariable):
            buildWorkgroup(config: config, useDefaultVariable: useDefaultVariable)
        }
        let done = NSButton(title: String(localized: "General.Done", defaultValue: "Done", comment: "Done button"),
                            target: self,
                            action: #selector(donePressed(_:)))
        done.keyEquivalent = "\r"
        addRow([NSView(), done], fill: true)

        guard let window else {
            return
        }
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: width),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }

    private func buildClaudeCode(location: ClaudeCodeConfigLocation) {
        addHeading(String(localized: "WorkgroupBrowserNavigation.ClaudeHeading",
                          defaultValue: "Let Claude Show You What It’s Working On",
                          comment: "Heading of the Claude Code browser setup window"))
        addParagraph(String(localized: "WorkgroupBrowserNavigation.ClaudeIntroShort",
                            defaultValue: "Claude opens the issue or pull request it’s working on in a browser in the workgroup, so you can read along.",
                            comment: "One-sentence explanation of letting Claude show pages in a workgroup browser"))
        if case .remote(let remote) = location {
            // The paths below are on that host, and nothing says so otherwise.
            let host = remote.host
            addParagraph(String(localized: "WorkgroupBrowserNavigation.ClaudeOnRemoteHost",
                                defaultValue: "Claude Code runs on \(host), so the files below are the ones there.",
                                comment: "Shown in the Claude Code browser setup window when Claude runs on a remote host reached through SSH Integration. The value is the host."))
        }

        let target = ClaudeCodeBrowserNavigation.target

        // Step 1: the peer.
        if let target {
            let title = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.PeerAddedTitle",
                       defaultValue: "Browser added as “%@”",
                       comment: "Title of a completed setup step. %@ is the browser session’s name."),
                target.peerName)
            if ClaudeCodeBrowserNavigation.runningWorkgroupsMissingBrowser.isEmpty {
                addStep(number: 1, state: .done, title: title, detail: nil, content: [])
            } else {
                // Adding it changed the saved workgroup, not the one running now.
                addStep(number: 1,
                        state: .todo,
                        title: title,
                        detail: String(localized: "WorkgroupBrowserNavigation.RestartDetail",
                                       defaultValue: "Your running Claude Code workgroup doesn’t have it yet. Restarting it adds the browser; Diff and Code Review start over.",
                                       comment: "Shown after a browser was added to the saved Claude Code workgroup while one was already running"),
                        content: [buttonRow([makeButton(String(localized: "WorkgroupBrowserNavigation.RestartWorkgroup",
                                                                   defaultValue: "Restart Workgroup",
                                                                   comment: "Button that exits and re-enters the running Claude Code workgroup so it gets the new browser session"),
                                                            action: #selector(restartWorkgroupPressed(_:)))])])
            }
        } else {
            let running = !ClaudeCodeBrowserNavigation.runningWorkgroupsMissingBrowser.isEmpty
            addStep(number: 1,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.AddPeerTitle",
                                  defaultValue: "Add a browser to the workgroup",
                                  comment: "Title of a setup step: add a browser session to the Claude Code workgroup"),
                    detail: running ? String(localized: "WorkgroupBrowserNavigation.AddPeerRestartDetail",
                                             defaultValue: "Your running Claude Code workgroup restarts to get it. Diff and Code Review start over.",
                                             comment: "Shown before adding a browser to the Claude Code workgroup while it is running: adding it restarts the workgroup") : nil,
                    content: [buttonRow([makeButton(String(localized: "WorkgroupBrowserNavigation.AddBrowser",
                                                               defaultValue: "Add Browser",
                                                               comment: "Button that adds a browser session to the Claude Code workgroup"),
                                                        action: #selector(addBrowserPressed(_:)))])])
        }

        // Steps 2 and 3 are laid out in full from the start, so nothing jumps
        // around when step 1 is done. Until then they show the name the peer
        // will get, with their controls disabled.
        let shownTarget = target ?? WorkgroupBrowserNavigation.Target(
            peerName: WorkgroupBrowserNavigation.defaultPeerName,
            variablePath: WorkgroupBrowserNavigation.defaultVariablePath)
        let laterState: StepState = target == nil ? .unavailable : .todo

        // Step 2: the allow rule.
        let ruleTitle = String(localized: "WorkgroupBrowserNavigation.AllowRuleTitle",
                               defaultValue: "Let Claude open pages without asking",
                               comment: "Title of a setup step: add a Claude Code permission rule for the command that opens pages")
        let settingsPath = location.displayPath(location.settingsPath)
        let ruleButton = makeButton(String(localized: "WorkgroupBrowserNavigation.AddAllowRule",
                                           defaultValue: "Add Rule",
                                           comment: "Button that adds a permission rule to Claude Code’s settings"),
                                    action: #selector(addAllowRulePressed(_:)))
        let it2 = location.it2
        ruleButton.toolTip = WorkgroupBrowserNavigation.claudeAllowRule(for: shownTarget, it2: it2)
        let ruleDetail: String
        let ruleState: StepState
        if target != nil, allowRuleApproved {
            ruleState = .done
            ruleButton.title = Self.addedTitle
            ruleButton.isEnabled = false
            ruleDetail = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.AllowRuleAddedDetail",
                       defaultValue: "Added to %@.",
                       comment: "Detail of the completed setup step that added a Claude Code permission rule. %@ is the settings file’s path, such as ~/.claude/settings.json."),
                settingsPath)
        } else if target != nil, allowRuleFound == true {
            ruleState = .todo
            ruleDetail = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.AllowRuleAlreadyThereDetail",
                       defaultValue: "%@ already has this rule. Click Add Rule to keep it.",
                       comment: "Detail of the setup step that adds a Claude Code permission rule, when the settings file already has it. %@ is the settings file’s path, such as ~/.claude/settings.json. “Add Rule” is the button’s title."),
                settingsPath)
        } else {
            ruleState = laterState
            ruleDetail = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.AllowRulePathDetail",
                       defaultValue: "Adds one rule to %@.",
                       comment: "Detail of the setup step that adds a Claude Code permission rule. %@ is the settings file’s path, such as ~/.claude/settings.json."),
                settingsPath)
        }
        addStep(number: 2, state: ruleState, title: ruleTitle, detail: ruleDetail, content: [buttonRow([ruleButton])])

        // Step 3: the instructions.
        let instructionsTitle = String(localized: "WorkgroupBrowserNavigation.InstructionsTitle",
                                       defaultValue: "Tell Claude when to open pages",
                                       comment: "Title of a setup step: add instructions to Claude Code skills or CLAUDE.md")
        let claudeMDPath = location.displayPath(location.claudeMDPath)
        let generated = WorkgroupBrowserNavigation.agentInstructions(for: shownTarget, it2: it2)
        generatedInstructions = generated
        let code = makeCode(generated)
        instructionsTextView = code.documentView as? NSTextView
        let appendButton = makeButton(String.localizedStringWithFormat(
                                          String(localized: "WorkgroupBrowserNavigation.AppendToPath",
                                                 defaultValue: "Add to %@",
                                                 comment: "Button that appends the instructions above to the end of a file. %@ is the file’s path, such as ~/.claude/CLAUDE.md."),
                                          claudeMDPath),
                                      action: #selector(appendPressed(_:)))
        let instructionsState: StepState
        let instructionsDetail: String
        if target != nil, ClaudeCodeBrowserNavigation.instructionsAppended(generated, in: location) {
            instructionsState = .done
            appendButton.title = Self.addedTitle
            appendButton.isEnabled = false
            instructionsDetail = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.InstructionsAddedDetail",
                       defaultValue: "Added to %@.",
                       comment: "Detail of the completed setup step that added instructions for Claude. %@ is the path of the user’s global CLAUDE.md file, such as ~/.claude/CLAUDE.md."),
                claudeMDPath)
        } else {
            instructionsState = laterState
            instructionsDetail = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.InstructionsWhereDetail",
                       defaultValue: "Add this to a skill, or to %@ to use it in every project.",
                       comment: "Detail of the setup step that adds instructions for Claude. %@ is the path of the user’s global CLAUDE.md file, such as ~/.claude/CLAUDE.md."),
                claudeMDPath)
        }
        var buttons = [makeButton(Self.copyTitle, action: #selector(copyPressed(_:))), appendButton]
        // Finder can't show a folder on another host.
        if location.localSkillsURL != nil {
            buttons.append(makeButton(String(localized: "WorkgroupBrowserNavigation.ShowSkills",
                                             defaultValue: "Show Skills Folder",
                                             comment: "Button that reveals the Claude Code skills folder in Finder"),
                                      action: #selector(showSkillsPressed(_:))))
        }
        if busy {
            ruleButton.isEnabled = false
            appendButton.isEnabled = false
        }
        addStep(number: 3,
                state: instructionsState,
                title: instructionsTitle,
                detail: instructionsDetail,
                content: [code, buttonRow(buttons)])
    }

    private static var useDefaultVariableTitle: String {
        return String(localized: "WorkgroupBrowserNavigation.UseVariable",
                      defaultValue: "Use \\(user.browserURL)",
                      comment: "Button that sets the session’s URL to a user variable. \\(user.browserURL) is literal syntax and must not be translated.")
    }

    private static var copyTitle: String {
        return String(localized: "WorkgroupBrowserNavigation.Copy",
                      defaultValue: "Copy",
                      comment: "Button that copies text to the clipboard")
    }

    private static var addedTitle: String {
        return String(localized: "WorkgroupBrowserNavigation.Added",
                      defaultValue: "Added",
                      comment: "Button title after instructions were appended to a file")
    }

    private func buildWorkgroup(config: iTermWorkgroupSessionConfig,
                                useDefaultVariable: (() -> iTermWorkgroupSessionConfig?)?) {
        addHeading(String(localized: "WorkgroupBrowserNavigation.WorkgroupHeading",
                          defaultValue: "Let Other Sessions Show Pages Here",
                          comment: "Heading of the help window for driving a workgroup browser session from other sessions"))
        addParagraph(String(localized: "WorkgroupBrowserNavigation.WorkgroupIntroShort",
                            defaultValue: "An agent or script in this workgroup can open a page here by setting a variable.",
                            comment: "One-sentence explanation of driving a workgroup browser session from other sessions"))

        let name = config.displayName
        let parsed = WorkgroupBrowserURLBinding.Template.parse(config.urlString)
        // Done only when the URL is exactly one variable, as
        // WorkgroupBrowserNavigation.target(for:) requires: the command passes
        // a whole URL. Until then the command names the variable that “Use
        // \(user.browserURL)” would put there.
        let soleVariable = WorkgroupBrowserNavigation.soleVariable(in: config.urlString)
        let variablePath = soleVariable ?? WorkgroupBrowserNavigation.defaultVariablePath
        let hasVariable = soleVariable != nil
        var variablePaths = [String]()
        if case .template(let template) = parsed {
            variablePaths = template.variablePaths
        }
        // The command sets one variable, so a URL that needs several to be
        // set never forms from it.
        let hasSeveralVariables = Set(variablePaths).count > 1
        // The variable is set to a whole URL, so text around it would mangle
        // the address, like https://github.com/https://….
        let hasTextAroundVariable = !hasVariable && !hasSeveralVariables && !variablePaths.isEmpty

        // Step 1: a name.
        if name.isEmpty {
            addStep(number: 1,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.NameTodoTitle",
                                  defaultValue: "Name this session",
                                  comment: "Title of a setup step: give the browser session a name"),
                    detail: String(localized: "WorkgroupBrowserNavigation.NameTodoShortDetail",
                                   defaultValue: "Other sessions find it by name.",
                                   comment: "Detail of the setup step that names the browser session"),
                    content: [])
        } else {
            addStep(number: 1,
                    state: .done,
                    title: String.localizedStringWithFormat(
                        String(localized: "WorkgroupBrowserNavigation.NameDoneTitle",
                               defaultValue: "Named “%@”",
                               comment: "Title of a completed setup step. %@ is the browser session’s name."),
                        name),
                    detail: nil,
                    content: [])
        }

        // Step 2: a URL with a variable.
        if parsed == .invalid {
            addStep(number: 2,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.URLInvalidTitle",
                                  defaultValue: "Fix this session’s URL",
                                  comment: "Title of a setup step: the browser session’s URL uses something that isn’t allowed"),
                    detail: String(localized: "WorkgroupBrowserNavigation.URLInvalidShortDetail",
                                   defaultValue: "Only user variables are allowed, like \\(user.browserURL).",
                                   comment: "Detail of the setup step for a disallowed URL. \\(user.browserURL) is literal syntax and must not be translated."),
                    content: [])
        } else if hasSeveralVariables {
            var content = [NSView]()
            if useDefaultVariable != nil {
                content.append(buttonRow([makeButton(Self.useDefaultVariableTitle,
                                                     action: #selector(useVariablePressed(_:)))]))
            }
            addStep(number: 2,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.URLSeveralVariablesTitle",
                                  defaultValue: "Use one variable in its URL",
                                  comment: "Title of a setup step: the browser session’s URL uses more than one user variable"),
                    detail: String(localized: "WorkgroupBrowserNavigation.URLSeveralVariablesDetail",
                                   defaultValue: "The command below sets only one variable, so a URL that needs several never forms.",
                                   comment: "Detail of the setup step for a browser session URL that uses more than one user variable"),
                    content: content)
        } else if hasTextAroundVariable {
            var content = [NSView]()
            if useDefaultVariable != nil {
                content.append(buttonRow([makeButton(Self.useDefaultVariableTitle,
                                                     action: #selector(useVariablePressed(_:)))]))
            }
            addStep(number: 2,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.URLTextAroundVariableTitle",
                                  defaultValue: "Make its URL just the variable",
                                  comment: "Title of a setup step: the browser session’s URL has text before or after its user variable"),
                    detail: String(localized: "WorkgroupBrowserNavigation.URLTextAroundVariableDetail",
                                   defaultValue: "The command below sets the variable to a whole URL, so text around it would change the address.",
                                   comment: "Detail of the setup step for a browser session URL with text before or after its user variable"),
                    content: content)
        } else if hasVariable {
            addStep(number: 2,
                    state: .done,
                    title: String.localizedStringWithFormat(
                        String(localized: "WorkgroupBrowserNavigation.URLDoneTitle",
                               defaultValue: "Its URL follows %@",
                               comment: "Title of a completed setup step. %@ is a variable name such as user.browserURL."),
                        variablePath),
                    detail: nil,
                    content: [])
        } else {
            var content = [NSView]()
            if useDefaultVariable != nil {
                content.append(buttonRow([makeButton(Self.useDefaultVariableTitle,
                                                     action: #selector(useVariablePressed(_:)))]))
            }
            addStep(number: 2,
                    state: .todo,
                    title: String(localized: "WorkgroupBrowserNavigation.URLTodoShortTitle",
                                  defaultValue: "Put a variable in its URL",
                                  comment: "Title of a setup step: put a user variable in the browser session’s URL"),
                    detail: nil,
                    content: content)
        }

        // Step 3: the command.
        let target = WorkgroupBrowserNavigation.Target(
            peerName: name.isEmpty ? WorkgroupBrowserNavigation.defaultPeerName : name,
            variablePath: variablePath)
        let code = makeCode(WorkgroupBrowserNavigation.command(for: target, url: "'<URL>'"))
        instructionsTextView = code.documentView as? NSTextView
        addStep(number: 3,
                state: .todo,
                title: String(localized: "WorkgroupBrowserNavigation.CommandShortTitle",
                              defaultValue: "Run this from another session",
                              comment: "Title of a setup step: the command that shows a page in the browser session"),
                detail: nil,
                content: [code,
                          buttonRow([makeButton(Self.copyTitle,
                                                action: #selector(copyPressed(_:)))])])

        // Step 4: permissions.
        addStep(number: 4,
                state: .todo,
                title: String(localized: "WorkgroupBrowserNavigation.PermissionShortTitle",
                              defaultValue: "Allow it in your agent’s settings",
                              comment: "Title of a setup step: let an AI agent run the command without asking"),
                detail: nil,
                content: [])
    }

    // MARK: - Building blocks

    private enum StepState {
        case todo
        case done
        /// Can’t be done until an earlier step is.
        case unavailable
    }

    private static let numberBadges: [SFSymbol] = [
        .number1CircleFill, .number2CircleFill, .number3CircleFill, .number4CircleFill
    ]

    // Widths, from the outside in: the stack's insets, the step box's margins,
    // then the badge column, which everything under a step's title lines up past.
    private var innerWidth: CGFloat { width - 2 * outerMargin }
    private let outerMargin: CGFloat = 24
    private let boxMargin: CGFloat = 14
    private let badgeSize: CGFloat = 20
    private let badgeGap: CGFloat = 10
    private var stepContentWidth: CGFloat { innerWidth - 2 * boxMargin - badgeSize - badgeGap }

    private func addHeading(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(label)
    }

    private func wrappingLabel(_ text: String, font: NSFont, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.preferredMaxLayoutWidth = width
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func addParagraph(_ text: String) {
        stack.addArrangedSubview(wrappingLabel(text,
                                               font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                               width: innerWidth))
    }

    /// A faint tint that sets the cards off from the window without washing
    /// out their text. A system label color with reduced alpha came out far
    /// too light in dark mode, so the appearance is chosen explicitly.
    private static let cardFillColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(white: 1, alpha: 0.04)
        }
        return NSColor(white: 0, alpha: 0.03)
    }

    /// A step in a rounded box: a badge beside the title, then an optional
    /// line of detail and the step's own controls, indented under the title
    /// so it's clear what they belong to.
    private func addStep(number: Int, state: StepState, title: String, detail: String?, content: [NSView]) {
        let symbol: SFSymbol
        let tint: NSColor
        switch state {
        case .done:
            symbol = .checkmarkCircleFill
            tint = .systemGreen
        case .todo:
            symbol = Self.numberBadges[min(number, Self.numberBadges.count) - 1]
            tint = .controlAccentColor
        case .unavailable:
            symbol = Self.numberBadges[min(number, Self.numberBadges.count) - 1]
            tint = .secondaryLabelColor
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let badge = NSImageView(image: NSImage.it_image(forSymbolName: symbol.rawValue,
                                                        accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage())
        badge.contentTintColor = tint
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: badgeSize),
            badge.heightAnchor.constraint(equalToConstant: badgeSize),
        ])

        let titleLabel = wrappingLabel(title,
                                       font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                                       width: stepContentWidth)
        if state == .unavailable {
            titleLabel.textColor = .secondaryLabelColor
        }
        // The badge centers on the title's first line: center it on the whole
        // title would drift down if a translation wraps.
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(badge)
        header.addSubview(titleLabel)
        let firstLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: titleLabel.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)))
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: titleLabel.topAnchor, constant: firstLineHeight / 2),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: badgeGap),
            titleLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            badge.topAnchor.constraint(greaterThanOrEqualTo: header.topAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
            badge.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor),
        ])
        let tight = NSLayoutConstraint(item: header, attribute: .height, relatedBy: .equal,
                                       toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        tight.priority = .defaultLow
        tight.isActive = true

        var below = [NSView]()
        if let detail {
            let detailLabel = wrappingLabel(detail,
                                            font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                            width: stepContentWidth)
            detailLabel.textColor = .secondaryLabelColor
            below.append(detailLabel)
        }
        below.append(contentsOf: content)
        if state == .unavailable {
            content.forEach { Self.disable($0) }
        }

        var views: [NSView] = [header]
        if !below.isEmpty {
            let indented = NSStackView(views: below)
            indented.orientation = .vertical
            indented.alignment = .leading
            indented.spacing = 8
            indented.edgeInsets = NSEdgeInsets(top: 0, left: badgeSize + badgeGap, bottom: 0, right: 0)
            views.append(indented)
        }
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = Self.cardFillColor
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        box.translatesAutoresizingMaskIntoConstraints = false
        let boxContent = NSView()
        boxContent.addSubview(column)
        box.contentView = boxContent
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: boxContent.leadingAnchor, constant: boxMargin),
            column.trailingAnchor.constraint(equalTo: boxContent.trailingAnchor, constant: -boxMargin),
            column.topAnchor.constraint(equalTo: boxContent.topAnchor, constant: boxMargin),
            column.bottomAnchor.constraint(equalTo: boxContent.bottomAnchor, constant: -boxMargin),
            box.widthAnchor.constraint(equalToConstant: innerWidth),
        ])
        stack.addArrangedSubview(box)
    }

    /// Selectable monospaced text, wrapped and tall enough to show all of it.
    /// Copy gives the exact text, so wrapping a long command costs nothing.
    private func makeCode(_ text: String) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else {
            it_fatalError("scrollableTextView has no text view")
        }
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = font
        textView.string = text
        let inset: CGFloat = 8
        textView.textContainerInset = NSSize(width: inset, height: inset)
        textView.textContainer?.widthTracksTextView = true
        // Measure the string itself at the width it gets inside the bezel and
        // beside the scroller; the text view hasn't been laid out yet.
        let bezel: CGFloat = 2
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let textWidth = stepContentWidth - 2 * bezel - 2 * inset - 2 * padding - scroller
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]).height
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let textHeight = max(ceil(measured), lineHeight * 3)
        let height = min(textHeight + 2 * inset + 2 * bezel, 240)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: stepContentWidth),
            scroll.heightAnchor.constraint(equalToConstant: height),
        ])
        return scroll
    }

    private func buttonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    /// A row spanning the content width, for the Done button.
    private func addRow(_ views: [NSView], fill: Bool) {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(row)
        if fill {
            row.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
        }
    }

    /// Disables every control in `view`. Buttons dim themselves; text, which
    /// would otherwise look live, is dimmed and made unselectable.
    private static func disable(_ view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = false
        }
        if let scroll = view as? NSScrollView {
            scroll.alphaValue = 0.5
            (scroll.documentView as? NSTextView)?.isSelectable = false
            return
        }
        view.subviews.forEach { disable($0) }
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func showError(_ error: Error) {
        ClaudeCodeBrowserNavigation.showError(error, window: window)
    }

    // MARK: - Actions

    @objc private func addBrowserPressed(_ sender: Any?) {
        guard confirmRestartingSeveralWorkgroups() else {
            return
        }
        do {
            try ClaudeCodeBrowserNavigation.addBrowserPeer()
        } catch {
            showError(error)
            rebuild()
            return
        }
        // A running workgroup keeps the members it was entered with; restart
        // it so the browser is there now. The step said so before the click.
        restartWorkgroups()
    }

    // The step's text speaks of one running workgroup. Restarting more than
    // one, perhaps in other windows, ends each one's reviews, so say how many.
    private func confirmRestartingSeveralWorkgroups() -> Bool {
        let count = ClaudeCodeBrowserNavigation.runningWorkgroupsMissingBrowser.count
        guard count > 1 else {
            return true
        }
        let selection = iTermWarning.show(
            withTitle: String(localized: "WorkgroupBrowserNavigation.RestartSeveralWorkgroups",
                              defaultValue: "\(count) Claude Code workgroups are running. Each one restarts, and its Diff and Code Review start over.",
                              comment: "Confirmation before restarting several running Claude Code workgroups so they get a new browser session. The argument is how many."),
            actions: [String(localized: "WorkgroupBrowserNavigation.RestartAction",
                             defaultValue: "Restart",
                             comment: "Button that confirms restarting running workgroups"),
                      iTermLocalizedCancel()],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: String(localized: "WorkgroupBrowserNavigation.RestartSeveralHeading",
                            defaultValue: "Restart Running Workgroups?",
                            comment: "Heading of the confirmation before restarting several running Claude Code workgroups"),
            window: window)
        return selection == .kiTermWarningSelection0
    }

    private var location: ClaudeCodeConfigLocation? {
        if case .claudeCode(let location) = mode {
            return location
        }
        return nil
    }

    /// Looks at whether the settings already have the rule, for step 2's text.
    private func refreshAllowRuleFound() {
        guard let target = ClaudeCodeBrowserNavigation.target, let location else {
            return
        }
        Task { @MainActor [weak self] in
            let found = await ClaudeCodeBrowserNavigation.allowRuleInstalled(for: target, in: location)
            guard let self, !self.finished else {
                return
            }
            self.allowRuleFound = found
            self.rebuild()
        }
    }

    @objc private func restartWorkgroupPressed(_ sender: Any?) {
        guard confirmRestartingSeveralWorkgroups() else {
            return
        }
        restartWorkgroups()
    }

    private func restartWorkgroups() {
        ClaudeCodeBrowserNavigation.restartRunningWorkgroupsMissingBrowser { [weak self] failures in
            guard let self else {
                return
            }
            if failures > 0 {
                self.showError(ClaudeCodeBrowserNavigation.SetupError.restartFailed(count: failures))
            }
            self.rebuild()
            self.refreshAllowRuleFound()
        }
    }

    @objc private func addAllowRulePressed(_ sender: Any?) {
        guard !busy, let target = ClaudeCodeBrowserNavigation.target, let location else {
            return
        }
        perform { [weak self] in
            try await ClaudeCodeBrowserNavigation.installAllowRule(for: target, in: location)
            self?.allowRuleApproved = true
        }
    }

    /// Runs a step's file changes with its buttons disabled, then shows any
    /// error and the new state.
    private func perform(_ body: @escaping @MainActor () async throws -> Void) {
        busy = true
        rebuild()
        Task { @MainActor [weak self] in
            var failure: Error?
            do {
                try await body()
            } catch {
                failure = error
            }
            guard let self else {
                return
            }
            self.busy = false
            if let failure {
                self.showError(failure)
            }
            self.rebuild()
        }
    }

    @objc private func copyPressed(_ sender: Any?) {
        guard let text = instructionsTextView?.string else {
            return
        }
        if let location {
            // The text runs this it2.
            ClaudeCodeBrowserNavigation.prepareIt2(for: location)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        instructionsCopied = true
    }

    @objc private func appendPressed(_ sender: Any?) {
        guard !busy, let text = generatedInstructions, let location else {
            return
        }
        ClaudeCodeBrowserNavigation.prepareIt2(for: location)
        let path = location.displayPath(location.claudeMDPath)
        let title: String
        if case .remote(let remote) = location {
            let host = remote.host
            title = String(localized: "WorkgroupBrowserNavigation.AppendConfirmRemote",
                           defaultValue: "The instructions go at the end of \(path) on \(host), which Claude reads in every project there. Nothing else in the file changes.",
                           comment: "Confirmation before appending instructions to the global CLAUDE.md on a remote host. The values are the file’s path, such as ~/.claude/CLAUDE.md, and the host.")
        } else {
            title = String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.AppendConfirmShort",
                       defaultValue: "The instructions go at the end of %@, which Claude reads in every project. Nothing else in the file changes.",
                       comment: "Confirmation before appending instructions to the user’s global CLAUDE.md. %@ is the file’s path, such as ~/.claude/CLAUDE.md."),
                path)
        }
        let selection = iTermWarning.show(
            withTitle: title,
            actions: [String(localized: "WorkgroupBrowserNavigation.AppendAction",
                             defaultValue: "Add Instructions",
                             comment: "Button that confirms appending instructions to CLAUDE.md"),
                      iTermLocalizedCancel()],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: String.localizedStringWithFormat(
                String(localized: "WorkgroupBrowserNavigation.AppendHeading",
                       defaultValue: "Add to %@?",
                       comment: "Heading of the confirmation before appending to a file. %@ is the file name."),
                (location.claudeMDPath as NSString).lastPathComponent),
            window: window)
        guard selection == .kiTermWarningSelection0 else {
            return
        }
        perform {
            try await ClaudeCodeBrowserNavigation.appendToClaudeMD(text, in: location)
            ClaudeCodeBrowserNavigation.noteInstructionsAppended(text, in: location)
        }
    }

    @objc private func showSkillsPressed(_ sender: Any?) {
        guard let skills = location?.localSkillsURL else {
            return
        }
        if FileManager.default.fileExists(atPath: skills.path) {
            NSWorkspace.shared.activateFileViewerSelecting([skills])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([skills.deletingLastPathComponent()])
        }
    }

    @objc private func useVariablePressed(_ sender: Any?) {
        guard case .workgroup(_, let useDefaultVariable) = mode,
              let updated = useDefaultVariable?() else {
            return
        }
        mode = .workgroup(config: updated, useDefaultVariable: useDefaultVariable)
        rebuild()
    }

    @objc private func donePressed(_ sender: Any?) {
        guard let window else {
            return
        }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
        finish()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        guard !finished else {
            return
        }
        finished = true
        Self.open.removeAll { $0 === self }
        onClose?(isComplete)
    }

    /// Whether Claude will show pages: the running workgroups have the
    /// browser, the allow rule was added here, and the instructions were
    /// added to CLAUDE.md or copied (to paste into a skill, which iTerm2
    /// can't see).
    private var isComplete: Bool {
        guard let location,
              ClaudeCodeBrowserNavigation.target != nil,
              ClaudeCodeBrowserNavigation.runningWorkgroupsMissingBrowser.isEmpty,
              allowRuleApproved,
              let generatedInstructions else {
            return false
        }
        return instructionsCopied ||
            ClaudeCodeBrowserNavigation.instructionsAppended(generatedInstructions, in: location)
    }
}
