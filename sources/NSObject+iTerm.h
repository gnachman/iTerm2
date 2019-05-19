//
//  NSObject+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import <Foundation/Foundation.h>

// https://www.mikeash.com/pyblog/friday-qa-2010-06-18-implementing-equality-and-hashing.html
// NOTE: This does not compose well. Use iTermCombineHash if you need to chain hashes.
NS_INLINE NSUInteger iTermMikeAshHash(NSUInteger hash1, NSUInteger hash2) {
    static const int rot = (CHAR_BIT * sizeof(NSUInteger)) / 2;
    return hash1 ^ ((hash2 << rot) | (hash2 >> rot));
}

// http://www.cse.yorku.ca/~oz/hash.html
NS_INLINE NSUInteger iTermDJB2Hash(unsigned char *bytes, size_t length) {
    NSUInteger hash = 5381;

    for (NSUInteger i = 0; i < length; i++) {
        unichar c = bytes[i];
        hash = (hash * 33) ^ c;
    }

    return hash;
}

NS_INLINE NSUInteger iTermCombineHash(NSUInteger hash1, NSUInteger hash2) {
    unsigned char hash1Bytes[sizeof(NSUInteger)];
    memmove(hash1Bytes, &hash1, sizeof(hash1));
    return iTermMikeAshHash(hash2, iTermDJB2Hash(hash1Bytes, sizeof(hash1)));
}


@interface iTermDelayedPerform : NSObject
// If set before the block is run, then the block will not be run.
@property(nonatomic, assign) BOOL canceled;

// Set by NSObject just before block is run.
@property(nonatomic, assign) BOOL completed;
@end

@interface NSObject (iTerm)

+ (BOOL)object:(NSObject *)a isEqualToObject:(NSObject *)b;
+ (instancetype)castFrom:(id)object;

- (void)performSelectorOnMainThread:(SEL)selector withObjects:(NSArray *)objects;

// Retains self for |delay| time, whether canceled or not.
// Set canceled=YES on the result to keep the block from running. Its completed flag will be set to
// YES before block is run. The pattern usually looks like this:
//
// @implementation MyClass {
//   __weak iTermDelayedPerform *_delayedPerform;
// }
//
// - (void)scheduleTask {
//   [self cancelScheduledTask];  // Don't this if you don't want to schedule two tasks at once.
//   _delayedPerform = [self performBlock:^() {
//                               [self performTask];
//                               if (_delayedPerform.completed) {
//                                 _delayedPerform = nil;
//                               }
//                             }
//                             afterDelay:theDelay];
// }
//
// - (void)cancelScheduledTask {
//   _delayedPerform.canceled = YES;
//   _delayedPerform = nil;
// }
- (iTermDelayedPerform *)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay;

// Returns nil if this object is an instance of NSNull, otherwise returns self.
- (instancetype)nilIfNull;

- (void)it_setAssociatedObject:(id)associatedObject forKey:(void *)key;
- (void)it_setWeakAssociatedObject:(id)associatedObject forKey:(void *)key;
- (id)it_associatedObjectForKey:(void *)key;

- (void)it_performNonObjectReturningSelector:(SEL)selector withObject:(id)object;
- (id)it_performAutoreleasedObjectReturningSelector:(SEL)selector withObject:(id)object;

- (BOOL)it_isSafeForPlist;
- (NSString *)it_invalidPathInPlist;
- (instancetype)it_weakProxy;

@end
