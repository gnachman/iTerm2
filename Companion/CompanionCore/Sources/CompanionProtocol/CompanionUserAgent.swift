//
//  CompanionUserAgent.swift
//  CompanionCore
//
//  A fixed User-Agent for every outbound relay/push request. The default
//  URLSession User-Agent encodes the app name, build number, and the
//  CFNetwork/Darwin versions (i.e. the exact OS version), which would leak to
//  the relay and let it fingerprint or correlate a user across requests. This
//  value is constant across users and versions, so it carries no such metadata.
//

public enum CompanionUserAgent {
    public static let value = "iTerm2Companion"
}
