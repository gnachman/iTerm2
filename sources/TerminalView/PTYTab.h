// PTYTab abstracts the concept of a tab. This is attached to the tabview's identifier and is the
// owner of PTYSession.

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"
#import "iTermEncoderAdapter.h"
#import "PSMTabBarControl.h"
#import "PTYSession.h"
#import "PTYSplitView.h"
#import "PTYTabDelegate.h"
#import "WindowControllerInterface.h"
#import "Api.pbobjc.h"

@class FakeWindow;
@class iTermFloatingPaneView;
@protocol iTermTabScope;
@class iTermVariables;
@class iTermVariableScope;
@class PTYSession;
@class PTYTab;
@class SessionView;
@class SolidColorView;
@class TmuxController;

extern NSString *const iTermTabDidChangeWindowNotification;
// A float was added, moved, resized, restacked, hidden or shown. The object is the tab.
extern NSString *const iTermTabFloatingPanesDidChangeNotification;
extern NSString *const iTermSessionBecameKey;
extern NSString *const iTermCurrentSessionDidChange;
extern NSString *const PTYTabVariableTitleOverride;

extern NSString *const PTYTabArrangementOptionsOnlySessionID;
extern NSString *const PTYTabArrangementOptionsReplacementProfile;
extern NSString *const PTYTabArrangementOptionsReplacementSaveProgram;
extern NSString *const PTYTabArrangementOptionsPendingJumps;

// This implements NSSplitViewDelegate but it was an informal protocol in 10.5. If 10.5 support
// is eventually dropped, change this to make it official.
// What has happened in a tab's hidden floats, in increasing priority, as a tab's icon shows it.
typedef NS_ENUM(NSInteger, iTermHiddenFloatingPanesActivity) {
    iTermHiddenFloatingPanesActivityNone,
    iTermHiddenFloatingPanesActivityIdle,
    iTermHiddenFloatingPanesActivityNewOutput,
    iTermHiddenFloatingPanesActivityBell,
    iTermHiddenFloatingPanesActivityEnded
};

@interface PTYTab : NSObject <
  NSCopying,
  NSSplitViewDelegate,
  iTermUniquelyIdentifiable,
  PTYSessionDelegate,
  PTYSplitViewDelegate,
  PSMTabBarControlRepresentedObjectIdentifierProtocol>

@property(nonatomic, assign, getter=isBroadcasting) BOOL broadcasting;

// Parent controller. Always set. Equals one of realParent or fakeParent.
@property(nonatomic, weak) id<WindowControllerInterface> parentWindow;

// The real window controller (a PseudoTerminal), not the proxy that gets subbed
// in during instant replay. Prefer this over -parentWindow when you need the
// actual window controller rather than the proxy. `realParentWindow_` is weak and
// non-nil only while the parent is a PseudoTerminal*, so callers must handle nil.
- (NSWindowController<iTermWindowController> *)realParentWindow;

// uniqueId lazily auto-assigns a unique id unless you assign it a value first. It is never 0.
@property(nonatomic, assign) int uniqueId;
@property(nonatomic, readonly) BOOL isMaximized;
// Sessions ordered in a similar-to-reading-order fashion.
@property(nonatomic, readonly) NSArray *orderedSessions;
@property(nonatomic, readonly) NSArray<PTYSession *> *minimizedSessions;
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
// Aggregated tab status from all sessions (highest-priority wins)
@property(nonatomic, readonly) iTermSessionTabStatus *aggregatedTabStatus;
@property(nonatomic, readonly) VT100ScreenProgress progress;

// Size we should report to fit the current layout
@property(nonatomic, readonly) NSSize tmuxSize;
@property(nonatomic, copy) NSString *tmuxWindowName;
@property (readonly, getter=isTmuxTab) BOOL tmuxTab;
@property (nonatomic, readonly) PTYTabState state;
@property (nonatomic, readonly) iTermVariables *variables;
@property (nonatomic, readonly) iTermVariables *userVariables;

// NOTE: This isn't actually the root view for tmux integration settings.
@property (nonatomic, readonly) NSView *rootView;
@property (nonatomic, readonly) NSView *realRootView;

// If non-nil, this session may not change size. This is useful when you want
// to change a session's size. You can resize it, lock it, and then
// adjustSubviews of the splitview (ordinarily done by a call to -[PTYTab
// setSize:]).
@property(nonatomic, weak) PTYSession *lockedSession;

// A string that overrides the default behavior of using the active session's title.
// Set to nil to use the default behavior. This is a swifty string.
@property (nonatomic, copy) NSString *titleOverride;
@property(nonatomic, getter=isPinned) BOOL pinned;
// Identifier of the tab group this tab belongs to, or nil. Source of
// truth for group membership (persisted in the tab arrangement); the
// window controller pushes it to the tab bar via
// -setTabGroupIdentifier:forTabViewItem:.
@property (nonatomic, copy) NSString *tabGroupID;
// The tab group's definition (its name and color) travels on every member
// tab, so it persists and moves across windows with the tabs and there is no
// separate registry to keep in sync. All tabs sharing a tabGroupID carry the
// same name/color; membership mutations copy them and rename fans them out.
// Meaningful only when tabGroupID is non-nil.
@property (nonatomic, copy) NSString *tabGroupName;
@property (nonatomic, copy) NSColor *tabGroupColor;
// Whether this tab's group is collapsed (its members are hidden in the tab bar
// but remain in the NSTabView). Like name/color it rides every member of the
// group; the invariant "the active tab is never in a collapsed group" is
// enforced by PseudoTerminal. Meaningful only when tabGroupID is non-nil.
@property (nonatomic) BOOL tabGroupCollapsed;
// When this tab's group (tabGroupID) is a sub-group, the definition of its
// parent group. Nesting is one level deep: a parent never has a parent. Like
// the fields above, the parent's definition rides every tab of every one of its
// sub-groups (and its own direct members carry it as their tabGroupID/Name/...),
// so a parent with no direct members still exists through its sub-groups.
// tabGroupParentID is nil for a top-level group; the others are meaningful only
// when it is set.
@property (nonatomic, copy) NSString *tabGroupParentID;
@property (nonatomic, copy) NSString *tabGroupParentName;
@property (nonatomic, copy) NSColor *tabGroupParentColor;
@property (nonatomic) BOOL tabGroupParentCollapsed;
// tabGroupParentID when the tab is grouped and its group is a sub-group, else
// nil. Use this, not tabGroupParentID, wherever a stale parent on an ungrouped
// tab must not count.
@property (nonatomic, readonly) NSString *nestedTabGroupParentID;
// The outermost group this tab belongs to: its parent group if it is in a
// sub-group, else tabGroupID.
@property (nonatomic, readonly) NSString *tabGroupTopLevelID;
// YES if the tab belongs to `groupID` directly or through a sub-group of it.
- (BOOL)isInTabGroup:(NSString *)groupID;
// YES if the tab is hidden in the tab bar because its group or its group's
// parent is collapsed.
@property (nonatomic, readonly) BOOL tabGroupHidden;
// Read and write the definition of `groupID` as carried by this tab, which may
// be its own group or its group's parent. No-op/nil/NO if the tab is not in it.
- (NSString *)nameOfTabGroup:(NSString *)groupID;
- (NSColor *)colorOfTabGroup:(NSString *)groupID;
- (BOOL)isTabGroupCollapsed:(NSString *)groupID;
- (void)setName:(NSString *)name ofTabGroup:(NSString *)groupID;
- (void)setColor:(NSColor *)color ofTabGroup:(NSString *)groupID;
- (void)setCollapsed:(BOOL)collapsed ofTabGroup:(NSString *)groupID;
// Clear the parent-group fields (the tab's group becomes top-level).
- (void)clearTabGroupParent;
@property(nonatomic, readonly) NSString *title;  // the effective title
@property (nonatomic, readonly) iTermVariableScope<iTermTabScope> *variablesScope;
@property(nonatomic, readonly) iTermMetalUnavailableReason metalUnavailableReason;
@property(nonatomic) BOOL deferFontChanges;

// If true, report that the tab's ideal size is its currentSize.
@property(nonatomic) BOOL reportIdeal;
@property(nonatomic, readonly) NSArray<PTYSession *> *sessionsAtTop;
@property(nonatomic, readonly) NSArray<PTYSession *> *sessionsAtLeft;
@property(nonatomic, readonly) NSArray<PTYSession *> *sessionsAtRight;
@property(nonatomic, readonly) NSArray<PTYSession *> *sessionsAtBottom;

+ (NSSize)sizeForTmuxWindowWithAffinity:(NSString *)affinity
                             controller:(TmuxController *)controller;

// Save the contents of all sessions. Used during window restoration so that if
// the sessions are later restored from a saved arrangement during startup
// activities, their contents can be rescued.
+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement;
+ (void)registerBuiltInFunctions;
+ (NSSize)cellSizeForBookmark:(Profile *)bookmark;

+ (void)drawArrangementPreview:(NSDictionary*)arrangement frame:(NSRect)frame dark:(BOOL)dark;

+ (PTYTab *)tabWithArrangement:(NSDictionary*)arrangement
                         named:(NSString *)arrangementName
                    inTerminal:(NSWindowController<iTermWindowController> *)term
               hasFlexibleView:(BOOL)hasFlexible
                       viewMap:(NSDictionary<NSNumber *, SessionView *> *)viewMap
                    sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap
                tmuxController:(TmuxController *)tmuxController
            partialAttachments:(NSDictionary *)partialAttachments
              reservedTabGUIDs:(NSSet<NSString *> *)reservedTabGUIDs
                       options:(NSDictionary *)options;

+ (NSDictionary<NSString *, PTYSession *> *)sessionMapWithArrangement:(NSDictionary *)arrangement
                                                             sessions:(NSArray *)sessions;

+ (PTYTab *)openTabWithTmuxLayout:(NSMutableDictionary *)parseTree
                    visibleLayout:(NSMutableDictionary *)visibleParseTree
                       inTerminal:(NSWindowController<iTermWindowController> *)term
                       tmuxWindow:(int)tmuxWindow
                   tmuxController:(TmuxController *)tmuxController
                 openInBackground:(BOOL)openInBackground;

+ (BOOL)arrangement:(NSDictionary *)arrangement
         passesTest:(BOOL (^NS_NOESCAPE)(NSDictionary *candidate))closure;
+ (NSDictionary *)modifiedArrangement:(NSDictionary *)arrangement
                              mutator:(NSDictionary *(^)(NSDictionary *))mutator;

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile;

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD;

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                  settingCustomLocale:(NSString *)lang;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                       profileMutator:(Profile *(^)(Profile *))profileMutator;
// The tab arrangement without its tab group parent, so its group restores as a
// top-level group.
+ (NSDictionary *)arrangementRemovingTabGroupParent:(NSDictionary *)arrangement;

+ (NSDictionary *)arrangementForSessionWithGUID:(NSString *)sessionGUID
                                  inArrangement:(NSDictionary *)arrangement;

- (NSDictionary *)arrangementWithOnlySession:(PTYSession *)session
                                     profile:(Profile *)profile
                                 saveProgram:(BOOL)saveProgram
                                pendingJumps:(NSArray<iTermSSHReconnectionInfo *> *)pendingJumps;

+ (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                  completion:(void (^)(NSDictionary *))completion;

// init/dealloc
- (instancetype)initWithSession:(PTYSession *)session
                   parentWindow:(NSWindowController<iTermWindowController> *)parentWindow;
- (instancetype)initWithRoot:(NSSplitView *)root
                    sessions:(NSMapTable<SessionView *, PTYSession *> *)sessions;

- (void)setRoot:(NSSplitView *)newRoot;

// Restore the window's first responder to the active session's main
// responder. A view-hierarchy rebuild (e.g. apply_layout) reparents
// SessionViews, which severs the responder chain even when the active
// session pointer is unchanged; setActiveSession: only calls
// makeFirstResponder: when the active session actually changes, so
// callers that rebuild the tree must restore focus explicitly.
- (void)restoreActiveSessionFirstResponder;

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
- (NSArray<SessionView *> *)sessionViews;
- (void)setFilter:(NSString *)query inSession:(PTYSession *)oldSession;
- (void)replaceActiveSessionWithSyntheticSession:(PTYSession *)newSession;
- (void)unmaximizeTemporarilyAndActivate:(PTYSession *(^)(void))sessionPicker;
- (void)setDvrInSession:(PTYSession*)newSession;
- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession;

// An image of the tab’s split panes as laid out, each drawn from its session’s terminal content
// snapshot. Floating panes are not included. Returns nil if there is nothing to draw.
- (NSImage *)contentSnapshot;

// Screenshot mode: creates synthetic session for interactive redaction selection
- (PTYSession *)enterScreenshotModeForSession:(PTYSession *)liveSession;
- (void)exitScreenshotModeForSession:(PTYSession *)syntheticSession;

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

- (NSSize)_minSessionSize:(SessionView*)sessionView respectPinning:(BOOL)respectPinning;
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
- (NSDictionary *)arrangement;
- (NSDictionary *)arrangementForDuplication;

- (void)notifyWindowChanged;
// NOTE: Do not call this directly. It doesn't handle tmux correctly.
- (void)maximize;
- (void)toggleMaximizeSession:(PTYSession *)session;
// Does any session in this tab require prompt on close?
- (iTermPromptOnCloseReason *)promptOnCloseReason;

// All sessions: the tiled ones first, then the floating ones back to front.
- (NSArray<PTYSession *> *)sessions;

// Sessions in the tiled layout only. May be empty in a tmux tab whose window has only floating
// panes.
- (NSArray<PTYSession *> *)tiledSessions;

// Floating sessions, back to front.
- (NSArray<PTYSession *> *)floatingSessions;
@property(nonatomic, readonly) NSArray<iTermFloatingPaneView *> *floatingPanes;
- (BOOL)sessionIsFloating:(PTYSession *)session;
- (iTermFloatingPaneView *)floatingPaneForSession:(PTYSession *)session;

// Adds an existing session's view as a float sized and placed like a new one: the largest grid
// that fits 80% of the tab, centered. The frame follows from the grid.
- (iTermFloatingPaneView *)installNewlyPlacedFloatingSession:(PTYSession *)session;
// Adds an existing session's view as a float with the given outline frame, keeping its grid. A
// route that adds a float to a live tab finishes with didInstallFloatingPane:session:activate: once
// the float is placed. Restoring an arrangement and adopting tmux's floats do not: their tab is
// still being built, and the underlays, blur and dimming are settled once the layout is complete.
- (iTermFloatingPaneView *)installFloatingSession:(PTYSession *)session outlineFrame:(NSRect)frame;
// The same, for a caller that places the float right after, which sets its frame from its grid.
- (iTermFloatingPaneView *)installFloatingSessionAwaitingPlacement:(PTYSession *)session;
// The common tail of every route that adds a float to a live tab, once its pane is installed and
// placed: the underlay, focus, blur and dimming.
- (void)didInstallFloatingPane:(iTermFloatingPaneView *)pane
                       session:(PTYSession *)session
                      activate:(BOOL)activate;

// Hides or shows every floating pane in the tab. Their sessions keep running. Activating a float
// shows them again.
@property(nonatomic) BOOL floatingPanesHidden;

// Hides floats for a moment without the effects of the hide toggle.
@property(nonatomic) BOOL floatingPanesTemporarilyHidden;

// A float that stays visible while floats are temporarily hidden, such as the source of Move
// Session to Split Pane, which shows how to cancel.
@property(nonatomic, weak) PTYSession *floatingSessionShownWhileTemporarilyHidden;

// Change a float's z-order.
- (void)bringFloatingPaneToFront:(iTermFloatingPaneView *)pane;
- (void)sendFloatingPaneToBack:(iTermFloatingPaneView *)pane;

// Arrangement helpers for floating panes.
+ (NSDictionary *)arrangementWithoutFloatingPanes:(NSDictionary *)arrangement;
+ (NSDictionary *)floatingPaneRecordForSessionWithGUID:(NSString *)guid inArrangement:(NSDictionary *)arrangement;

// The sessions a tmux layout change may reuse for its tiled panes, keyed by tmux pane id (a
// filtered pane's synthetic session by its live session's pane). Non-tmux sessions and panes that
// are floating in the new layout are left out.
+ (NSDictionary<NSNumber *, PTYSession *> *)tiledSessionsByTmuxPaneFromSessions:(NSArray<PTYSession *> *)sessions
                                                                   floatingPanes:(NSSet<NSNumber *> *)floatingPanes;
// The tmux pane a session shows in a tmux layout: its own, or for a filtered pane's synthetic
// session, its live session's. -1 if it is not a tmux pane (a native session's id reads as 0,
// which is tmux's pane %0).
+ (int)tmuxLayoutPaneForSession:(PTYSession *)session;
// The session among `sessions` that shows tmux pane `wp`, by +tmuxLayoutPaneForSession:, or nil.
+ (PTYSession *)sessionShowingTmuxPane:(int)wp amongSessions:(NSArray<PTYSession *> *)sessions;
// The sessions left over from a tmux layout change that tmux made floating rather than closed.
+ (NSArray<PTYSession *> *)sessionsBecomingTmuxFloatsAmong:(NSArray<PTYSession *> *)sessions
                                             floatingPanes:(NSSet<NSNumber *> *)floatingPanes;
- (void)addRevivedFloatingSession:(PTYSession *)session fromArrangement:(NSDictionary *)arrangement;
// Undo close of a float whose undo window ran out: create a session from the archived session
// arrangement in the float's record and put it back where the record says it was. Returns the new
// session, or nil if the record could not be restored.
- (PTYSession *)addArchivedFloatingSessionWithGUID:(NSString *)guid fromArrangement:(NSDictionary *)arrangement;

// Whether the user may resize the float or take it out of the float now.
- (BOOL)floatingPaneCanResize:(iTermFloatingPaneView *)pane;

// For a native float: set its grid within the tab and return YES. NO for any other session.
- (BOOL)sessionResizeFloatingPane:(PTYSession *)session columns:(int)columns rows:(int)rows;

// Tells API clients that a float was added, moved, resized, restacked, hidden or shown.
- (void)floatingPanesDidChange;

// What has happened in the hidden floats since they were hidden.
@property(nonatomic, readonly) iTermHiddenFloatingPanesActivity hiddenFloatingPanesActivity;

// The tiled session with the highest activity counter.
- (PTYSession *)mostRecentlyActiveTiledSession;

// The session a split aimed at `session` should actually split. A native float holds one session,
// so splits aimed at one go to the most recently active tiled session instead.
- (PTYSession *)splitTargetForSession:(PTYSession *)session;

- (void)removeSession:(PTYSession *)aSession;
// Removes a session the caller puts back in this tab at once, as a float or as a tiled pane. The
// active session is unchanged, even if it is this one, so no successor is activated, no other
// pane's activity counter changes, and the pane used most recently stays the one the user last
// worked in. Nothing is notified of the removal: the install that follows renumbers the panes and
// tells the window, once the tab is consistent again. Once the session is back, the caller makes it
// active with setActiveSessionRestoringFocus: if it should be.
- (void)removeSessionForReinstallation:(PTYSession *)aSession;
// Makes a session active. If it already was, as after removeSessionForReinstallation:, its view
// leaving the window took keyboard focus from it, which this gives back.
- (void)setActiveSessionRestoringFocus:(PTYSession *)session;

// Anyone changing the number of sessions must call this after the sessions
// are "well formed".
- (void)numberOfSessionsDidChange;
- (BOOL)updatePaneTitles;
- (void)updateSessionOrdinals;

// sessionKeepingGrid's views are laid out but its grid is not resized. This is for the session a
// zoomed layout will maximize, since shrinking it to its hidden split size first would discard rows
// tmux won't redraw.
- (void)resizeViewsInViewHierarchy:(NSView *)view
                      forNewLayout:(NSMutableDictionary *)parseTree
                sessionKeepingGrid:(PTYSession *)sessionKeepingGrid;
- (void)reloadTmuxLayout;
// Size we are given the current layout

- (void)setTmuxLayout:(NSMutableDictionary *)parseTree
        visibleLayout:(NSMutableDictionary *)visibleParseTree
       tmuxController:(TmuxController *)tmuxController
               zoomed:(NSNumber *)zoomed;
// Returns true if the tmux layout is too large for the window to accommodate.
- (BOOL)updatedTmuxLayoutRequiresAdjustment;
// tmux changed which panes have no border (pane-border-lines none). Borderless floats hide their
// title bars.
- (void)tmuxPaneBordersDidChange;

// Whether a tiled pane can become a float or a float a tiled pane, as far as tmux is concerned. It
// refuses both while the window is zoomed (cmd-break-pane.c, cmd-join-pane.c). Raising, moving and
// resizing a float are allowed then (resizing unzooms), so this is separate from
// tmuxAllowsChangingFloatingPanes. Always YES natively.
- (BOOL)tmuxAllowsChangingWhichPanesFloat;

// Whether the floats can be moved, resized, raised or docked. tmux 3.7 has floating panes but no
// commands to change them, so they only show.
- (BOOL)tmuxAllowsChangingFloatingPanes;
- (TmuxController *)tmuxController;

- (void)setTmuxFontTable:(iTermFontTable *)fontTable
                hSpacing:(double)hs
                vSpacing:(double)vs;

- (void)moveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;
- (BOOL)canMoveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally;

- (void)swapSession:(PTYSession *)session1 withSession:(PTYSession *)session2;

- (void)didAddToTerminal:(NSWindowController<iTermWindowController> *)term
         withArrangement:(NSDictionary *)arrangement;

- (void)replaceWithContentsOfTab:(PTYTab *)tabToGut;

- (NSDictionary*)arrangementWithContents:(BOOL)contents;
- (BOOL)encodeWithContents:(BOOL)contents
                   encoder:(id<iTermEncoderAdapter>)encoder;
- (BOOL)encodeWithContents:(BOOL)contents
            constructIdMap:(BOOL)constructIdMap
                   encoder:(id<iTermEncoderAdapter>)encoder
                   options:(NSDictionary *)options;
+ (BOOL)encodeWithContents:(BOOL)contents
            constructIdMap:(BOOL)constructIdMap
                   encoder:(id<iTermEncoderAdapter>)encoder
                   options:(NSDictionary *)options
             activeSession:(PTYSession *)activeSession
                   tabGuid:(NSString *)guid
             titleOverride:(NSString *)titleOverride
               isMaximized:(BOOL)isMaximized
          savedArrangement:(NSDictionary *)savedArrangement
                     idMap:(NSMutableDictionary<NSNumber *, SessionView *> *)idMap
                      root:(NSView *)root
         sessionViewFinder:(SessionView *(^NS_NOESCAPE)(NSString *guid))sessionViewFinder
             sessionFinder:(PTYSession *(^NS_NOESCAPE)(SessionView *sessionView))sessionFinder;
+ (NSSplitView *)placeholderSplitViewForSession:(PTYSession *)session;

// Recompute the tab's title (honoring a title override, the tmux prefix, and the
// subtitle) and publish it to tab.title and the tab bar. Call this when something
// changed an input to the title without going through the session name controller,
// e.g. after a tmux window's layout is loaded or after the active session is
// swapped without -setActiveSession:.
- (void)updateTabTitle;

// Apply a profile's custom-tab-title template to a newly created tmux window's tab. The template is
// evaluated against this tab's scope so the tmux window is renamed to a concrete value rather than
// the literal template text. A blank result is ignored.
- (void)applyProfileCustomTabTitleForNewTmuxWindow:(NSString *)template;

// Update icons in tab.
- (void)updateIcon;

- (void)checkInvariants:(NSString *)when;
- (void)setTmuxWindowName:(NSString *)tmuxWindowName;

- (NSString *)tmuxPerTabSetting;
- (void)setPerTabSettings:(NSString *)setting;

- (void)updateUseMetal;
// Panes that count toward the limit on panes using the GPU renderer. Hidden floats don't.
@property (nonatomic, readonly) NSUInteger numberOfPanesCountingTowardMetalLimit;
- (ITMSplitTreeNode *)rootSplitTreeNode;
// The tab's floating panes, back to front, for the API.
- (NSArray<ITMFloatingPane *> *)floatingPaneMessages;

- (void)setSizesFromSplitTreeNode:(ITMSplitTreeNode *)node;
- (void)arrangeSplitPanesEvenly;

// Recursively distributes available space evenly across siblings of the
// given split view. Operates on the live hierarchy without needing
// arrangement-frame pre-computation. Short-circuits to
// `arrangeTmuxSplitPanesEvenly` for tmux integration tabs.
- (void)arrangeSplitPanesEvenlyInSplitView:(NSSplitView *)splitView;

// Fit each session view to its scroll view. Used after view hierarchy
// changes to propagate sizes down without going through the
// arrangement-restore path.
- (void)fitSubviewsToRoot;

// Returns the PTYSession that owns the given SessionView, or nil if the
// view is not part of this tab.
- (PTYSession *)sessionForSessionView:(SessionView *)sessionView;

// Adopts a session that has been detached from its previous tab via
// `removeSession:` and is now parented (visually) in this tab's split
// tree. Updates the view-to-session map and the session's delegate.
// Used by the layout-application API for cross-tab moves.
- (void)adoptSession:(PTYSession *)session;

// Restore the window's first responder to the active session after a
// view-hierarchy rebuild that reparented SessionViews. Reparenting (via
// setRoot:) detaches whatever view held first-responder status, leaving
// the window with a nil/stale responder. Unlike setActiveSession:, this
// fires even when the active session pointer is unchanged, which is the
// common case for an in-place reshape where the active pane survives.
// Guarded to the current tab to avoid making a non-visible textview the
// first responder (see the NSTextInput note in setActiveSession:).
- (void)restoreFirstResponderAfterViewHierarchyRebuild;

- (void)bounceMetal;
- (void)makeActive;
- (void)willDeselectTab;
- (void)didSelectTab;

@end
