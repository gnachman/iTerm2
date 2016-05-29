//
//  SplitSelectionView.h
//  iTerm2
//
//  Draws an view over each session and allows the user to select a split in it
//  for moving panes. Only exists briefly while in move pane mode.
//
//  Created by George Nachman on 8/26/11.
//

#import <Cocoa/Cocoa.h>

@class PTYSession;

typedef NS_ENUM(NSInteger, SplitSessionHalf) {
    kNoHalf,
    kNorthHalf,
    kSouthHalf,
    kEastHalf,
    kWestHalf,
    kFullPane
};

@class PTYSession;

@protocol SplitSelectionViewDelegate <NSObject>

// dest will be null when canceling.
- (void)didSelectDestinationSession:(PTYSession *)session
                               half:(SplitSessionHalf)half;
@end

@interface SplitSelectionView : NSView

@property (nonatomic, assign) BOOL cancelOnly;

// a "cancelOnly" pane can't be a destination and clicking on it cancels the
// operation.
//
// frame is the frame fo the parent view.
// session is the session we overlay.
// the delegate gets called when a selection is made.
- (instancetype)initAsCancelOnly:(BOOL)cancelOnly
                       withFrame:(NSRect)frame
                         session:(PTYSession *)session
                        delegate:(id<SplitSelectionViewDelegate>)delegate
                            move:(BOOL)move;

// Update the selected half for a drag at the given point
- (void)updateAtPoint:(NSPoint)point;

// Which half is currently selected.
- (SplitSessionHalf)half;

@end
