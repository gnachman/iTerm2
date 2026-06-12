//
//  iTermSessionPreviewPanel.h
//  iTerm2
//
//  A reusable floating preview panel that shows a snapshot of a PTYSession plus
//  a title and detail line. Extracted from iTermOpenQuicklyWindowController so
//  both Open Quickly and the AI chat session @-mention picker can share one
//  implementation. The panel is a borderless, non-activating child window that
//  positions itself beside a parent rect, flipping to the other side when it
//  would run off-screen, and sizes its height to the snapshot's aspect ratio.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class PTYSession;

@interface iTermSessionPreviewPanel : NSObject

// YES while the preview is on screen.
@property (nonatomic, readonly) BOOL visible;

// Show (building the panel lazily) or update the preview for `session`,
// positioned relative to `parentFrame` and attached as a child of
// `parentWindow`. The snapshot is cached by session guid, so calling this
// repeatedly for the same session does not re-render the grid.
- (void)showForSession:(PTYSession *)session
                 title:(NSString *)title
                detail:(NSString *)detail
           parentFrame:(NSRect)parentFrame
          parentWindow:(NSWindow *)parentWindow
    NS_SWIFT_NAME(show(for:title:detail:parentFrame:parentWindow:));

// Reposition the (already visible) panel for a new parent frame without
// touching its content. Used while the parent window animates its own resize,
// since a borderless child panel does not animate reliably alongside it.
- (void)repositionForParentFrame:(NSRect)parentFrame;

// Order the panel out but keep it for reuse.
- (void)hide;

// Detach from the parent, destroy the panel, and clear the snapshot cache. The
// panel is rebuilt on the next -showForSession:. Call from every dismissal path.
- (void)teardown;

@end

NS_ASSUME_NONNULL_END
