//
//  SVGViewController.swift
//  iTerm2
//
//  Created by George Nachman on 5/25/25.
//

import WebKit

@objc
class SVGViewController: NSViewController, WKScriptMessageHandler {
    private var webView: WKWebView!
    var html: String = "" {
        didSet {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// The SVG markup to display.
    var svgString: String? {
        didSet {
            loadSVG()
        }
    }

    override func loadView() {
        view = webView
    }

    override func viewDidLoad() {
        loadSVG()
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        let js = """
               let oldLog = console.log;
               let oldError = console.error;
               console.log = function() {
                   oldLog.apply(console, arguments);
                   window.webkit.messageHandlers.iTerm2ConsoleLog.postMessage(
                       Array.from(arguments).join(" ")
                   );
               };
               console.error = function() {
                   oldError.apply(console, arguments);
                   window.webkit.messageHandlers.iTerm2ConsoleLog.postMessage(
                       Array.from(arguments).join(" ")
                   );
               };
               return true;
           """
        let script = WKUserScript(
            source: "(function() {" + js + "})();",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "iTerm2ConsoleLog")
        configuration.userContentController.addUserScript(script)

        webView = WKWebView(frame: .zero, configuration: configuration)
    }
    
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle console.log messages separately since they come as String
        switch message.name {
        case "iTerm2ConsoleLog":
            let string = if let logMessage = message.body as? String {
                logMessage
            } else {
                message.body
            }
            NSLog("SVGViewController JS Console: \(string)")
        default:
            break
        }
    }

    private func loadSVG() {
        guard let svg = svgString else {
            return
        }

        let html = """
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        </head>
        <body style="margin:0;padding:0;">
        \(svg)
        </body>
        </html>
        """

        self.html = html
    }
}

@objc(iTermRegexVisualizationViewController)
class RegexVisualizationViewController: SVGViewController {
    private let maxSize: NSSize
    private var sizeEstimator: SVGSizeEstimator?
    private var _regex: String
    private var appearanceObservation: NSKeyValueObservation?

    @objc var regex: String {
        get {
            _regex
        }
        set {
            _regex = newValue
            reload(sync: false)
        }
    }

    @objc(initWithRegex:maxSize:)
    init(regex: String, maxSize: NSSize) {
        self.maxSize = maxSize
        self._regex = regex

        super.init(nibName: nil, bundle: nil)

        reload(sync: true)
    }

    deinit {
      appearanceObservation?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appearanceObservation = view.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] view, _ in
            self?.reload(sync: false)
        }
    }

    @objc
    private func appearanceMaybeChanged() {
        reload(sync: false)
    }

    private func reload(sync: Bool) {
        let dsl = ICURegexToRailroadConverter().convert(regex)
        let svg = dsl.withCString { dslPtr -> UnsafeMutablePointer<CChar>? in
            let cssPtr = railroad_dsl_css_for_theme(view.effectiveAppearance.it_isDark ? "dark" : "light")!
            defer {
                railroad_string_free(cssPtr)
            }
            if !railroad_dsl_is_valid(dslPtr) {
                return nil
            }
            return railroad_dsl_to_svg(dslPtr, cssPtr)
        }

        guard let svg else {
            html = """
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            </head>
            <body style="margin:0;padding:0;">
            The regular expression could not be parsed.
            </body>
            </html>
            """
            preferredContentSize = NSSize(width: 400, height: 100)
            return
        }
        svgString = String(cString: svg)
        railroad_string_free(svg)
        if sync {
            sizeEstimator = SVGSizeEstimator(html: html)
            preferredContentSize = min(maxSize, sizeEstimator!.desiredSize)
        } else {
            sizeEstimator = SVGSizeEstimator(html: html) { [weak self] size in
                guard let self = self else { return }
                self.preferredContentSize = min(self.maxSize, size)
            }
        }
    }

    @MainActor required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
}

func min(_ lhs: NSSize, _ rhs: NSSize) -> NSSize {
    return NSSize(width: min(lhs.width, rhs.width),
                  height: min(lhs.height, rhs.height))
}
