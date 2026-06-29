//
//  iTermOpenDirectory+MainApp.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/4/26.
//

#import "iTermOpenDirectory.h"

NS_ASSUME_NONNULL_BEGIN

// Main-app-only API: cached, gateway-routed access to the user's login
// shell. The OpenDirectory query itself runs in the pidinfo XPC service
// via iTermSlowOperationGateway, so a wedged opendirectoryd never blocks
// the main app. Not visible to (and not built into) the pidinfo target.
@interface iTermOpenDirectory (MainApp)

// Returns the user's login shell. The first call blocks until the lookup
// settles (because there's nothing else to return). Subsequent calls
// always trigger a fresh background lookup and wait briefly for it; if
// the lookup doesn't complete in time, the cached value from the previous
// successful query is returned. This keeps the result responsive to chsh
// while preventing the UI from hanging when opendirectoryd is slow.
+ (nullable NSString *)userShell;

// Kicks off a background lookup to populate the cache. Safe to call
// multiple times; only one lookup is in flight at a time. Call early in
// app launch so the first +userShell call doesn't have to block.
+ (void)prime;

@end

NS_ASSUME_NONNULL_END
