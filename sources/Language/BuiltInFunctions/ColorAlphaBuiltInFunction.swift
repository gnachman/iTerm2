//
//  ColorAlphaBuiltInFunction.swift
//  iTerm2SharedARC
//
//  iterm2.with_alpha(color:, alpha:) returns a color string with the given alpha
//  applied. It lets an expression binding overlay transparency on a color that is
//  otherwise opaque, for example a palette color:
//
//    iterm2.with_alpha(color: colors.ansi.red, alpha: 0.5)
//
//  Only colors that honor alpha (the badge and cursor guide) show the effect.
//

import Foundation

@objc(iTermColorAlphaBuiltInFunction)
class ColorAlphaBuiltInFunction: NSObject {
}

extension ColorAlphaBuiltInFunction: iTermBuiltInFunctionProtocol {
    static func register() {
        let colorArg = "color"
        let alphaArg = "alpha"
        let function = iTermBuiltInFunction(
            name: "with_alpha",
            arguments: [colorArg: NSString.self, alphaArg: NSNumber.self],
            optionalArguments: [],
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: nil) { parameters, completion in
                guard let colorString = parameters[colorArg] as? String,
                      let alpha = parameters[alphaArg] as? NSNumber else {
                    completion(nil, NSError(domain: "com.iterm2.with-alpha",
                                            code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "with_alpha requires a color string and a numeric alpha"]))
                    return
                }
                guard let color = NSColor(fromHexString: colorString, allowingAlpha: true) else {
                    // The input didn't parse as a hex color (for example an empty
                    // string from a colors.* variable not yet seeded, or an X11 name).
                    // Fail loudly rather than silently returning it with no alpha
                    // applied, so the binding surfaces the problem instead of
                    // rendering opaque.
                    DLog("with_alpha: could not parse color \(colorString)")
                    completion(nil, NSError(domain: "com.iterm2.with-alpha",
                                            code: 2,
                                            userInfo: [NSLocalizedDescriptionKey: "with_alpha could not parse color “\(colorString)”"]))
                    return
                }
                let clamped = max(0.0, min(1.0, alpha.doubleValue))
                let result = color.withAlphaComponent(CGFloat(clamped))
                completion(result.hexStringWithAlpha(), nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(function, namespace: "iterm2")
    }
}
