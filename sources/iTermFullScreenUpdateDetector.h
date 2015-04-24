//
//  iTermFullScreenUpdateDetector.h
//  iTerm2
//
//  Created by George Nachman on 4/23/15.
//
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"

@class VT100Grid;

@protocol iTermFullScreenUpdateDetectorDelegate<NSObject>

- (VT100Grid *)fullScreenUpdateDidComplete;
- (void)fullScreenDidExpire;

@end

@interface iTermFullScreenUpdateDetector : NSObject

@property(nonatomic, assign) id<iTermFullScreenUpdateDetectorDelegate> delegate;
@property(nonatomic, readonly) VT100Grid *savedGrid;
@property(nonatomic, assign) BOOL drewSavedGrid;

- (void)cursorMovedToRow:(int)row;
- (void)willAppendCharacters:(int)count;
- (void)reset;

@end
