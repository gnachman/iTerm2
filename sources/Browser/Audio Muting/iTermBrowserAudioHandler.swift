//
//  iTermBrowserAudioHandler.swift
//  iTerm2
//
//  Created by George Nachman on 8/4/25.
//

@MainActor
protocol iTermBrowserAudioHandlerDelegate: AnyObject {
    func browserAudioHandlerDidStartPlaying(_ sender: iTermBrowserAudioHandler, inFrame: WKFrameInfo)
}

@MainActor
class iTermBrowserAudioHandler {
    static let messageHandlerName = "iTerm2AudioHandler"
    private let secret: String
    weak var delegate: iTermBrowserAudioHandlerDelegate?
    var disabled = false
    var mutedFrames: [WKFrameInfo] = []

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
    }

    func javascript(world: WKContentWorld) -> String {
        switch world {
        case .page:
            return [
                iTermBrowserTemplateLoader.loadTemplate(
                    named: "monitor-play",
                    type: "js",
                    substitutions: ["SECRET": secret]),
                iTermBrowserTemplateLoader.loadTemplate(
                    named: "mute-audio",
                    type: "js",
                    substitutions: ["SECRET": secret])
            ].joined(separator: "\n")
        case .defaultClient:
            return iTermBrowserTemplateLoader.loadTemplate(
                named: "monitor-audio-context",
                type: "js",
                substitutions: ["SECRET": secret])

        default:
            it_fatalError("Unexpected world")
        }
    }

    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let secret = body["sessionSecret"] as? String,
              secret == self.secret,
              let event = body["event"] as? String else {
            return
        }

        enum Event: String {
            case play
            case pause
            case audioContextCreated
        }

        switch Event(rawValue: event) {
        case .pause: 
            DLog("[Audio Detection] Pause event - ignoring")
            return
        case .play, .audioContextCreated:
            DLog("[Audio Detection] Triggering audio handler for event: \(event)")
            if !disabled {
                delegate?.browserAudioHandlerDidStartPlaying(self, inFrame: message.frameInfo)
            }
        case .none: 
            DLog("[Audio Detection] Unknown event: \(event)")
            return
        }
    }

    func mute(_ webView: iTermBrowserWebView, frame: WKFrameInfo) async {
        do {
            _ = try await webView.safelyEvaluateJavaScript("window.iTerm2AudioMuting.mute('\(secret)');",
                                                     in: frame,
                                                     contentWorld: .page)
            mutedFrames.append(frame)
        } catch {
            DLog("\(error)")
        }
    }

    func unmute(_ webView: iTermBrowserWebView, frame: WKFrameInfo) async {
        do {
            _ = try await webView.safelyEvaluateJavaScript("window.iTerm2AudioMuting.unmute('\(secret)');",
                                                     in: frame,
                                                     contentWorld: .page)
            mutedFrames.remove(object: frame)
        } catch {
            DLog("\(error)")
        }
    }
}
