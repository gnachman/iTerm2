//
//  iTermOpenDirectory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermOpenDirectory : NSObject

// Synchronously runs the OpenDirectory query for the calling user's
// login shell. Can hang if opendirectoryd is wedged. This is the
// implementation used by the pidinfo XPC service inside its
// performRiskyBlock watchdog — main-app callers should import
// "iTermOpenDirectory+MainApp.h" and use +userShell instead, which
// routes through pidinfo and caches the result.
+ (nullable NSString *)performBlockingLookup;

@end

NS_ASSUME_NONNULL_END
