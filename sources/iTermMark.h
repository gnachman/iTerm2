//
//  iTermMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@class iTermMark;

@protocol iTermMark <NSObject, IntervalTreeImmutableObject>
@property (nonatomic) long long cachedLocation;
@property (nonatomic, readonly) BOOL isDoppelganger;
@property (nonatomic, readonly) NSString *guid;
- (iTermMark *)progenitor;
- (id<iTermMark>)doppelganger;
@end

// This is a base class for marks but should never be used directly.
@interface iTermMark : NSObject<iTermMark, IntervalTreeObject, IntervalTreeImmutableObject, NSCopying>
@property (nonatomic, readonly) BOOL isDoppelganger;
@property (nonatomic, readonly) NSString *guid;
@property (nonatomic, readonly) NSString *stableIdentifier;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDictionary:(NSDictionary *)dict NS_DESIGNATED_INITIALIZER;
- (NSDictionary *)dictionaryValue;
- (id<iTermMark>)doppelganger;

- (NSDictionary *)dictionaryValueWithTypeInformation;

// When using this beware of `IntervalTreeObject`s that do not inherit from iTermMark, such as
// PTYAnnotation (which needs a delegate to function).
+ (id<IntervalTreeObject>)intervalTreeObjectWithDictionaryWithTypeInformation:(NSDictionary *)dict;

// This is here for subclasses to override. They should always call it.
- (void)becomeDoppelgangerWithProgenitor:(iTermMark *)progenitor;

// For use in copyWithZone: to copy guid to doppelganger
- (void)copyGuidFrom:(iTermMark *)source;

@end
