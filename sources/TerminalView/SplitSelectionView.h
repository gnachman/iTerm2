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
    kFullPane,

    // These mean the moved pane should span the whole tab along the named edge,
    // becoming a child of the tab’s root splitter rather than of the hovered
    // pane’s splitter.
    kTabTopEdge,
    kTabBottomEdge,
    kTabLeftEdge,
    kTabRightEdge
};

// Which of a pane’s edges lie on the outer edge of its tab, and are therefore
// eligible to offer a full-width or full-height drop.
typedef NS_OPTIONS(NSUInteger, iTermTabEdgeMask) {
    iTermTabEdgeMaskNone = 0,
    iTermTabEdgeMaskTop = 1 << 0,
    iTermTabEdgeMaskBottom = 1 << 1,
    iTermTabEdgeMaskLeft = 1 << 2,
    iTermTabEdgeMaskRight = 1 << 3
};

// Is this a whole-tab-edge drop target (as opposed to a half of one pane)?
BOOL SplitSessionHalfIsTabEdge(SplitSessionHalf half);

// Does a drop at this tab edge produce a splitter whose orientation is vertical
// (i.e., side-by-side children)? Undefined unless SplitSessionHalfIsTabEdge().
BOOL SplitSessionHalfTabEdgeIsVertical(SplitSessionHalf half);

// Does a drop at this tab edge insert the pane before the existing content
// (top/left) rather than after it (bottom/right)? Undefined unless
// SplitSessionHalfIsTabEdge().
BOOL SplitSessionHalfTabEdgeIsBefore(SplitSessionHalf half);

typedef NS_ENUM(NSInteger, SplitSelectionViewMode) {
    // Clicking cancels
    SplitSelectionViewModeSourceMove,
    SplitSelectionViewModeSourceSwap,

    // Clicking moves/swaps
    SplitSelectionViewModeTargetMove,
    SplitSelectionViewModeTargetSwap,

    // Clicking selects
    SplitSelectionViewModeInspect,
    SplitSelectionViewModeSelect
};

@class PTYSession;

@protocol SplitSelectionViewDelegate <NSObject>

// dest will be null when canceling.
- (void)didSelectDestinationSession:(PTYSession *)session
                               half:(SplitSessionHalf)half;
@end

@interface SplitSelectionView : NSView
@property (nonatomic, readonly) SplitSelectionViewMode mode;

// Edges of the pane this view overlays that coincide with the tab’s outer
// edges. Dragging near one of them offers a whole-tab drop. Defaults to none.
@property (nonatomic) iTermTabEdgeMask tabEdges;

// Called when the selected whole-tab edge changes, with kNoHalf when no tab
// edge is selected any more. The tab uses this to draw the drop target, since
// it spans panes and this view cannot draw outside its own bounds.
@property (nonatomic, copy) void (^tabEdgeDidChange)(SplitSessionHalf);

// When set, clicks pass through to whatever is underneath. Used by the
// tab-spanning drop target, which is decoration only.
@property (nonatomic) BOOL clickThrough;

// frame is the frame fo the parent view.
// session is the session we overlay.
// the delegate gets called when a selection is made.
- (instancetype)initWithMode:(SplitSelectionViewMode)mode
                   withFrame:(NSRect)frame
                     session:(PTYSession *)session
                    delegate:(id<SplitSelectionViewDelegate>)delegate;

// Update the selected half for a drag at the given point
- (void)updateAtPoint:(NSPoint)point;

// Which half is currently selected.
- (SplitSessionHalf)half;

// Force the highlighted region. Used for the tab-spanning drop target, which
// has no tracking area of its own.
- (void)setHalf:(SplitSessionHalf)half;

@end
