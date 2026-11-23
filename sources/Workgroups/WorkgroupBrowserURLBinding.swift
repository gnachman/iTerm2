//
//  WorkgroupBrowserURLBinding.swift
//  iTerm2
//
//  Lets a workgroup browser session follow user variables.
//

import Foundation

/// A workgroup browser session's URL can name user variables, as in
/// `\(user.reviewURL)` or `https://github.com/\(user.reviewPath)`. The browser
/// navigates whenever the evaluated URL changes, so an agent in another member
/// can show a page by running `it2 session set-var --peer-name Browser user.reviewURL URL`.
///
/// Anything that can write a user variable can drive the browser, which has the
/// user’s cookies and sign-ins. The template language is kept deliberately small
/// to limit what that means:
/// - Only `\(user.NAME)` substitutions. No other namespaces, so a shared workgroup
///   can’t send session state (paths, host names) off the machine, and no function
///   calls. Values are inserted as text and never evaluated.
/// - The result must be an http or https URL with a host. The URL bar accepts more
///   (internal schemes, file URLs), which a variable must not reach.
/// - A template whose fixed prefix includes the slash after the host pins the
///   origin, since the value can then only become part of the path.
final class WorkgroupBrowserURLBinding {
    struct Template: Equatable {
        enum Piece: Equatable {
            case literal(String)
            /// A full variable path, such as `user.reviewURL`.
            case variable(String)
        }

        enum ParseResult: Equatable {
            /// No substitutions; the string is an ordinary URL.
            case plain
            case template(Template)
            /// Contains a substitution other than `\(user.NAME)`.
            case invalid
        }

        let pieces: [Piece]

        var variablePaths: [String] {
            return pieces.compactMap { piece in
                if case .variable(let path) = piece {
                    return path
                }
                return nil
            }
        }

        private static let substitutionStart = "\\("

        // A user variable a template can name. set_workgroup_member_variable
        // accepts only these, so a value is never set that no URL could follow.
        private static let userVariablePattern = #"user\.[A-Za-z_][A-Za-z0-9_]*"#

        private static let regex: NSRegularExpression = {
            do {
                return try NSRegularExpression(
                    pattern: #"\\\(\s*("# + userVariablePattern + #")\s*\)"#)
            } catch {
                it_fatalError("Bad regex: \(error)")
            }
        }()

        private static let userVariableRegex: NSRegularExpression = {
            do {
                return try NSRegularExpression(pattern: "^" + userVariablePattern + "$")
            } catch {
                it_fatalError("Bad regex: \(error)")
            }
        }()

        /// Whether `path` is a user variable a template can name, like user.browserURL.
        static func isUserVariablePath(_ path: String) -> Bool {
            let range = NSRange(location: 0, length: (path as NSString).length)
            return userVariableRegex.firstMatch(in: path, range: range) != nil
        }

        static func isTemplate(_ string: String) -> Bool {
            return string.contains(substitutionStart)
        }

        static func parse(_ string: String) -> ParseResult {
            guard isTemplate(string) else {
                return .plain
            }
            let nsString = string as NSString
            var pieces = [Piece]()
            var location = 0
            func appendLiteral(upTo end: Int) -> Bool {
                guard end > location else {
                    return true
                }
                let literal = nsString.substring(with: NSRange(location: location, length: end - location))
                if literal.contains(substitutionStart) {
                    return false
                }
                pieces.append(.literal(literal))
                return true
            }
            for match in regex.matches(in: string, range: NSRange(location: 0, length: nsString.length)) {
                guard appendLiteral(upTo: match.range.location) else {
                    return .invalid
                }
                pieces.append(.variable(nsString.substring(with: match.range(at: 1))))
                location = match.range.location + match.range.length
            }
            guard appendLiteral(upTo: nsString.length) else {
                return .invalid
            }
            return .template(Template(pieces: pieces))
        }

        /// The URL this template names given the variables’ values, or nil if a
        /// variable is unset or empty or the result isn’t an acceptable URL.
        func evaluate(_ lookup: (String) -> String?) -> URL? {
            var result = ""
            for piece in pieces {
                switch piece {
                case .literal(let literal):
                    result += literal
                case .variable(let path):
                    guard let value = lookup(path), !value.isEmpty else {
                        return nil
                    }
                    result += value
                }
            }
            return Self.acceptableURL(result)
        }

        static func acceptableURL(_ string: String) -> URL? {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host,
                  !host.isEmpty else {
                return nil
            }
            return url
        }
    }

    private weak var session: PTYSession?
    private let template: Template
    private var references = [iTermVariableReference<AnyObject>]()
    // The last URL the binding produced. Navigation happens only when this
    // changes, so rewriting the same value leaves the user on whatever page
    // they clicked through to.
    private var lastApplied: String?
    // While changingTogether() writes several variables, the URL they form
    // partway through is neither the old page nor the new one.
    private var restoring = false

    /// Loads a URL in the session, returning whether it started loading. A
    /// test replaces it, since a test's session has no browser view.
    var open: (PTYSession, URL) -> Bool = { session, url in
        session.open(url: url)
    }

    /// Called after the binding navigates, with the variables that produced
    /// the page, so it can be shown again later (see WorkgroupBrowserMemory).
    var didNavigate: (([String: String]) -> Void)?

    /// The current value of each variable the template names, when every one
    /// is set and together they form an acceptable URL.
    var values: [String: String]? {
        guard currentURL() != nil, let scope = session?.genericScope else {
            return nil
        }
        var result = [String: String]()
        for path in template.variablePaths {
            result[path] = scope.stringValue(forVariableName: path)
        }
        return result
    }

    var hasPage: Bool {
        return currentURL() != nil
    }

    /// Sets the template's variables to `values`, as an agent would, which
    /// navigates if the URL they form differs from the last one shown. Paths
    /// the template doesn’t name are ignored, and so are values that don’t
    /// form an acceptable URL.
    func restore(_ values: [String: String]) {
        guard let scope = session?.genericScope else {
            return
        }
        let paths = template.variablePaths
        guard paths.allSatisfy({ values[$0] != nil }),
              template.evaluate({ values[$0] }) != nil else {
            DLog("WorkgroupBrowserURLBinding: not restoring values that don't form an acceptable URL")
            return
        }
        changingTogether {
            for path in Set(paths) {
                scope.setValue(values[path], forVariableNamed: path)
            }
        }
    }

    /// Runs `body`, which sets several variables, and then follows them once,
    /// so the browser never visits a URL formed from some new values and some
    /// old ones.
    func changingTogether(_ body: () -> Void) {
        restoring = true
        body()
        restoring = false
        variableDidChange()
    }

    /// Returns nil when `urlString` has no substitutions or is not a valid template.
    init?(urlString: String, session: PTYSession) {
        switch Template.parse(urlString) {
        case .plain:
            return nil
        case .invalid:
            RLog("WorkgroupBrowserURLBinding: not binding session \(session.guid) because its URL template uses something other than \\(user.NAME)")
            return nil
        case .template(let template):
            self.template = template
        }
        self.session = session
        // Whatever the variables say now is already reflected in the page: a
        // fresh session has no user variables yet, and a restored one restored
        // its own page. Only later changes navigate.
        lastApplied = currentURL()?.absoluteString
        for path in Set(template.variablePaths) {
            let ref = iTermVariableReference<AnyObject>(path: path, vendor: session.genericScope)
            // Set after creation so it doesn't fire for the current value.
            ref.onChangeBlock = { [weak self] in
                self?.variableDidChange()
            }
            references.append(ref)
        }
        DLog("WorkgroupBrowserURLBinding: bound session \(session.guid) to \(template.variablePaths); initial value \(lastApplied.d)")
    }

    /// Stops following the variables. Not iTermVariableReference.invalidate(),
    /// which relinks the reference and reports a change. The scope holds
    /// references weakly, so dropping them detaches them.
    func invalidate() {
        for ref in references {
            ref.onChangeBlock = nil
        }
        references.removeAll()
        didNavigate = nil
    }

    private func currentURL() -> URL? {
        guard let scope = session?.genericScope else {
            return nil
        }
        return template.evaluate { path in
            scope.stringValue(forVariableName: path)
        }
    }

    private func variableDidChange() {
        guard !restoring, let session else {
            return
        }
        // An unset or rejected value leaves the page alone rather than blanking it.
        guard let url = currentURL() else {
            DLog("WorkgroupBrowserURLBinding: session \(session.guid) variables changed but don't form an acceptable URL")
            return
        }
        let string = url.absoluteString
        guard string != lastApplied else {
            return
        }
        RLog("WorkgroupBrowserURLBinding: navigating session \(session.guid) to a bound URL")
        // Only a page that loads counts: one refused (the view isn't a
        // browser, or not yet) isn't remembered, and setting the same value
        // again tries again.
        guard open(session, url) else {
            return
        }
        lastApplied = string
        if let values {
            didNavigate?(values)
        }
    }
}

extension iTermWorkgroupSessionConfig {
    /// The URL a browser member should start at. A template starts blank,
    /// since its variables can’t be set yet. Not the profile’s initial URL:
    /// that is usually the welcome page, which turns into browser onboarding
    /// in a member that exists only to show what an agent opens.
    var initialURLString: String {
        // Localization unneeded: a URL.
        // An invalid template isn't bound, so it loads as typed, as it always did.
        if case .template = WorkgroupBrowserURLBinding.Template.parse(urlString) {
            return "about:blank"
        }
        return urlString
    }
}
