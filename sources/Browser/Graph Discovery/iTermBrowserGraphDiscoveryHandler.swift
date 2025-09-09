import WebKit

@MainActor
class iTermBrowserGraphDiscoveryHandler {
    static let messageHandlerName = "iTermGraphDiscovery"
    private var frames = [String: WKFrameInfo]()
    let world = WKContentWorld.defaultClient

    var javascript: String {
        iTermBrowserTemplateLoader.loadTemplate(
            named: "graph-discovery",
            type: "js",
            substitutions: [:])
    }

    func willNavigate() {
        frames = [:]
    }

    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) {
        DLog("[IFD] NATIVE - got a message: \(message.body)")
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "REGISTER_FRAME":
            if let frameID = body["frameId"] as? String {
                DLog("[IFD] NATIVE - register frame \(frameID)")
                frames[frameID] = message.frameInfo
            }

        case "REQUEST_REPORT":
            // JS now supplies requestId; if missing, synthesize one so we don't stall.
            let requestId = (body["requestId"] as? String) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            requestReport(webView: webView, requestId: requestId)

        case "EVAL_IN_FRAME":
            guard let target = body["target"] as? String,
                  let sender = body["sender"] as? String,
                  let senderFrame = frames[sender],
                  let requestID = body["requestID"] as? String,
                  let code = body["code"] as? String else {
                return
            }
            guard let targetFrame = frames[target] else {
                Task {
                    await sendEvalResponse(webView: webView,
                                           to: senderFrame,
                                           requestID: requestID,
                                           value: nil)
                }
                return
            }
            Task {
                // Wrap and stringify result to ensure a String crosses the bridge.
                let value = await self.eval(webView: webView,
                                            frameInfo: targetFrame,
                                            code: code)
                await sendEvalResponse(webView: webView,
                                       to: senderFrame,
                                       requestID: requestID,
                                       value: value)
            }

        case "DOM_CHANGED":
            Task {
                _ = await self.eval(webView: webView,
                                    frameInfo: nil,
                                    code: "window[Symbol.for('iTermGraphDiscovery')].rediscover();")
            }

        default:
            break
        }
    }

    private func sendEvalResponse(webView: iTermBrowserWebView,
                                  to frameInfo: WKFrameInfo,
                                  requestID: String,
                                  value: String?) async {
        // Build a direct call with JSON-literal args.
        let encodedRequestID = (try? JSONEncoder().encode(requestID))?.lossyString ?? "\"\""
        let encodedValue = value ?? "null"

        let js = """
        window[Symbol.for('iTermGraphDiscovery')].handleEvalResponse(\(encodedRequestID), \(encodedValue));
        """

        _ = await self.eval(webView: webView,
                            frameInfo: frameInfo,
                            code: js)
    }

    private func requestReport(webView: iTermBrowserWebView, requestId: String) {
        Task {
            let encodedRequestID = (try? JSONEncoder().encode(requestId))?.lossyString ?? "\"\""

            let frameIDs = frames.keys

            // Phase 1: prepare
            await withTaskGroup(of: Void.self) { group in
                let code = "window[Symbol.for('iTermGraphDiscovery')].prepareForReport(\(encodedRequestID))"
                for frameID in frameIDs {
                    group.addTask {
                        await self.eval(webView: webView, frameID: frameID, code: code)
                    }
                }
            }

            // Phase 2: report
            await withTaskGroup(of: Void.self) { group in
                let code = "window[Symbol.for('iTermGraphDiscovery')].report(\(encodedRequestID))"
                for frameID in frameIDs {
                    group.addTask {
                        await self.eval(webView: webView, frameID: frameID, code: code)
                    }
                }
            }
        }
    }

    private func eval(webView: iTermBrowserWebView, frameID: String, code: String) async {
        guard let frameInfo = frames[frameID] else {
            DLog("[IFD] No such frame \(frameID)")
            return
        }
        _ = await eval(webView: webView, frameInfo: frameInfo, code: code)
    }

    private func eval(webView: iTermBrowserWebView, frameInfo: WKFrameInfo?, code: String) async -> String? {
        do {
            let wrapped = """
            (() => { 
                try { 
                    const raw = \(code);
                    const value = JSON.stringify(raw); 
                    return value;
                } catch (e) { 
                    console.error("[eval] Eval failed", e.toString(), e);
                    return null;
                } 
            })()
            """
            let result = try await webView.evaluateJavaScript(
                wrapped,
                in: frameInfo,
                contentWorld: world) as? String
            return result
        } catch {
            DLog("[IFD] eval error: \(error)")
            return nil
        }
    }
}
