//
//  DateFormatter+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 5/27/25.
//

private var cachedDateFormatters = MutableAtomicObject([String: DateFormatter]())

@objc
extension DateFormatter {
    @objc static func cacheableFormatter(template: String) -> DateFormatter {
        return cachedDateFormatters.mutableAccess { dict in
            if let value = dict[template] {
                return value
            }
            let dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: NSLocale.current)
            let formatter = DateFormatter()
            formatter.dateFormat = dateFormat
            dict[template] = formatter
            return formatter
        }
    }
}
