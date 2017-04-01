//
//  iTermMark.h
//  iTerm2
//
//  Created by George Nachman on 10/18/15.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@protocol iTermMark <NSObject, IntervalTreeObject>

// Should the mark be seen by the user? Returns YES by default.
@property(nonatomic, readonly) BOOL isVisible;

@end

// This is a base class for marks but should never be used directly.
@interface iTermMark : NSObject<iTermMark>

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

@end
