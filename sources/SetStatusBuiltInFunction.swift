//
//  SetStatusBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/12/26.
//

import Foundation

@objc(iTermSetStatusBuiltInFunction)
class SetStatusBuiltInFunction: NSObject {
}

extension SetStatusBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let statusArg = "status"
    private static let textColorArg = "text_color"
    private static let dotColorArg = "dot_color"

    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.set-status",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "set_status",
            arguments: [statusArg: NSString.self,
                      textColorArg: NSString.self,
                       dotColorArg: NSString.self],
            optionalArguments: Set([statusArg, textColorArg, dotColorArg]),
            defaultValues: ["session_id": iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: "[set_status]") { parameters, completion in
                guard let sessionID = parameters["session_id"] as? String else {
                    completion(nil, error(message: "Missing session_id"))
                    return
                }
                guard let session = iTermController.sharedInstance().session(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }

                let update = VT100TabStatusUpdate()

                if let status = parameters[statusArg] as? String {
                    update.statusPresence = .set
                    update.status = status
                }

                if let textColorHex = parameters[textColorArg] as? String {
                    var textColor = iTermSRGBColor(r: 0, g: 0, b: 0)
                    guard iTermSRGBColorFromHexString(textColorHex, &textColor) else {
                        completion(nil, error(message: "Invalid text_color (expected #rrggbb)"))
                        return
                    }
                    update.statusColorPresence = .set
                    update.statusColor = textColor
                }

                if let dotColorHex = parameters[dotColorArg] as? String {
                    var dotColor = iTermSRGBColor(r: 0, g: 0, b: 0)
                    guard iTermSRGBColorFromHexString(dotColorHex, &dotColor) else {
                        completion(nil, error(message: "Invalid dot_color (expected #rrggbb)"))
                        return
                    }
                    update.indicatorPresence = .set
                    update.indicator = dotColor
                }

                session.screenSetTabStatus(update)
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
