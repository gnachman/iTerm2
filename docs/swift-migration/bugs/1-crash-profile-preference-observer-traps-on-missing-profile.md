# A browser session crashes the app if its profile disappears from the profile model

**Waiting on the owner:** its file is under `sources/Settings/`, which is reserved while another agent reworks it; the owner has been asked whether to fix it anyway.

**Where:** `sources/Settings/iTermProfilePreferenceObserver.swift`, the five `value(_:)` overloads and the private `observedProfile` property (near line 127).

**What happens:** each `value(_:)` accessor looks up the observed profile by GUID and calls `it_fatalError` when the model has no profile with that GUID, so the app crashes. The browser (`iTermBrowserManager`, `iTermBrowserViewController`, `iTermBrowserExtensionManager`) reads these accessors for a browser session's profile in the shared or the sessions profile model. Deleting the profile of an open browser session in Settings is enough (below).

**Why:** `observedProfile` is

```swift
guard let profile = model.bookmark(withGuid: guid) else {
    it_fatalError("No profile with GUID \(guid)")
}
```

The same class's `value(for:)`, used by its observation closures, treats a missing profile as an empty dictionary, and the Objective-C `iTermProfilePreferences` methods it calls accept a nil profile and read the defaults. So the crash looks unintended.

**How to see it:** open a browser session whose profile is not divorced; `PTYSession.swift` (near line 1692) then gives the observer the shared model and the profile's GUID. Give that profile a browser trigger. Delete the profile in Settings: `+[ITAddressBookMgr removeProfile:fromModel:]` removes any profile but the last, and nothing tells the session, whose `-reloadProfile` only logs that the shared profile is missing. When the trigger, loaded before the deletion, next matches a page, `iTermBrowserTriggerHandler.handle(matchEvent:)` (near line 196) reads `profileObserver.value(KEY_TRIGGERS_USE_INTERPOLATED_STRINGS)`, which reaches `it_fatalError`. The extension manager's reads (`iTermBrowserExtensionManager.swift`, near lines 155, 174 and 204) reach it the same way. Seen by reading the code; not run.

**Suggested fix:** pass the optional profile through (`model.bookmark(withGuid: guid)` without the trap), so the accessors read the defaults the way `value(for:)` does.

**Found:** 2026-11-20, while making the false nonnull claims of `iTermProfilePreferences` nullable. Before that change the crash was an implicit unwrap.

**Checked against the tree:** 2026-11-27. `observedProfile` still traps; the browser view controller is still created with this observer in `PTYSession.swift`; each step of the route above was read in the source.
