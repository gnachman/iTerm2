//
//  iTermUserDefaultsObserver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Owns its registrations: they are removed when the observer is deallocated.
@interface iTermUserDefaultsObserver : NSObject
// Runs `block` async on the main queue when the value for `key` changes.
// Writes that leave the value unchanged are ignored. Observing the same key
// again replaces its block.
- (void)observeKey:(NSString *)key block:(void (^)(void))block;
- (void)observeAllKeysWithBlock:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
