//
//  ChatIconGenerator.swift
//  iTerm2
//
//  Created by George Nachman on 6/10/25.
//
//  Generates a small square icon for a chat by asking the configured AI
//  model to draw an SVG for the chat's title, then rasterizing it. The
//  result is delivered as PNG data sized for the chat list, or nil when
//  generation fails so the caller can clear any icon left over from a
//  previous title. Requests silently do nothing when generative AI is
//  disabled; chats with no stored icon show a default icon.
//

import AppKit

class ChatIconGenerator {
    static let instance = ChatIconGenerator()

    // Pixel side length of the stored icon. The chat list displays it at
    // 32pt, so 128px leaves headroom for retina displays.
    static let pixelSideLength = 128

    // Per-chat request state, purely for coalescing. An entry exists
    // exactly while a generation is under way, from template evaluation
    // through the model round trip. If a request arrives while one is
    // running (e.g., the title changed again before the first one
    // finished), the newest request parks in `pending` and runs when the
    // current one completes, so the icon always reflects the latest
    // title. (Keeping the conversation alive is handled by
    // AIConversation.completeOneShot, not here.)
    private struct Request {
        var pending: (title: String, completion: (Data?) -> Void)?
    }
    // Main-thread only; enforced with dispatchPrecondition rather than
    // @MainActor because the calling stack (ChatListModel and its users)
    // is main-thread-by-convention, not actor-annotated, and the
    // deployment target predates MainActor.assumeIsolated.
    private var requests = [String: Request]()

    // Call on the main thread. The completion runs on the main thread
    // with the generated PNG, or nil when generation fails, so the
    // caller can decide what a failure means for any existing icon. It
    // is not called at all when the request never starts (generative AI
    // disabled, blank title) or when a newer title supersedes this one.
    func requestIcon(forChatID chatID: String,
                     title: String,
                     completion: @escaping (Data?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if requests[chatID] != nil {
            // Park before any other guard, even for a blank title or
            // with AI freshly disabled: the new title supersedes the
            // running request, whose result must not be persisted for a
            // title the chat no longer has. When the parked request
            // re-enters below, the guards drop it without starting a
            // generation.
            requests[chatID]!.pending = (title: trimmed, completion: completion)
            return
        }
        guard iTermAITermGatekeeper.allowed else {
            return
        }
        if trimmed.isEmpty {
            return
        }
        requests[chatID] = Request()
        let template = iTermPreferences.string(forKey: kPreferenceKeyAIPromptChatIcon) ?? ""
        Self.evaluatePromptTemplate(template, subject: trimmed) { [weak self] prompt in
            if prompt.isEmpty {
                DLog("Chat icon prompt template evaluated to an empty string")
                self?.finish(chatID: chatID, data: nil, completion: completion)
                return
            }
            self?.requestSVG(chatID: chatID,
                             prompt: prompt,
                             subject: trimmed,
                             completion: completion)
        }
    }

    private func requestSVG(chatID: String,
                            prompt: String,
                            subject: String,
                            completion: @escaping (Data?) -> Void) {
        var conversation = AIConversation(
            registrationProvider: nil,
            messages: [AITermController.Message(role: .user, content: prompt)])
        conversation.shouldThink = false
        // The callback can run synchronously (e.g., when no registration
        // exists); finish is deferred to the next runloop turn so the
        // bookkeeping in `requests` never mutates re-entrantly.
        AIConversation.completeOneShot(conversation) { [weak self] (result: Result<AIConversation, Error>) in
            switch result {
            case .success(let updated):
                let reply = updated.messages.last?.body.content ?? ""
                // Extract, parse, rasterize, and encode off the main
                // thread: a reply can be token-limit-sized, and even the
                // extraction scan over megabytes of untrusted text costs
                // enough to stall the UI.
                DispatchQueue.global(qos: .utility).async {
                    // Try candidates in order until one rasterizes: a
                    // balanced prose pair before the document (e.g.
                    // “wrapped in <svg>...</svg> tags:”) extracts first
                    // but fails to produce a usable image, and the real
                    // document behind it must still win.
                    var data: Data?
                    for svg in Self.extractSVGCandidates(from: reply) {
                        if let svgData = svg.data(using: .utf8),
                           let png = Self.rasterizeIconPNG(svgData: svgData, subject: subject) {
                            data = png
                            break
                        }
                    }
                    if data == nil {
                        DLog("Chat icon generation for \u{201C}\(subject)\u{201D} got a reply with no renderable SVG: \(reply)")
                    }
                    DispatchQueue.main.async {
                        self?.finish(chatID: chatID, data: data, completion: completion)
                    }
                }
            case .failure(let error):
                RLog("Chat icon generation for \u{201C}\(subject)\u{201D} failed: \(error)")
                DispatchQueue.main.async {
                    self?.finish(chatID: chatID, data: nil, completion: completion)
                }
            }
        }
    }

    private func finish(chatID: String, data: Data?, completion: (Data?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let request = requests.removeValue(forKey: chatID) else {
            return
        }
        if let (title, pendingCompletion) = request.pending {
            // A newer title arrived while this request ran. Drop this
            // result rather than persisting an icon for a superseded
            // title, and generate for the newest title instead.
            requestIcon(forChatID: chatID, title: title, completion: pendingCompletion)
            return
        }
        completion(data)
    }

    // MARK: - Prompt template

    // The template lives in Settings > General > AI > Prompts (Chat List
    // Icon) and is an interpolated string; the chat's title is exposed to
    // it as \(ai.subject), like \(ai.prompt) in the Engage AI prompt.
    // Evaluation is asynchronous so templates may call registered
    // functions. Internal rather than private so tests can verify the
    // substitution.
    static func evaluatePromptTemplate(_ template: String,
                                       subject: String,
                                       completion: @escaping (String) -> Void) {
        AIPromptTemplateEvaluator.evaluate(template,
                                           variables: [iTermAIPromptVariableSubject: subject],
                                           synchronous: false) { value in
            completion(value ?? "")
        }
    }

    // MARK: - SVG rasterization

    // Models sometimes disobey and wrap the SVG in fences or prose, so
    // extract the outermost <svg>...</svg> span rather than parsing the
    // whole reply. The string is tokenized in one forward pass; the
    // candidate loop then works on the token array, so a pathological
    // reply (token-limit-sized, dense with unbalanced "<svg" mentions)
    // costs one linear scan plus quadratic work in the token COUNT, not
    // repeated substring searches over megabytes of text. Candidates
    // that never balance (e.g. prose before the document mentioning
    // "<svg>") are skipped; a bare self-closing <svg/> only wins as a
    // last resort so a prose mention of it can't preempt a real document
    // later in the reply. An opening token must be followed by
    // whitespace, ">", or "/" so words like <svgfoo> don't count, and
    // self-closing <svg .../> elements don't change nesting depth. A
    // backwards search for the last </svg> is wrong here: prose after
    // the document mentioning the tag would extend the span, producing
    // bytes CoreSVG rejects. Internal rather than private so tests can
    // pin the extraction cases.
    static func extractSVG(from response: String) -> String? {
        return extractSVGCandidates(from: response).first
    }

    // Bounds on extraction work. A real icon reply has a handful of
    // tokens; these caps only bite on pathological output (e.g. a
    // token-limit-sized reply stuffed with unbalanced "<svg") where the
    // candidate loop's quadratic-in-token-count work would otherwise pin
    // a core for seconds.
    private static let maxSVGTokens = 512
    private static let maxSVGCandidates = 8

    // All balanced candidate documents in reply order; rasterization
    // tries them until one renders. A bare self-closing <svg/> is
    // appended only when nothing else balanced, so a prose mention of it
    // can't preempt a real document.
    static func extractSVGCandidates(from response: String) -> [String] {
        let tokens = svgTokens(in: response)
        var results = [String]()
        var selfClosingFallback: Range<String.Index>?
        for (i, candidate) in tokens.enumerated() {
            if results.count >= maxSVGCandidates {
                break
            }
            switch candidate.kind {
            case .close:
                continue
            case .selfClosed:
                if selfClosingFallback == nil {
                    selfClosingFallback = candidate.start..<candidate.end
                }
            case .open:
                var depth = 1
                scan: for token in tokens[(i + 1)...] {
                    switch token.kind {
                    case .open:
                        depth += 1
                    case .selfClosed:
                        break
                    case .close:
                        depth -= 1
                        if depth == 0 {
                            results.append(String(response[candidate.start..<token.end]))
                            break scan
                        }
                    }
                }
                // If it never balances, try the next candidate.
            }
        }
        if results.isEmpty, let selfClosingFallback {
            results.append(String(response[selfClosingFallback]))
        }
        return results
    }

    private struct SVGToken {
        enum Kind {
            case open        // <svg ...>
            case selfClosed  // <svg .../>
            case close       // </svg ...>
        }
        let kind: Kind
        let start: String.Index  // the "<"
        let end: String.Index    // just past the closing ">"
    }

    // Single forward scan. The next match of each token type is cached
    // and only re-searched from a later position, so total search cost
    // is linear even when one token type stops occurring (the case that
    // made a per-iteration tail re-search quadratic).
    private static func svgTokens(in s: String) -> [SVGToken] {
        var tokens = [SVGToken]()
        var cursor = s.startIndex

        func find(_ needle: String, from index: String.Index) -> Range<String.Index>? {
            s.range(of: needle, options: .caseInsensitive, range: index..<s.endIndex)
        }
        var nextOpen = find("<svg", from: cursor)
        var nextClose = find("</svg", from: cursor)

        while cursor < s.endIndex, tokens.count < maxSVGTokens {
            if let stale = nextOpen, stale.lowerBound < cursor {
                nextOpen = find("<svg", from: cursor)
            }
            if let stale = nextClose, stale.lowerBound < cursor {
                nextClose = find("</svg", from: cursor)
            }
            let isOpen: Bool
            let token: Range<String.Index>
            if let open = nextOpen, nextClose == nil || open.lowerBound < nextClose!.lowerBound {
                isOpen = true
                token = open
            } else if let close = nextClose {
                isOpen = false
                token = close
            } else {
                break
            }
            guard token.upperBound < s.endIndex else {
                break
            }
            let following = s[token.upperBound]
            if isOpen {
                guard following == ">" || following == "/" || following.isWhitespace else {
                    // A word like <svgfoo>, not an opening tag.
                    cursor = token.upperBound
                    continue
                }
            } else {
                guard following == ">" || following.isWhitespace else {
                    // A tag like </svgText> or </svg:svg>, not our close.
                    // Without this guard, depth would hit zero early and
                    // the extracted span would end mid-document.
                    cursor = token.upperBound
                    continue
                }
            }
            // Find the end of the tag. For opens this also reveals
            // whether it self-closes. (A ">" inside a quoted attribute
            // value would fool this; not worth a full parser for model
            // output.)
            guard let tagEnd = find(">", from: token.upperBound) else {
                break
            }
            let kind: SVGToken.Kind
            if !isOpen {
                kind = .close
            } else if tagEnd.lowerBound > token.upperBound,
                      s[s.index(before: tagEnd.lowerBound)] == "/" {
                kind = .selfClosed
            } else {
                kind = .open
            }
            tokens.append(SVGToken(kind: kind, start: token.lowerBound, end: tagEnd.upperBound))
            cursor = tagEnd.upperBound
        }
        return tokens
    }

    // Off-main. Decodes the SVG through the sandboxed worker first, the
    // same path every other source of untrusted image bytes uses, so a
    // CoreSVG parser bug triggered by adversarial model output doesn't
    // run unsandboxed in this process. The in-process vector draw below
    // only runs on bytes that survived that gate, and gives a crisp
    // 128px raster instead of scaling the worker's pre-rasterized
    // bitmap. It must use the same fixedSVGData repair the worker
    // applies: without it, _NSSVGImageRep silently drops <use> content
    // referenced through a <g> inside <defs> and the (non-nil, blank)
    // in-process image would beat the correct worker bitmap. The worker
    // bitmap is the fallback whenever the in-process decode fails OR
    // reports no size (realistic for viewBox-only documents).
    private static func rasterizeIconPNG(svgData: Data, subject: String) -> Data? {
        guard let decoded = iTermImage(compressedData: svgData),
              let workerBitmap = decoded.images.firstObject as? NSImage,
              workerBitmap.size.width > 0,
              workerBitmap.size.height > 0 else {
            DLog("Sandboxed decode rejected SVG for \u{201C}\(subject)\u{201D}")
            return nil
        }
        let image: NSImage
        if let vector = NSImage(data: iTermImage.fixedSVGData(svgData)),
           vector.size.width > 0,
           vector.size.height > 0 {
            image = vector
        } else {
            image = workerBitmap
        }
        return downscaledPNG(of: image)
    }

    private static func downscaledPNG(of image: NSImage) -> Data? {
        let side = pixelSideLength
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: side,
                                            pixelsHigh: side,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        // Aspect-fill the square destination; a well-behaved reply has a
        // square viewBox, in which case this is a plain scale.
        let imageSize = image.size
        let scale = max(CGFloat(side) / imageSize.width,
                        CGFloat(side) / imageSize.height)
        let scaledSize = NSSize(width: imageSize.width * scale,
                                height: imageSize.height * scale)
        let origin = NSPoint(x: (CGFloat(side) - scaledSize.width) / 2,
                             y: (CGFloat(side) - scaledSize.height) / 2)
        image.draw(in: NSRect(origin: origin, size: scaledSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1)
        context.flushGraphics()

        return bitmap.representation(using: .png, properties: [:])
    }
}
