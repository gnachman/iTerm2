//
//  SVGViewController.swift
//  iTerm2
//
//  Created by George Nachman on 5/25/25.
//

import WebKit

@objc
class SVGViewController: NSViewController {
    private let webView = WKWebView(frame: .zero)
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
                self?.preferredContentSize = size
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
