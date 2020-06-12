//
//  PTYSplitView.h
//  iTerm
//
//  Created by George Nachman on 12/10/11.
//

#import <AppKit/AppKit.h>
#import "FutureMethods.h"

@class PTYSplitView;

@protocol PTYSplitViewDelegate<NSSplitViewDelegate>

- (void)splitView:(PTYSplitView *)splitView
     draggingDidEndOfSplit:(int)clickedOnSplitterIndex
                    pixels:(NSSize)changePx;

- (void)splitView:(PTYSplitView *)splitView draggingWillBeginOfSplit:(int)splitterIndex;
- (void)splitViewDidChangeSubviews:(PTYSplitView *)splitView;

@end

@interface PTYSplitViewDividerInfo: NSObject
@property (nonatomic, readonly) NSRect frame;
@property (nonatomic, readonly) BOOL isVertical;

- (instancetype)initWithFrame:(NSRect)frame vertical:(BOOL)vertical;
- (NSComparisonResult)compare:(PTYSplitViewDividerInfo *)other;

@end

/* This extends NSSplitView by adding a delegate method that's called when
 * dragging a splitter finishes. */
@interface PTYSplitView : NSSplitView

@property (weak) id<PTYSplitViewDelegate> delegate;

- (NSArray<PTYSplitViewDividerInfo *> *)transitiveDividerLocationsVertical:(BOOL)vertical;

@end
