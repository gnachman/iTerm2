//
//  iTermSyntheticConfParser+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/2/19.
//

#import "iTermSyntheticConfParser.h"

// Exposed for testing

@interface iTermSyntheticDirectory: NSObject
// Something like "/bar"
@property (nonatomic, readonly) NSString *root;
// Something like "/System/Volumes/Data/bar"
@property (nonatomic, readonly) NSString *target;

- (instancetype)initWithRoot:(NSString *)root target:(NSString *)target NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSString *)pathByReplacingPrefixWithSyntheticRoot:(NSString *)dir;
@end

@interface iTermSyntheticConfParser()
@property (nonatomic, readonly) NSArray<iTermSyntheticDirectory *> *syntheticDirectories;

- (instancetype)initPrivate NS_DESIGNATED_INITIALIZER;
@end

