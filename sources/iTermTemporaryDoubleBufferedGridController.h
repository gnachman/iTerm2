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

@protocol iTermTemporaryDoubleBufferedGridControllerDelegate<NSObject>

// Requests a copy of the current grid, which will be held on to for a short time and provided
// via -savedGrid.
- (VT100Grid *)temporaryDoubleBufferedGridCopy;

// A saved grid that was drawn has expired. The view should be redrawn with the current grid.
- (void)temporaryDoubleBufferedGridDidExpire;

@end

@interface iTermTemporaryDoubleBufferedGridController : NSObject

@property(nonatomic, assign) id<iTermTemporaryDoubleBufferedGridControllerDelegate> delegate;
@property(nonatomic, readonly) VT100Grid *savedGrid;

// Set this to use if you're drawing the view from the saved grid in order to get a notification
// when it expires.
@property(nonatomic, assign) BOOL drewSavedGrid;

// Save the grid if there isn't already a saved grid.
- (void)start;

// Remove the saved grid.
- (void)reset;

@end
