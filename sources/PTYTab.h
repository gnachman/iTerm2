// PTYTab abstracts the concept of a tab. This is attached to the tabview's identifier and is the
// owner of PTYSession.

#import <Cocoa/Cocoa.h>
#import "WindowControllerInterface.h"
#import "PSMTabBarControl.h"
#import "PTYSplitView.h"
#import "FutureMethods.h"

@class PTYSession;
@class FakeWindow;
@class SessionView;
@class TmuxController;
@class SolidColorView;

// This implements NSSplitViewDelegate but it was an informal protocol in 10.5. If 10.5 support
// is eventually dropped, change this to make it official.
@interface PTYTab : NSObject <
  NSCopying,
  NSSplitViewDelegate,
  PTYSplitViewDelegate,
  PSMTabBarControlRepresentedObjectIdentifierProtocol> {
    PTYSession* activeSession_;

    // Owning tab view item
    NSTabViewItem* tabViewItem_;

    id<WindowControllerInterface> parentWindow_;  // Parent controller. Always set. Equals one of realParent or fakeParent.
    NSWindowController<iTermWindowController> *realParentWindow_;  // non-nil only if parent is PseudoTerminal*. Implements optional methods of protocol.
    FakeWindow* fakeParentWindow_;  // non-nil only if parent is FakeWindow*

    // The tab number that is observed by PSMTabBarControl.
    int objectCount_;

    // The icon to display in the tab. Observed by PSMTabBarControl.
    NSImage* icon_;

    // Whether the session is "busy". Observed by PSMTabBarControl.
    BOOL isProcessing_;

    // Does any session have new output?
    BOOL newOutput_;

    // The root view of this tab. May be a SolidColorView for tmux tabs or the
    // same as root_ otherwise (the normal case).
    NSView *tabView_;  // weak

    // If there is a flexible root view, this is set and is the tabview's view.
    // Otherwise it is nil.
    SolidColorView *flexibleView_;

    // The root of a tree of split views whose leaves are SessionViews. The root is the view of the
    // NSTabViewItem.
    //
    // NSTabView -> NSTabViewItem -> NSSplitView (root) -> ... -> SessionView -> PTYScrollView -> etc.
    NSSplitView* root_;

    // If non-nil, this session may not change size.
    PTYSession* lockedSession_;

    // The active pane is maximized, meaning there are other panes that are hidden.
    BOOL isMaximized_;
    NSMutableDictionary* idMap_;  // maps saved session id to ptysession.
    NSDictionary* savedArrangement_;  // layout of splitters pre-maximize
    NSSize savedSize_;  // pre-maximize active session size.

    // If true, report that the tab's ideal size is its currentSize.
    BOOL reportIdeal_;

    // If this window is a tmux client, this is the window number defined by
    // the tmux server. -1 if not a tmux client.
    int tmuxWindow_;

    // If positive, then a tmux-originated resize is in progress and splitter
    // delegates won't interfere.
    int tmuxOriginatedResizeInProgress_;

    // The tmux controller used by all sessions in this tab.
    TmuxController *tmuxController_;

    // The last tmux parse tree
    NSMutableDictionary *parseTree_;

    // Temporarily hidden live views (this is needed to hold a reference count).
    NSMutableArray *hiddenLiveViews_;  // SessionView objects

    NSString *tmuxWindowName_;

	// This tab broadcasts to all its sessions?
	BOOL broadcasting_;
}

@property(nonatomic, assign, getter=isBroadcasting) BOOL broadcasting;

// uniqueId lazily auto-assigns a unique id unless you assign it a value first. It is never 0.
@property(nonatomic, assign) int uniqueId;
@property(nonatomic, readonly) BOOL isMaximized;
// Sessions ordered in a similar-to-reading-order fashion.
@property(nonatomic, readonly) NSArray *orderedSessions;
// Save the contents of all sessions. Used during window restoration so that if
// the sessions are later restored from a saved arrangement during startup
// activities, their contents can be rescued.
+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement;

// init/dealloc
- (id)initWithSession:(PTYSession*)session;
- (id)initWithRoot:(NSSplitView*)root;
- (void)dealloc;
- (void)setRoot:(NSSplitView *)newRoot;

- (NSRect)absoluteFrame;
- (PTYSession*)activeSession;
- (void)setActiveSession:(PTYSession*)session;
- (NSTabViewItem *)tabViewItem;
- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem;
- (void)previousSession;
- (void)nextSession;
- (int)indexOfSessionView:(SessionView*)sessionView;

- (void)setLockedSession:(PTYSession*)lockedSession;
- (id<WindowControllerInterface>)parentWindow;
- (NSWindowController<iTermWindowController> *)realParentWindow;
- (void)setParentWindow:(NSWindowController<iTermWindowController> *)theParent;
- (void)setFakeParentWindow:(FakeWindow*)theParent;
- (FakeWindow*)fakeWindow;

- (void)setBell:(BOOL)flag;
- (void)nameOfSession:(PTYSession*)session didChangeTo:(NSString*)newName;

- (BOOL)isForegroundTab;
- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;
- (NSSize)sessionSizeForViewSize:(PTYSession *)aSession;
- (BOOL)fitSessionToCurrentViewSize:(PTYSession*)aSession;
+ (NSDictionary *)tmuxBookmark;
// Fit session views to scroll views.
// This is useful for a tmux tab where scrollviews sizes are not tightly coupled to the
// SessionView size because autoresizing is turned off. When something changes, such as
// toggling the pane title bars, it's necessary to grow or shrink session views for a
// tight fit. This should be followed by fitting the window to tabs.
- (void)recompact;

// Tab index.
- (int)number;

- (PTYSession *)sessionWithViewId:(int)viewId;

- (int)realObjectCount;
// These values are observed by PSMTTabBarControl:
// Tab number for display
- (int)objectCount;
- (void)setObjectCount:(int)value;
// Icon to display in tab
- (NSImage *)icon;
- (void)setIcon:(NSImage *)anIcon;
// Should show busy indicator in tab?
- (BOOL)isProcessing;
- (BOOL)realIsProcessing;
- (void)setIsProcessing:(BOOL)aFlag;
- (BOOL)isActiveSession;
// Returns true if another update may be needed later (so the timer should be scheduled).
- (BOOL)updateLabelAttributes;
- (void)closeSession:(PTYSession*)session;
- (void)terminateAllSessions;
- (NSArray*)sessions;
- (NSArray *)windowPanes;
- (NSArray*)sessionViews;
- (BOOL)allSessionsExited;
- (void)setDvrInSession:(PTYSession*)newSession;
- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession;
- (BOOL)hasMultipleSessions;
- (NSSize)size;
- (void)setReportIdealSizeAsCurrent:(BOOL)v;
- (NSSize)currentSize;
- (NSSize)minSize;
- (void)setSize:(NSSize)newSize;
- (PTYSession*)sessionLeftOf:(PTYSession*)session;
- (PTYSession*)sessionRightOf:(PTYSession*)session;
- (PTYSession*)sessionAbove:(PTYSession*)session;
- (PTYSession*)sessionBelow:(PTYSession*)session;
- (BOOL)canSplitVertically:(BOOL)isVertical withSize:(NSSize)newSessionSize;
- (NSImage*)image:(BOOL)withSpaceForFrame;
- (BOOL)blur;
- (double)blurRadius;
- (void)recheckBlur;

- (NSSize)_minSessionSize:(SessionView*)sessionView;
- (NSSize)_sessionSize:(SessionView*)sessionView;

// Remove a dead session. This should be called from [session terminate] only.
- (void)removeSession:(PTYSession*)aSession;

// If the active session's parent splitview has:
//   only one child: make its orientation vertical and add a new subview.
//   more than one child and a vertical orientation: add a new subview and return it.
//   more than one child and a horizontal orientation: add a new split subview with vertical orientation and add a sessionview subview to it and return that sessionview.
- (SessionView*)splitVertically:(BOOL)isVertical
                         before:(BOOL)before
                  targetSession:(PTYSession*)targetSession;
- (NSSize)_recursiveMinSize:(NSSplitView*)node;
- (PTYSession*)_recursiveSessionAtPoint:(NSPoint)point relativeTo:(NSView*)node;

+ (void)drawArrangementPreview:(NSDictionary*)arrangement frame:(NSRect)frame;

// A viewMap maps a session's unique ID to a SessionView. Views in the
// arrangement with matching session unique IDs will be assigned those
// SessionView's.
+ (PTYTab *)openTabWithArrangement:(NSDictionary*)arrangement
                        inTerminal:(NSWindowController<iTermWindowController> *)term
                   hasFlexibleView:(BOOL)hasFlexible
                           viewMap:(NSDictionary *)viewMap;

+ (PTYTab *)tabWithArrangement:(NSDictionary*)arrangement
                    inTerminal:(NSWindowController<iTermWindowController> *)term
               hasFlexibleView:(BOOL)hasFlexible
                       viewMap:(NSDictionary *)viewMap;

+ (NSDictionary *)viewMapWithArrangement:(NSDictionary *)arrangement sessions:(NSArray *)sessions;

- (void)updateFlexibleViewColors;
- (NSDictionary*)arrangement;

- (void)notifyWindowChanged;
- (BOOL)hasMaximizedPane;
- (void)maximize;
- (void)unmaximize;
// Does any session in this tab require prompt on close?
- (BOOL)promptOnClose;

// Anyone changing the number of sessions must call this after the sessions
// are "well formed".
- (void)numberOfSessionsDidChange;
- (BOOL)updatePaneTitles;

- (void)resizeViewsInViewHierarchy:(NSView *)view
                      forNewLayout:(NSMutableDictionary *)parseTree;
- (void)reloadTmuxLayout;
+ (PTYTab *)openTabWithTmuxLayout:(NSMutableDictionary *)parseTree
                       inTerminal:(NSWindowController<iTermWindowController> *)term
                       tmuxWindow:(int)tmuxWindow
                   tmuxController:(TmuxController *)tmuxController;
+ (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)hs
           vSpacing:(double)vs;

// Size we should report to fit the current layout
- (NSSize)tmuxSize;
// Size we are given the current layout
- (NSSize)maxTmuxSize;
- (NSString *)tmuxWindowName;
- (void)setTmuxWindowName:(NSString *)tmuxWindowName;

- (int)tmuxWindow;
- (BOOL)isTmuxTab;
- (void)setTmuxLayout:(NSMutableDictionary *)parseTree
       tmuxController:(TmuxController *)tmuxController;
// Returns true if the tmux layout is too large for the window to accommodate.
- (BOOL)layoutIsTooLarge;
- (TmuxController *)tmuxController;

- (void)moveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;
- (BOOL)canMoveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;

- (void)swapSession:(PTYSession *)session1 withSession:(PTYSession *)session2;

- (void)addToTerminal:(NSWindowController<iTermWindowController> *)term
      withArrangement:(NSDictionary *)arrangement;

- (void)replaceWithContentsOfTab:(PTYTab *)tabToGut;

- (NSDictionary*)arrangementWithContents:(BOOL)contents;

#pragma mark NSSplitView delegate methods
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification;
// This is the implementation of splitViewDidResizeSubviews. The delegate method isn't called when
// views are added or adjusted, so we often have to call this ourselves.
- (void)_splitViewDidResizeSubviews:(NSSplitView*)splitView;
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex;
- (void)_recursiveRemoveView:(NSView*)theView;

@end
