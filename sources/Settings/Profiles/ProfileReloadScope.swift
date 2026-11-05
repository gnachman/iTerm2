//
//  ProfileReloadScope.swift
//  iTerm2SharedARC
//
//  When a session's profile changes, PTYSession reloads itself from the new profile. The full
//  reload (reallySetPreferencesFromAddressBookEntry:) reapplies every setting and is expensive:
//  it rebuilds the font table, relayouts views, recreates the status bar, and so on. Escape
//  sequences that change colors (OSC 4/10/11/12/112, etc.) rewrite the profile too, and a
//  program like tmux can emit several per second. See issue 13192.
//
//  This file holds the hand-maintained map from profile key to the scope of work needed when
//  that key changes. A key in the colors scope is read, during a reload, only by
//  -[PTYSession reloadColorsFromProfile:], so a change to it needs only the colors reload. Every
//  other key, including any key nobody has classified, gets the everything scope, which runs the
//  full reload. Forgetting to classify a new key is therefore slow but never wrong. Only color
//  keys can be misclassified, so ProfileReloadScopeTests asserts that every color key
//  iTermProfilePreferences knows about is either in the colors scope or explicitly excluded.
//
//  The graph is deliberately authored by hand rather than inferred. The one invariant that must
//  hold for the colors scope is: nothing outside reloadColorsFromProfile: reads a colors-scope key
//  during the full reload, and nothing reads one from the live profile (self.profile) while a
//  reload is in flight. In debug builds iTermProfileReadRecorder (an Objective-C NSDictionary
//  subclass) checks both on every full reload; see -[PTYSession setPreferencesFromAddressBookEntry:].
//  Readers that need a color outside the reload (the badge, for one) cache it from
//  reloadColorsFromProfile: instead of reading the profile at draw time.
//

import Foundation

enum ProfileReloadScope {
    // Only the color map and things derived from it need to be reloaded.
    case colors
    // Run the full profile reload. This is the safe default.
    case everything
}

@objc(iTermProfileReloadScopes)
final class ProfileReloadScopes: NSObject {
    // The base keys of every color setting. Each has three variants: the base key, which is used
    // when the profile does not have separate light and dark colors, and the light and dark
    // suffixed keys. Note that the flag that selects between them
    // (KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE) is not in this scope: it changes how
    // non-color settings like KEY_USE_BOLD_COLOR are resolved too, so it needs the full reload.
    private static let colorBaseKeys: [String] = [
        KEY_FOREGROUND_COLOR,
        KEY_BACKGROUND_COLOR,
        KEY_BOLD_COLOR,
        KEY_LINK_COLOR,
        KEY_MATCH_COLOR,
        KEY_SELECTION_COLOR,
        KEY_SELECTED_TEXT_COLOR,
        KEY_CURSOR_COLOR,
        KEY_CURSOR_TEXT_COLOR,
        KEY_IME_CURSOR_COLOR,
        KEY_ANSI_0_COLOR,
        KEY_ANSI_1_COLOR,
        KEY_ANSI_2_COLOR,
        KEY_ANSI_3_COLOR,
        KEY_ANSI_4_COLOR,
        KEY_ANSI_5_COLOR,
        KEY_ANSI_6_COLOR,
        KEY_ANSI_7_COLOR,
        KEY_ANSI_8_COLOR,
        KEY_ANSI_9_COLOR,
        KEY_ANSI_10_COLOR,
        KEY_ANSI_11_COLOR,
        KEY_ANSI_12_COLOR,
        KEY_ANSI_13_COLOR,
        KEY_ANSI_14_COLOR,
        KEY_ANSI_15_COLOR,
        KEY_CURSOR_GUIDE_COLOR,
        KEY_BADGE_COLOR,
        KEY_TAB_COLOR,
        KEY_UNDERLINE_COLOR,
        KEY_ACTIVE_PANE_BORDER_COLOR,
    ]

    @objc static let colorsScopeKeys: Set<String> = {
        var keys = Set<String>()
        for base in colorBaseKeys {
            for variant in iTermProfilePreferences.colorVariantKeys(forBaseKey: base) {
                keys.insert(variant)
            }
        }
        return keys
    }()

    // Color keys that nonetheless need the full reload. Empty today. A key goes here when something
    // outside reloadColorsFromProfile: reads it and cannot reasonably be moved there. Listing it
    // keeps ProfileReloadScopeTests honest: every color key must be in exactly one of these two
    // sets, so a new color key has to be classified by hand.
    @objc static let colorKeysExcludedFromColorsScope: Set<String> = []

    static func scope(forKey key: String) -> ProfileReloadScope {
        if colorsScopeKeys.contains(key) {
            return .colors
        }
        return .everything
    }
}

// Describes what must be reloaded to bring a session in line with a changed profile.
@objc(iTermProfileReloadPlan)
final class ProfileReloadPlan: NSObject {
    @objc let changedKeys: Set<String>
    // When true, run the full reload. Otherwise every changed key is in the colors scope and only
    // the colors reload is needed. There is no third state: the full reload includes colors.
    @objc let reloadsEverything: Bool

    private init(changedKeys: Set<String>, everything: Bool) {
        self.changedKeys = changedKeys
        self.reloadsEverything = everything
        super.init()
    }

    // The plan that runs the full reload, which is what callers that don't know what changed use.
    @objc static let everything = ProfileReloadPlan(changedKeys: [], everything: true)

    // Computes the keys whose values differ between the two profiles and takes the union of their
    // scopes. A nil old profile, or a diff that finds nothing changed, falls back to everything:
    // the caller decided a reload was needed, so do not second-guess it.
    //
    // This runs on every escape-sequence color write, so it makes one pass over each profile with
    // no intermediate collections. Unchanged values are normally the same object in both profiles
    // (writers shallow-copy the current profile and replace a few values), so the identity check
    // settles most keys without calling isEqual: on large values like triggers or key mappings.
    @objc(planFromProfile:toProfile:)
    static func plan(from oldProfile: NSDictionary?, to newProfile: NSDictionary) -> ProfileReloadPlan {
        guard let oldProfile else {
            return .everything
        }
        var changed = Set<String>()
        var sawUnclassifiableKey = false
        oldProfile.enumerateKeysAndObjects { key, oldValue, stop in
            guard let string = key as? String else {
                // A non-string key is not a profile key we know how to classify.
                sawUnclassifiableKey = true
                stop.pointee = true
                return
            }
            guard let newValue = newProfile.object(forKey: key) else {
                changed.insert(string)
                return
            }
            let oldObject = oldValue as AnyObject
            if oldObject !== newValue as AnyObject && !oldObject.isEqual(newValue) {
                changed.insert(string)
            }
        }
        if sawUnclassifiableKey {
            return .everything
        }
        for key in newProfile.allKeys where oldProfile.object(forKey: key) == nil {
            guard let string = key as? String else {
                return .everything
            }
            changed.insert(string)
        }
        if changed.isEmpty {
            return .everything
        }
        let everything = changed.contains { ProfileReloadScopes.scope(forKey: $0) == .everything }
        return ProfileReloadPlan(changedKeys: changed, everything: everything)
    }

    override var description: String {
        return "<ProfileReloadPlan everything=\(reloadsEverything) changedKeys=\(changedKeys.sorted())>"
    }
}
