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

// Returns a URL that is the same but does not have a fragment.
- (NSURL *)URLByRemovingFragment;

// Adds a query parameter to a URL which may or may not have other query parameters or a fragment.
- (NSURL *)URLByAppendingQueryParameter:(NSString *)queryParameter;

// If non-ascii characters are present then the string is first percent-escaped. NSURL will fail
// if any non-ascii characters exist, so it's worth a shot.
+ (NSURL *)URLWithUserSuppliedString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
