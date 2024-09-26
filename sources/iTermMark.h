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
- (iTermMark *)progenitor;
- (id<iTermMark>)doppelganger;
@end

// This is a base class for marks but should never be used directly.
@interface iTermMark : NSObject<iTermMark, IntervalTreeObject, IntervalTreeImmutableObject, NSCopying>
@property (nonatomic, readonly) BOOL isDoppelganger;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;
- (id<iTermMark>)doppelganger;

- (NSDictionary *)dictionaryValueWithTypeInformation;

// When using this beware of `IntervalTreeObject`s that do not inherit from iTermMark, such as
// PTYAnnotation (which needs a delegate to function).
+ (id<IntervalTreeObject>)intervalTreeObjectWithDictionaryWithTypeInformation:(NSDictionary *)dict;

@end
