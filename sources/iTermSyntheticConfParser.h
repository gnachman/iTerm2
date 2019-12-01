//
//  iTermSyntheticConfParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSyntheticConfParser : NSObject

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

// Converts a path like "/System/Volumes/Data/bar/baz" into "/bar/baz" when there's an entry in
// synthetic.conf like:
//
// bar  System/Volumes/Data/bar
- (NSString *)pathByReplacingPrefixWithSyntheticRoot:(NSString *)dir;

@end

NS_ASSUME_NONNULL_END
