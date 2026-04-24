//
//  iTermMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermMark;
@class ScreenCharArray;

@protocol iTermMark <NSObject, IntervalTreeImmutableObject>
@property (nonatomic) long long cachedLocation;
@property (nonatomic, readonly) BOOL isDoppelganger;
@property (nonatomic, readonly) NSString *guid;
- (iTermMark *)progenitor;
- (id<iTermMark>)doppelganger;
@end

/// A mark that remembers the screen width at the time its content was saved.
/// Used by ResilientCoordinate to reflow coordinates when the width changes
/// between fold/porthole creation and removal.
@protocol iTermWidthSavingMark <iTermMark>
@property (nonatomic, readonly) int savedWidth;
@property (nonatomic, readonly, nullable) NSArray<ScreenCharArray *> *savedLines;
@end

// This is a base class for marks but should never be used directly.
@interface iTermMark : NSObject<iTermMark, IntervalTreeObject, IntervalTreeImmutableObject, NSCopying>
@property (nonatomic, readonly) BOOL isDoppelganger;
@property (nonatomic, readonly) NSString *guid;
@property (nonatomic, readonly) NSString *stableIdentifier;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict NS_DESIGNATED_INITIALIZER;
- (NSDictionary *)dictionaryValue;
- (id<iTermMark>)doppelganger;

- (NSDictionary *)dictionaryValueWithTypeInformation;

// When using this beware of `IntervalTreeObject`s that do not inherit from iTermMark, such as
// PTYAnnotation (which needs a delegate to function).
+ (nullable id<IntervalTreeObject>)intervalTreeObjectWithDictionaryWithTypeInformation:(NSDictionary *)dict;

// This is here for subclasses to override. They should always call it.
- (void)becomeDoppelgangerWithProgenitor:(iTermMark *)progenitor;

// For use in copyWithZone: to copy guid to doppelganger
- (void)copyGuidFrom:(iTermMark *)source;

@end

NS_ASSUME_NONNULL_END
