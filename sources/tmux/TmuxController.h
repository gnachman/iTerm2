//
//  TmuxController.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"
#import "iTermInitialDirectory.h"
#import "iTermTmuxSessionObject.h"
#import "TmuxGateway.h"
#import "TmuxLayoutParser.h"
#import "WindowControllerInterface.h"

@class iTermFontTable;
@class iTermTmuxClientTracker;
@class iTermVariableScope;
@class PTYSession;
@class PTYTab;
@class PseudoTerminal;
@class EquivalenceClassSet;

// Posted just before sessions change (names, addition, deletion)
extern NSString *const kTmuxControllerSessionsWillChange;
// Posted when sessions change (names, addition, deletion)
extern NSString *const kTmuxControllerSessionsDidChange;
// Posted after detaching
extern NSString *const kTmuxControllerDetachedNotification;
// Posted when a window changes.
extern NSString *const kTmuxControllerWindowsChangeNotification;
// Posted when a window changes name
extern NSString *const kTmuxControllerWindowWasRenamed;
// Posted when a window opens
extern NSString *const kTmuxControllerWindowDidOpen;
// Posted when a window closes
extern NSString *const kTmuxControllerWindowDidClose;
// Posted when the attached session changes
extern NSString *const kTmuxControllerAttachedSessionDidChange;
// Posted when a session changes name
extern NSString *const kTmuxControllerSessionWasRenamed;
// Posted when set-titles option changes. Object is tmux controller.
extern NSString *const kTmuxControllerDidFetchSetTitlesStringOption;
// Posted before sending kill-window
extern NSString *const iTermTmuxControllerWillKillWindow;
// Posted when one or more windows changes hidden status
extern NSString *const kTmuxControllerDidChangeHiddenWindows;

@protocol iTermTmuxControllerSession<NSObject>
- (void)tmuxControllerSessionSetTTL:(NSTimeInterval)ttl redzone:(BOOL)redzone;
- (void)revealIfTabSelected;
@end

@interface TmuxController : NSObject

@property(nonatomic, readonly) TmuxGateway *gateway;
@property(nonatomic, retain) NSMutableDictionary *windowPositions;
@property(nonatomic, copy) NSString *sessionName;
@property(nonatomic, copy) NSArray<iTermTmuxSessionObject *> *sessionObjects;
@property(nonatomic, assign) BOOL ambiguousIsDoubleWidth;
@property(nonatomic, assign) NSInteger unicodeVersion;
@property(nonatomic, readonly) NSString *clientName;
@property(nonatomic, readonly) int sessionId;
@property(nonatomic, readonly) BOOL hasOutstandingWindowResize;
@property(nonatomic, readonly, getter=isAttached) BOOL attached;
@property(nonatomic, readonly) BOOL detaching;
@property(nonatomic, copy) Profile *sharedProfile;
@property(nonatomic, readonly) NSDictionary *sharedFontOverrides;
@property(nonatomic, readonly) NSDictionary *sharedKeyMappingOverrides;
@property(nonatomic, readonly) NSString *sessionGuid;
@property(nonatomic, readonly) BOOL variableWindowSize;
@property(nonatomic, readonly) BOOL shouldSetTitles;
@property(nonatomic, readonly) BOOL serverIsLocal;
// Identity of the tmux server this controller is attached to, as reported by the server
// itself. Together with sessionId these are the three fields of $TMUX, which is how a
// process running in a pane names its server and session. Both are nil/0 until the
// response to loadServerPID arrives, and serverSocketPath stays nil on tmux < 2.2, which
// has no #{socket_path}.
@property(nonatomic, readonly) NSString *serverSocketPath;
@property(nonatomic, readonly) pid_t serverPid;
// Whether the serverIsLocal determination has ever actually succeeded, as opposed to the lookup
// failing. serverIsLocal is NO in both the settled-remote and the not-yet-determined case, and
// callers that report on the difference need to tell them apart.
@property(nonatomic, readonly) BOOL serverLocalityKnown;

// Which machine this controller's tmux server runs on, for pane addressing: nil for this Mac,
// otherwise the clientUniqueID of the SSH-integration conductor carrying the gateway session.
// Forwarded from the gateway's delegate rather than read from a session directly, so this file
// keeps no dependency on PTYSession.
@property(nonatomic, readonly) NSString *serverOriginIdentifier;

// How an attached controller tells `it2` in a pane how to reach it: one global user option per
// attacher, @it2_client_<hex of tmux client name> = c_<hex of JSON record>. Exposed for tests;
// see advertiseIT2Client for the design.
+ (NSString *)it2ClientOptionNameForTmuxClientName:(NSString *)clientName;
+ (NSString *)commandAdvertisingIT2ClientRecord:(NSDictionary<NSString *, NSString *> *)record
                                 tmuxClientName:(NSString *)clientName;
+ (NSString *)commandWithdrawingIT2ClientRecordForTmuxClientName:(NSString *)clientName;

// Remove this controller's own it2 client record from the server. Call before a clean detach,
// while the gateway can still send.
- (void)withdrawIT2ClientRecord;

// Re-run the serverIsLocal determination if it has never actually succeeded. Reading serverIsLocal
// does this for you; call it directly only to refresh without reading. That test asks the
// kernel for the name of the process with the server's pid, and a miss is indistinguishable from
// "remote": sysctl can return zero bytes for a pid that is momentarily unreferenceable (see
// +[iTermLSOF nameFailureDiagnosisForPid:]). Because the answer was computed once at connect time
// and cached, a single unlucky lookup used to mark a local server remote for the life of the
// connection. Cheap and a no-op once the answer is known.
- (void)refreshServerLocalityIfUnknown;
@property(nonatomic, readonly) NSString *defaultTerminal;
@property(nonatomic) NSRect initialWindowHint;
@property(nonatomic, readonly) BOOL detached;
@property(nonatomic, readonly) NSArray<NSNumber *> *windowPaneIDs;

// OSC query handling properties (tmux 3.6+)
@property(nonatomic, readonly) BOOL shouldHandleOSC4Queries;  // tmux >= 3.6
@property(nonatomic, readonly) BOOL shouldHandleOSC52Queries; // tmux > 3.6 and get-clipboard >= 2 or tmux.36 and set-clipboard < 2
@property(nonatomic, readonly) BOOL isResponsibleForOSCQueries;  // Are we the designated responder?
@property(nonatomic, strong, readonly) iTermTmuxClientTracker *clientTracker;

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                     clientName:(NSString *)clientName
                        profile:(Profile *)profile
                   profileModel:(ProfileModel *)profileModel NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (Profile *)profileForWindow:(int)window;

// tmux's pane-border-status option for the given window, as last learned from
// list-windows. Defaults to off. Used to correct layout geometry (issue 12925).
- (iTermTmuxPaneBorderStatus)paneBorderStatusForWindow:(int)window;
- (void)setPaneBorderStatus:(iTermTmuxPaneBorderStatus)status forWindow:(int)window;
- (NSString *)perWindowSettingsForWindowWithGUID:(NSString *)terminalGUID;
- (NSString *)perTabSettingsForTabWithWindowID:(int)wid;
- (NSDictionary *)fontOverridesForWindow:(int)window;

- (void)openWindowsInitial;

- (void)openWindowWithId:(int)windowId
			 intentional:(BOOL)intentional
                 profile:(Profile *)profile;

- (void)openWindowWithId:(int)windowId
			  affinities:(NSArray *)affinities
			 intentional:(BOOL)intentional
                 profile:(Profile *)profile;

- (void)hideWindow:(int)windowId;

// Modifies a native tab to match the given server layout.
// Returns YES if you should call adjustWindowSizeIfNeededForTabs: after all tabs have been updated.
- (BOOL)setLayoutInTab:(PTYTab *)tab
              toLayout:(NSString *)layout
         visibleLayout:(NSString *)visibleLayout
                zoomed:(NSNumber *)zoomed;
- (void)adjustWindowSizeIfNeededForTabs:(NSArray<PTYTab *> *)tabs;

- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid;
- (void)sessionsChanged;
- (void)session:(int)sessionId renamedTo:(NSString *)newName;
- (void)windowsChanged;
- (void)windowWasRenamedWithId:(int)id to:(NSString *)newName;

// Call `block` when a window pane with `wp` is registered. If one is already registered, it will be called asynchronously.
- (void)whenPaneRegistered:(int)wp call:(void (^)(PTYSession<iTermTmuxControllerSession> *))block;

- (PTYSession<iTermTmuxControllerSession> *)sessionForWindowPane:(int)windowPane;
- (PTYTab *)window:(int)window;
- (NSArray<PTYSession<iTermTmuxControllerSession> *> *)sessionsInWindow:(int)window;
- (void)registerSession:(PTYSession<iTermTmuxControllerSession> *)aSession
               withPane:(int)windowPane
               inWindow:(int)window;
- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session;
- (void)changeWindow:(int)window tabTo:(PTYTab *)tab;
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes windowID:(int)windowID;

// This should be called after the host sends an %exit command.
- (void)detach;
- (void)windowDidResize:(NSWindowController<iTermWindowController> *)term;
- (void)fitLayoutToWindows;
- (void)validateOptions;
- (void)ping;
- (void)sendPhonyCommand;
- (void)sendReport:(NSData *)report pane:(int)pane;
- (void)enablePauseModeIfPossible;
- (void)unpausePanes:(NSArray<NSNumber *> *)wps;
- (void)pausePanes:(NSArray<NSNumber *> *)wps;
- (void)didPausePane:(int)wp;

// Issue tmux commands to infer bounds on the version.
- (void)guessVersion;
- (void)loadTitleFormat;

- (void)setClientSize:(NSSize)size;
- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal;

// If completion is nonnull it will be called with the new window pane or -1 on error.
- (void)splitWindowPane:(int)wp
             vertically:(BOOL)splitVertically
                  scope:(iTermVariableScope *)scope
       initialDirectory:(iTermInitialDirectory *)initialDirectory
             completion:(void (^)(int wp))completion;

- (void)newWindowInSessionNumber:(NSNumber *)sessionNumber
                           scope:(iTermVariableScope *)scope
                initialDirectory:(iTermInitialDirectory *)initialDirectory;

- (void)selectPane:(int)windowPane;

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid;
- (NSSet<NSObject<NSCopying> *> *)savedAffinitiesForWindow:(NSString *)value;
- (NSSize)sizeOfSmallestWindowAmong:(NSSet<NSString *> *)siblings;

// nil: Open in a new window
// A string of a non-negative integer (e.g., @"2") means to open alongside a tmux window with that ID
// A string of a negative integer (e.g., @"-2") means to open in an iTerm2 window with abs(windowId)==window number.
// If affinity is given then the newly created tab will be considered "manually opened" which is
// used to determine the tab's eventual location in the tabbar.
- (void)newWindowWithAffinity:(NSString *)windowIdString
                         size:(NSSize)size
             initialDirectory:(iTermInitialDirectory *)initialDirectory
                        index:(NSNumber *)index
                        scope:(iTermVariableScope *)scope
                   completion:(void (^)(int))completion;

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore;
- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint;
- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling;

- (void)killWindowPane:(int)windowPane;
- (void)killWindow:(int)window;
- (void)unlinkWindowWithId:(int)windowId;
- (void)requestDetach;
- (void)renameWindowWithId:(int)windowId
           inSessionNumber:(NSNumber *)sessionNumber
                    toName:(NSString *)newName;

// Rename the window and save in tmux server setting.
- (void)setWindowTitleOverride:(NSString *)title
                        window:(int)windowId;
- (BOOL)canRenamePane;
- (void)renamePane:(int)windowPane toTitle:(NSString *)newTitle;
- (void)setHotkeyForWindowPane:(int)windowPane to:(NSDictionary *)hotkey;
- (NSDictionary *)hotkeyForWindowPane:(int)windowPane;

- (void)setTabColorString:(NSString *)colorString forWindowPane:(int)windowPane;
- (NSString *)tabColorStringForWindowPane:(int)windowPane;

- (void)linkWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSession;

- (void)moveWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber;

- (void)renameSessionNumber:(int)sessionNumber
                         to:(NSString *)newName;

- (void)killSessionNumber:(int)sessionNumber;
- (void)attachToSessionWithNumber:(int)sessionNumber;
- (void)addSessionWithName:(NSString *)sessionName;
// NOTE: If anything goes wrong the selector will not be called.
- (void)listWindowsInSessionNumber:(int)sessionNumber
                            target:(id)target
                          selector:(SEL)selector
                            object:(id)object;

- (void)listSessions;
- (void)saveAffinities;
- (void)saveWindowOrigins;
- (void)saveHiddenWindows;
- (void)savePerWindowSettings;
- (void)savePerTabSettings;

- (void)swapPane:(int)pane1 withPane:(int)pane2;
- (void)toggleZoomForPane:(int)pane;
- (void)setPartialWindowIdOrder:(NSArray *)partialOrder;
- (void)setCurrentWindow:(int)windowId;
- (void)checkForUTF8;
- (void)loadDefaultTerminal;
- (void)loadKeyBindings;
- (void)exitCopyMode;

- (void)clearHistoryForWindowPane:(int)windowPane;

- (void)setTmuxFontTable:(iTermFontTable *)fontTable
                hSpacing:(CGFloat)hs
                vSpacing:(CGFloat)vs
                  window:(int)window;
- (BOOL)windowIsHidden:(int)windowId;
- (void)setLayoutInWindow:(int)window toLayout:(NSString *)layout;
- (NSArray<PTYSession<iTermTmuxControllerSession> *> *)clientSessions;

- (void)setSize:(NSSize)size window:(int)window;

- (void)setEncodedUserVars:(NSString *)encodedUserVars forPane:(int)paneID;
- (void)setUserVariableWithKey:(NSString *)key
                         value:(NSString *)value
                          pane:(int)paneID;
- (NSDictionary<NSString *, NSString *> *)userVarsForPane:(int)paneID;
- (void)activeWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID;
- (void)activeWindowDidChangeTo:(int)windowID;
- (void)setCurrentLatency:(NSTimeInterval)latency forPane:(int)wp;
- (void)copyBufferToLocalPasteboard:(NSString *)bufferName;
- (void)restoreWindowFrame:(PseudoTerminal *)term;

// Called when a client attaches or changes session
- (void)clientSessionChanged:(NSString *)clientName;
// Called when a client detaches
- (void)clientDetached:(NSString *)clientName;
// Call this after attaching to initialize client tracker state
- (void)updateAttachedClientsWithCompletion:(void (^)(void))completion;

@end
