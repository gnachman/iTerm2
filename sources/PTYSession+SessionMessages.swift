//
//  PTYSession+SessionMessages.swift
//  iTerm2SharedARC
//
//  Created for Session Messages Customization
//

import Foundation

@objc extension PTYSession {
    
    var sessionEndMessageColor: NSColor {
        return iTermProfilePreferences.color(forKey: KEY_SESSION_END_MESSAGE_COLOR, in: profile) ?? 
            NSColor(calibratedRed: 70.0/255.0, green: 83.0/255.0, blue: 246.0/255.0, alpha: 1.0)
    }
    
    var sessionEndMessageText: String {
        return iTermProfilePreferences.string(forKey: KEY_SESSION_END_MESSAGE_TEXT, in: profile) ?? "Session Ended"
    }
    
    var sessionRestartedMessageText: String {
        return iTermProfilePreferences.string(forKey: KEY_SESSION_RESTARTED_MESSAGE_TEXT, in: profile) ?? "Session Restarted"
    }
    
    var sessionFinishedMessageText: String {
        return iTermProfilePreferences.string(forKey: KEY_SESSION_FINISHED_MESSAGE_TEXT, in: profile) ?? "Finished"
    }
}
