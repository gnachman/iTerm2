//
//  NSObject+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

// https://www.mikeash.com/pyblog/friday-qa-2010-06-18-implementing-equality-and-hashing.html
// NOTE: This does not compose well. Use iTermCombineHash if you need to chain hashes.
NS_INLINE NSUInteger iTermMikeAshHash(NSUInteger hash1, NSUInteger hash2) {
    static const int rot = (CHAR_BIT * sizeof(NSUInteger)) / 2;
    return hash1 ^ ((hash2 << rot) | (hash2 >> rot));
}

// http://www.cse.yorku.ca/~oz/hash.html
NS_INLINE NSUInteger iTermDJB2Hash(const unsigned char *bytes, size_t length) {
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

// For Swift convenience.
@property(nonatomic, readonly) NSString *it_addressString;

+ (BOOL)object:(NSObject * _Nullable)a isEqualToObject:(NSObject * _Nullable)b;

// Supports NSArray, NSDictionary, and NSNumber.
+ (BOOL)object:(__kindof NSObject * _Nullable)a isApproximatelyEqualToObject:(__kindof NSObject * _Nullable)b epsilon:(double)epsilon;

+ (instancetype _Nullable)castFrom:(id _Nullable)object;
+ (instancetype)forceCastFrom:(id)object;

- (void)performSelectorOnMainThread:(SEL)selector withObjects:(NSArray * _Nullable)objects;

+ (void)it_enumerateDynamicProperties:(void (^)(NSString *name))block;

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
- (instancetype _Nullable)nilIfNull;

- (void)it_setAssociatedObject:(id _Nullable)associatedObject forKey:(const void *)key;
- (void)it_setWeakAssociatedObject:(id _Nullable)associatedObject forKey:(const void *)key;
- (id _Nullable)it_associatedObjectForKey:(const void *)key;

- (void)it_performNonObjectReturningSelector:(SEL)selector
                                  withObject:(id _Nullable)object;

- (void)it_performNonObjectReturningSelector:(SEL)selector
                                  withObject:(id _Nullable)object1
                                  withObject:(id _Nullable)object2;

- (void)it_performNonObjectReturningSelector:(SEL)selector
                                  withObject:(id _Nullable)object1
                                      object:(id _Nullable)object2
                                      object:(id _Nullable)object3;

- (id)it_performAutoreleasedObjectReturningSelector:(SEL)selector withObject:(id)object;

- (BOOL)it_isSafeForPlist;
- (NSString * _Nullable)it_invalidPathInPlist;
- (instancetype)it_weakProxy;
- (NSString *)tastefulDescription;
- (id)it_jsonSafeValue;

- (NSData *)it_keyValueCodedData;
+ (instancetype)it_fromKeyValueCodedData:(NSData *)data;
- (NSString *)jsonEncoded;
+ (instancetype)fromJsonEncodedString:(NSString *)string;


@end

NS_ASSUME_NONNULL_END
