//
//  NSDictionary+Conductor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/13/22.
//

import Foundation

extension NSDictionary {
    // For Profile dictionaries.
    @objc var sshIdentity: SSHIdentity? {
        if (self[KEY_CUSTOM_COMMAND] as? String) != kProfilePreferenceCommandTypeSSHValue {
            return nil
        }
        guard let args = self[KEY_COMMAND_LINE] as? String else {
            return nil
        }
        // booleanArgs comes from parsing the output of ssh's usage string. We know this only
        // applies to the macOS ssh since it must be run locally. I guess it would be better to
        // generate this at build time and load it from a resource but I'm not up to that today.
        let parsed = ParsedSSHArguments(args, booleanArgs: "46AaCfGgKkMNnqsTtVvXxYy")
        return parsed.identity
    }
}
