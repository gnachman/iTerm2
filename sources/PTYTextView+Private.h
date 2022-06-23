//
//  PTYTextView+Private.h
//  iTerm2
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "PTYNoteViewController.h"
#import "iTermTextViewContextMenuHelper.h"
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermFindCursorView.h"
#import "iTermQuickLookController.h"
#import "iTermBadgeLabel.h"
#import "iTermTextViewAccessibilityHelper.h"
#import "iTermFindCursorView.h"
#import "iTermFindOnPageHelper.h"
#import "iTermKeyboardHandler.h"
#import "iTermSelection.h"
#import "iTermSelectionScrollHelper.h"
#import "iTermTextPopoverViewController.h"

@protocol iTermCancelable;
@class iTermContentNavigationShortcut;
@class iTermIdempotentOperationJoiner;
@class iTermShellIntegrationWindowController;
@class iTermURLActionHelper;
@protocol Porthole;
@class PTYMouseHandler;
@protocol PTYTrackingChildWindow;

@interface PTYTextView () <
PTYNoteViewControllerDelegate,
iTermBadgeLabelDelegate,
iTermTextViewAccessibilityHelperDelegate,
iTermFindCursorViewDelegate,
iTermFindOnPageHelperDelegate,
iTermKeyboardHandlerDelegate,
iTermSelectionDelegate,
iTermSelectionScrollHelperDelegate,
NSDraggingSource,
NSPopoverDelegate> {
    NSCursor *cursor_;
    PTYMouseHandler *_mouseHandler;
    iTermURLActionHelper *_urlActionHelper;
    iTermShellIntegrationWindowController *_shellIntegrationInstallerWindow;
    iTermTextViewContextMenuHelper *_contextMenuHelper;
    iTermTextPopoverViewController* _indicatorMessagePopoverViewController;
    // Child windows that need to have their frames adjusted as you scroll.
    NSMutableArray<id<PTYTrackingChildWindow>> *_trackingChildWindows;
    CGFloat _lastVirtualOffset;
}

@property(nonatomic, strong) iTermSelection *selection;
@property(nonatomic, strong) iTermSemanticHistoryController *semanticHistoryController;
@property(nonatomic, strong) iTermFindCursorView *findCursorView;
@property(nonatomic, strong) NSWindow *findCursorWindow;  // For find-cursor animation
@property(nonatomic, strong) iTermQuickLookController *quickLookController;
@property(strong, readwrite) NSTouchBar *touchBar NS_AVAILABLE_MAC(10_12_2);
@property(nonatomic, readonly) BOOL hasUnderline;
@property(nonatomic, strong) id<iTermCancelable> lastUrlActionCanceler;
@property(nonatomic, readonly, strong) NSMutableArray<id<Porthole>> *portholes;
@property(nonatomic, strong) iTermIdempotentOperationJoiner *portholesNeedUpdatesJoiner;
@property(nonatomic) int lastPortholeWidth;  // in cells
@property(nonatomic, strong) NSMutableArray<iTermContentNavigationShortcut *> *contentNavigationShortcuts;

- (void)addNote;
- (void)updateAlphaValue;
- (NSString *)selectedTextCappedAtSize:(int)maxBytes;
- (BOOL)_haveShortSelection;
- (BOOL)haveReasonableSelection;
- (BOOL)withRelativeCoord:(VT100GridAbsCoord)coord
                    block:(void (^ NS_NOESCAPE)(VT100GridCoord coord))block;
- (BOOL)withRelativeCoordRange:(VT100GridAbsCoordRange)range
                         block:(void (^ NS_NOESCAPE)(VT100GridCoordRange))block;
- (NSRect)adjustedDocumentVisibleRect;

// exposed for tests
- (void)setDrawingHelperIsRetina:(BOOL)isRetina;
- (void)copySelectionWithStyles:(iTermSelection *)selection;
- (void)copySelection:(iTermSelection *)selection;
- (void)scrollToCenterLine:(int)line;

@end

