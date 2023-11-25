//
//  iTermSelectionScrollHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/24/14.
//
//

#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

@protocol iTermSelectionScrollHelperDelegate <NSObject>

- (CGFloat)lineHeight;
- (CGFloat)excess;
- (BOOL)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView;
- (void)selectionScrollWillStart;
- (BOOL)selectionScrollAllowed;

@end

@interface iTermSelectionScrollHelper : NSObject

@property(nonatomic, assign) NSView<iTermSelectionScrollHelperDelegate> *delegate;

- (void)mouseUp;
- (void)mouseDraggedTo:(NSPoint)locationInTextView coord:(VT100GridCoord)coord;
- (void)disableUntilMouseUp;

@end
