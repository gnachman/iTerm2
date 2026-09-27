//
//  iTermAPICreateTabFocusDeferral.h
//  iTerm2
//
//  Self-contained workaround for a defect in the iterm2 Python library. See the
//  .m file for the full explanation. Everything about the workaround, including
//  the client-library-version gate that decides whether it applies at all, lives
//  behind this object so the rest of iTermAPIHelper is untouched except at a few
//  clearly named call sites.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ITMFocusChangedNotification;

// Opaque per-create handle returned by
// -beginCreateTabForConnectionGuid:libraryVersion:. Nil means the create is
// unaffected and the workaround does nothing for it.
@interface iTermAPICreateTabFocusDeferralToken : NSObject
@end

@interface iTermAPICreateTabFocusDeferral : NSObject

// Whether a client advertising `libraryVersion` (the raw x-iterm2-library-version
// header, e.g. "python 2.22") predates the library-side fix and therefore needs
// the deferral workaround. Exposed for testing; callers use the instance methods.
+ (BOOL)libraryVersionIsAffected:(nullable NSString *)libraryVersion;

// Call when an API CreateTab begins. `connectionGuid` identifies the requesting
// connection (the same guid its focus subscription is keyed under). Returns a
// token when this create is affected (nil otherwise). While the token is
// outstanding the connection is "holding": see -shouldHold... below. Pass the
// token to -endCreateTabWithToken:... when the create finishes.
- (nullable iTermAPICreateTabFocusDeferralToken *)beginCreateTabForConnectionGuid:(nullable NSString *)connectionGuid
                                                                   libraryVersion:(nullable NSString *)libraryVersion;

// Whether selected_tab / active-session FocusChanged notifications destined for
// the given connection should be held right now. True only for a connection with
// an affected CreateTab in flight -- during that window such a notification could
// reference a window the connection does not know about yet and trip the bug.
// Every other connection keeps receiving focus notifications normally.
- (BOOL)shouldHoldFocusNotificationForConnectionGuid:(nullable NSString *)connectionGuid;

// Balances -beginCreateTabForConnectionGuid:libraryVersion:. Call once the
// CreateTab response has been sent. Stops holding for this connection and replays
// this create's own focus state to that connection (only), so it lands after the
// connection knows the new window: `selectedTabId` (nil if the new tab did not
// become current, e.g. a background tab) then `activeSessionId` (nil if unknown).
// The replay block receives the notification and the target connection guid. A
// nil token is a no-op.
- (void)endCreateTabWithToken:(nullable iTermAPICreateTabFocusDeferralToken *)token
                selectedTabId:(nullable NSString *)selectedTabId
              activeSessionId:(nullable NSString *)activeSessionId
                       replay:(void (^)(ITMFocusChangedNotification *notification,
                                        NSString *connectionGuid))replay;

@end

NS_ASSUME_NONNULL_END
