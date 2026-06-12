//
//  SVGSizeEstimator.swift
//  iTerm2
//
//  Created by George Nachman on 5/25/25.
//

import WebKit

class SVGSizeEstimator: NSObject, WKNavigationDelegate {
    private let webView = WKWebView(frame: .zero)
    private let js = """
    /**
     * Compute the outer window size (in CSS pixels) that you should pass
     * to window.open() so that:
     *  1. A root-level <svg> in <body> will fill the viewport exactly, and
     *  2. CSS “14px monospace” text will render at 14 points tall.
     */
    function getSvgWindowSize() {
      // 1. Grab the root <svg>
      const svg = document.querySelector('body > svg');
      if (!svg) {
        throw new Error('No root-level SVG found in <body>');
      }

      // 2. Determine its intrinsic width/height in SVG user units
      let svgW, svgH;
      const wAttr = svg.getAttribute('width');
      const hAttr = svg.getAttribute('height');
      if (wAttr !== null && hAttr !== null) {
        svgW = parseFloat(wAttr);
        svgH = parseFloat(hAttr);
      } else if (svg.viewBox && svg.viewBox.baseVal) {
        svgW = svg.viewBox.baseVal.width;
        svgH = svg.viewBox.baseVal.height;
      } else {
        const bb = svg.getBBox();
        svgW = bb.width;
        svgH = bb.height;
      }

      // 3. Measure how many CSS px equal one point on this device/screen
      const ruler = document.createElement('div');
      ruler.style.position = 'absolute';
      ruler.style.top = '-9999px';
      ruler.style.height = '1pt';
      document.body.appendChild(ruler);
      const pxPerPt = ruler.offsetHeight;
      document.body.removeChild(ruler);

      // 4. Compute the required innerWidth/innerHeight so that
      //    1 SVG user unit = pxPerPt CSS px, hence CSS “14px” = 14pt
      const targetInnerW = Math.round(svgW * pxPerPt);
      const targetInnerH = Math.round(svgH * pxPerPt);

      return [
          targetInnerW,
          targetInnerH
      ];
    }

    // Example usage:
    // const {width, height} = getSvgWindowSize();
    // window.open('mySvgPage.html', 'svgWin', `width=${width},height=${height}`);
    """
    init(html: String, callback: ((NSSize) -> ())? = nil) {
        self.onDesiredSize = callback
        super.init()
        webView.loadHTMLString(html, baseURL: nil)
        webView.navigationDelegate = self
    }

    private var _desiredSize: NSSize?
    var desiredSize: NSSize {
        DLog("desiredSize called")
        while _desiredSize == nil {
            DLog("spin")
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        DLog("spinloop finished, return \(_desiredSize!)")
        return _desiredSize!
    }

    var onDesiredSize: ((NSSize) -> ())?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = js + "\ngetSvgWindowSize();"
        DLog("did finish navigation")
        webView.evaluateJavaScript(script) { [self] result, error in
            if let error = error {
                print("JavaScript error: \(error)")
                _desiredSize = NSSize(width: 400, height: 400)
                return
            }
            DLog("JavaScript result=\(String(describing: result))")
            guard let array = result as? [Double], array.count == 2 else {
                _desiredSize = NSSize(width: 400, height: 400)
                return
            }
            let w = array[0]
            let h = array[1]

            let resultSize = NSSize(width: CGFloat(w), height: CGFloat(h))
            print("result size is \(resultSize), do dispatch to main")
            DispatchQueue.main.async { [self] in
                DLog("Main thread setting desired size \(resultSize)")
                _desiredSize = resultSize
                if let callback = onDesiredSize {
                    onDesiredSize = nil
                    callback(resultSize)
                }
            }
        }
    }

    func wait() {

    }
}
