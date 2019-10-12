// PTYTab abstracts the concept of a tab. This is attached to the tabview's identifier and is the
// owner of PTYSession.

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"
#import "PSMTabBarControl.h"
#import "PTYSession.h"
#import "PTYSplitView.h"
#import "PTYTabDelegate.h"
#import "WindowControllerInterface.h"
#import "Api.pbobjc.h"

@class FakeWindow;
@protocol iTermTabScope;
@class iTermVariables;
@class iTermVariableScope;
@class PTYSession;
@class PTYTab;
@class SessionView;
@class SolidColorView;
@class TmuxController;

extern NSString *const iTermTabDidChangeWindowNotification;
extern NSString *const iTermSessionBecameKey;
extern NSString *const PTYTabVariableTitleOverride;

// This implements NSSplitViewDelegate but it was an informal protocol in 10.5. If 10.5 support
// is eventually dropped, change this to make it official.
@interface PTYTab : NSObject <
  NSCopying,
  NSSplitViewDelegate,
  PTYSessionDelegate,
  PTYSplitViewDelegate,
  PSMTabBarControlRepresentedObjectIdentifierProtocol>

@property(nonatomic, assign, getter=isBroadcasting) BOOL broadcasting;

// Parent controller. Always set. Equals one of realParent or fakeParent.
@property(nonatomic, weak) id<WindowControllerInterface> parentWindow;

// uniqueId lazily auto-assigns a unique id unless you assign it a value first. It is never 0.
@property(nonatomic, assign) int uniqueId;
@property(nonatomic, readonly) BOOL isMaximized;
// Sessions ordered in a similar-to-reading-order fashion.
@property(nonatomic, readonly) NSArray *orderedSessions;
@property(nonatomic, weak) id<PTYTabDelegate> delegate;

// While activeSession is not retained, it should only ever refer to a session that belongs to
// this tab, and is thus retained through the view-to-session map.
@property(nonatomic, weak) PTYSession *activeSession;
@property(nonatomic, weak) NSTabViewItem *tabViewItem;

// These values are observed by PSMTTabBarControl:
// Tab number for display
@property(nonatomic, assign) int objectCount;
// Icon to display in tab
@property(nonatomic, retain) NSImage *icon;

// Size we should report to fit the current layout
@property(nonatomic, readonly) NSSize tmuxSize;
@property(nonatomic, copy) NSString *tmuxWindowName;
@property (readonly, getter=isTmuxTab) BOOL tmuxTab;
@property (nonatomic, readonly) PTYTabState state;
@property (nonatomic, readonly) iTermVariables *variables;
@property (nonatomic, readonly) iTermVariables *userVariables;

// If non-nil, this session may not change size. This is useful when you want
// to change a session's size. You can resize it, lock it, and then
// adjustSubviews of the splitview (ordinarily done by a call to -[PTYTab
// setSize:]).
@property(nonatomic, weak) PTYSession *lockedSession;

// A string that overrides the default behavior of using the active session's title.
// Set to nil to use the default behavior. This is a swifty string.
@property (nonatomic, copy) NSString *titleOverride;

@property (nonatomic, readonly) iTermVariableScope<iTermTabScope> *variablesScope;
@property(nonatomic, readonly) iTermMetalUnavailableReason metalUnavailableReason;
@property(nonatomic) BOOL deferFontChanges;

// If true, report that the tab's ideal size is its currentSize.
@property(nonatomic) BOOL reportIdeal;

+ (NSSize)sizeForTmuxWindowWithAffinity:(NSString *)affinity
                             controller:(TmuxController *)controller;

// Save the contents of all sessions. Used during window restoration so that if
// the sessions are later restored from a saved arrangement during startup
// activities, their contents can be rescued.
+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement;
+ (void)registerBuiltInFunctions;

+ (void)drawArrangementPreview:(NSDictionary*)arrangement frame:(NSRect)frame;

+ (PTYTab *)openTabWithArrangement:(NSDictionary*)arrangement
                        inTerminal:(NSWindowController<iTermWindowController> *)term
                   hasFlexibleView:(BOOL)hasFlexible
                           viewMap:(NSDictionary<NSNumber *, SessionView *> *)viewMap
                        sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap;

+ (PTYTab *)tabWithArrangement:(NSDictionary*)arrangement
                    inTerminal:(NSWindowController<iTermWindowController> *)term
               hasFlexibleView:(BOOL)hasFlexible
                       viewMap:(NSDictionary<NSNumber *, SessionView *> *)viewMap
                    sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap
                tmuxController:(TmuxController *)tmuxController;

+ (NSDictionary<NSString *, PTYSession *> *)sessionMapWithArrangement:(NSDictionary *)arrangement
                                                             sessions:(NSArray *)sessions;

+ (PTYTab *)openTabWithTmuxLayout:(NSMutableDictionary *)parseTree
                       inTerminal:(NSWindowController<iTermWindowController> *)term
                       tmuxWindow:(int)tmuxWindow
                   tmuxController:(TmuxController *)tmuxController;

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile;

// init/dealloc
- (instancetype)initWithSession:(PTYSession *)session
                   parentWindow:(NSWindowController<iTermWindowController> *)parentWindow;
- (instancetype)initWithRoot:(NSSplitView *)root
                    sessions:(NSMapTable<SessionView *, PTYSession *> *)sessions;

- (void)setRoot:(NSSplitView *)newRoot;

// This is safe to call when there may be a maximized pane.
- (void)setActiveSessionPreservingMaximization:(PTYSession *)session;

- (NSRect)absoluteFrame;
- (int)indexOfSessionView:(SessionView*)sessionView;

- (void)setFakeParentWindow:(FakeWindow*)theParent;

- (BOOL)isForegroundTab;
- (NSSize)sessionSizeForViewSize:(PTYSession *)aSession;
- (BOOL)fitSessionToCurrentViewSize:(PTYSession*)aSession;
// Fit session views to scroll views.
// This is useful for a tmux tab where scrollviews sizes are not tightly coupled to the
// SessionView size because autoresizing is turned off. When something changes, such as
// toggling the pane title bars, it's necessary to grow or shrink session views for a
// tight fit. This should be followed by fitting the window to tabs.
- (void)recompact;

- (PTYSession *)sessionWithViewId:(int)viewId;

// Should show busy indicator in tab?
- (BOOL)isProcessing;
- (BOOL)realIsProcessing;
- (void)setIsProcessing:(BOOL)aFlag;
- (void)terminateAllSessions;
- (NSArray *)windowPanes;
- (NSArray*)sessionViews;
- (void)replaceActiveSessionWithSyntheticSession:(PTYSession *)newSession;
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

- (NSSize)_minSessionSize:(SessionView*)sessionView;
- (NSSize)_sessionSize:(SessionView*)sessionView;

// If the active session's parent splitview has:
//   only one child: make its orientation vertical and add a new subview.
//   more than one child and a vertical orientation: add a new subview and return it.
//   more than one child and a horizontal orientation: add a new split subview with vertical orientation and add a sessionview subview to it and return that sessionview.
- (void)splitVertically:(BOOL)isVertical
             newSession:(PTYSession *)newSession
                 before:(BOOL)before
          targetSession:(PTYSession*)targetSession;

// A viewMap maps a session's unique ID to a SessionView. Views in the
// arrangement with matching session unique IDs will be assigned those
// SessionView's.
- (void)updateFlexibleViewColors;
- (NSDictionary*)arrangement;

- (void)notifyWindowChanged;
- (void)maximize;
// Does any session in this tab require prompt on close?
- (iTermPromptOnCloseReason *)promptOnCloseReason;

// Anyone changing the number of sessions must call this after the sessions
// are "well formed".
- (void)numberOfSessionsDidChange;
- (BOOL)updatePaneTitles;

- (void)resizeViewsInViewHierarchy:(NSView *)view
                      forNewLayout:(NSMutableDictionary *)parseTree;
- (void)reloadTmuxLayout;
// Size we are given the current layout

- (void)setTmuxLayout:(NSMutableDictionary *)parseTree
       tmuxController:(TmuxController *)tmuxController
               zoomed:(NSNumber *)zoomed;
// Returns true if the tmux layout is too large for the window to accommodate.
- (BOOL)layoutIsTooLarge;
- (TmuxController *)tmuxController;

- (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)hs
           vSpacing:(double)vs;

- (void)moveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;
- (BOOL)canMoveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;

- (void)swapSession:(PTYSession *)session1 withSession:(PTYSession *)session2;

- (void)didAddToTerminal:(NSWindowController<iTermWindowController> *)term
         withArrangement:(NSDictionary *)arrangement;

- (void)replaceWithContentsOfTab:(PTYTab *)tabToGut;

- (NSDictionary*)arrangementWithContents:(BOOL)contents;

// Update the tab's title from the active session's name. Needed for initializing the tab's title
// after setting up tmux tabs.
- (void)loadTitleFromSession;

// Update icons in tab.
- (void)updateIcon;

- (void)checkInvariants:(NSString *)when;
- (void)setTmuxWindowName:(NSString *)tmuxWindowName;

- (void)updateUseMetal NS_AVAILABLE_MAC(10_11);
- (ITMSplitTreeNode *)rootSplitTreeNode;

- (void)setSizesFromSplitTreeNode:(ITMSplitTreeNode *)node;
- (void)arrangeSplitPanesEvenly;
- (void)bounceMetal;

@end
