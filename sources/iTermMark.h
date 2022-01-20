//
//  iTermMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@protocol iTermMark <NSObject, IntervalTreeImmutableObject>

// Should the mark be seen by the user? Returns YES by default.
#warning TODO: This should move to VT100ScreenMark.
@property(nonatomic, readonly) BOOL isVisible;

@end

// This is a base class for marks but should never be used directly.
@interface iTermMark : NSObject<iTermMark, IntervalTreeObject, NSCopying>
@property (nonatomic, readonly) BOOL isDoppelganger;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;
- (id<iTermMark>)progenitor;

@end
