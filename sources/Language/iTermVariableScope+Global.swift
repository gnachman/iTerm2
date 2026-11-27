//
//  iTermVariableScope+Global.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

import Foundation

// The variables every global scope exposes: the app's process ID, the host
// name, the effective theme and the bundle path.
@objc(iTermGlobalScope)
protocol iTermGlobalScope: NSObjectProtocol {
    var applicationPID: NSNumber? { get set }
    var localhostName: String? { get set }
    var effectiveTheme: String? { get set }
    var appBundlePath: String? { get set }
}

extension iTermVariableScope: iTermGlobalScope {
    // Returns a new scope whose unnamed frame is the app's global variables.
    @objc
    class func globalsScope() -> iTermVariableScope & iTermGlobalScope {
        let scope = iTermVariableScope()
        scope.add(iTermVariables.globalInstance(), toScopeNamed: nil)
        return scope
    }

    @objc var applicationPID: NSNumber? {
        get {
            return value(forVariableName: iTermVariableKeyApplicationPID) as? NSNumber
        }
        set {
            setValue(newValue, forVariableNamed: iTermVariableKeyApplicationPID)
        }
    }

    @objc var localhostName: String? {
        get {
            return value(forVariableName: iTermVariableKeyApplicationLocalhostName) as? String
        }
        set {
            setValue(newValue, forVariableNamed: iTermVariableKeyApplicationLocalhostName)
        }
    }

    @objc var effectiveTheme: String? {
        get {
            return value(forVariableName: iTermVariableKeyApplicationEffectiveTheme) as? String
        }
        set {
            setValue(newValue, forVariableNamed: iTermVariableKeyApplicationEffectiveTheme)
        }
    }

    @objc var appBundlePath: String? {
        get {
            return value(forVariableName: iTermVariableKeyApplicationBundlePath) as? String
        }
        set {
            setValue(newValue, forVariableNamed: iTermVariableKeyApplicationBundlePath)
        }
    }
}
