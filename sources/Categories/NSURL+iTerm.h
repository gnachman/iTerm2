//
//  NSURL.h
//  iTerm2
//
//  Created by George Nachman on 4/24/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURL(iTerm)

+ (nullable NSURL *)urlByReplacingFormatSpecifier:(NSString *)formatSpecifier
                                         inString:(NSString *)string
                                        withValue:(NSString *)value;

// Returns a URL that is the same but does not have a fragment.
- (NSURL *)URLByRemovingFragment;

// Adds a query parameter to a URL which may or may not have other query parameters or a fragment.
- (NSURL *)URLByAppendingQueryParameter:(NSString *)queryParameter;

// If non-ascii characters are present then the string is first percent-escaped. NSURL will fail
// if any non-ascii characters exist, so it's worth a shot. Returns nil if the string cannot be
// turned into a URL.
+ (nullable NSURL *)URLWithUserSuppliedString:(NSString *)string;

- (BOOL)saveContentsOfPathToZip:(NSURL *)destination;
- (nullable NSData *)zippedContents;

// A description safe for the always-on retrospective ring (RLog): scheme, host,
// and path only. Drops the three places a secret hides in a URL: userinfo
// (user:password@), the query string (?token=…), and the fragment (#access_token=…).
// See DebugLogging.h.
@property (nonatomic, readonly) NSString *it_redactedDescription;

@end

NS_ASSUME_NONNULL_END
