//
//  iTermRightGutterPanel.h
//  iTerm2
//
//  Protocol for an NSView-hosting accessory installed in the strip to the
//  right of the terminal grid (between any timestamps strip and the
//  scrollbar). The terminal grid is shrunk by the panel's width via
//  +[PTYSession desiredRightExtraForProfile:] adding into the right-extra
//  budget that already supports adjacent timestamps.
//

#import <Cocoa/Cocoa.h>

@class PTYSession;
@protocol iTermRightGutterPanelDelegate;

NS_ASSUME_NONNULL_BEGIN

@protocol iTermRightGutterPanel <NSObject>

// Stable identifier; used for ordering and lookup. Must not change over the
// lifetime of the panel instance.
@property (nonatomic, readonly) NSString *identifier;

// The hosted view. Installed by the controller as a SessionView subview
// above the scrollview (and the legacy/metal rendering siblings) so the
// renderer cannot overdraw it.
@property (nonatomic, readonly) NSView *view;

// Width in points used to size the hosted view at layout time. Must agree
// with the value returned by the registered widthProvider for the same
// profile state — the controller positions panels using `width` but the
// global width budget (which shrinks the terminal grid) is computed from
// widthProvider, and a mismatch leaves a gap or overhang. The simplest way
// to keep them in sync is for both to call a shared helper.
@property (nonatomic, readonly) CGFloat width;

// If NO, the hosted view is hidden but the slot it would occupy is NOT
// reclaimed by neighbors — that is determined by the registered
// widthProvider. To make an invisible panel contribute zero to the width
// budget (the usual case), the widthProvider must return 0 in the same
// state that drives `visible` to NO.
@property (nonatomic, readonly) BOOL visible;

// Notified when width or visibility changes; the controller will relayout
// and trigger a right-extra recomputation as needed.
@property (nonatomic, weak, nullable) id<iTermRightGutterPanelDelegate> panelDelegate;

- (void)attachToSession:(PTYSession *)session;
- (void)detach;

@end

@protocol iTermRightGutterPanelDelegate <NSObject>
- (void)rightGutterPanelDidChangeWidthOrVisibility:(id<iTermRightGutterPanel>)panel;
@end

NS_ASSUME_NONNULL_END
