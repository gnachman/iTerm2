#import "PTYTab.h"
#import "FakeWindow.h"
#import "IntervalMap.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermFlexibleView.h"
#import "iTermMoveTabToWindowBuiltInFunction.h"
#import "iTermNotificationController.h"
#import "iTermObject.h"
#import "iTermOrderedDictionary.h"
#import "iTermPowerManager.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"
#import "iTermPresentationController.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermProfilePreferences.h"
#import "iTermSwiftyString.h"
#import "iTermSwiftyStringGraph.h"
#import "iTermTmuxLayoutBuilder.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "MovePaneController.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSView+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+PSM.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "ProfilesWindowPreferencesViewController.h"
#import "PSMTabBarControl.h"
#import "PSMTabDragAssistant.h"
#import "PSMTabStyle.h"
#import "PTYNoteViewController.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYSession+ARC.h"
#import "SessionView.h"
#import "SolidColorView.h"
#import "TmuxDashboardController.h"
#import "TmuxLayoutParser.h"
#import "iTermTmuxOptionMonitor.h"
#import "VT100GridTypes.h"
#import "VT100ScreenMutableState.h"
#import "WindowControllerInterface.h"

#define PtyLog DLog

NSString *const iTermTabDidChangeWindowNotification = @"iTermTabDidChangeWindowNotification";
NSString *const iTermSessionBecameKey = @"iTermSessionBecameKey";
NSString *const iTermCurrentSessionDidChange = @"iTermCurrentSessionDidChange";

// No user output/idle alerts for a few seconds after a window is resized because there will be bogus bg activity
const int POST_WINDOW_RESIZE_SILENCE_SEC = 5;

static CGFloat WithGrainDim(BOOL isVertical, NSSize size);
static CGFloat AgainstGrainDim(BOOL isVertical, NSSize size);
static void SetWithGrainDim(BOOL isVertical, NSSize* dest, CGFloat value);
static void SetAgainstGrainDim(BOOL isVertical, NSSize* dest, CGFloat value);

// Constants for saved window arrangement keys.
static NSString* TAB_ARRANGEMENT_ROOT = @"Root";
static NSString* TAB_ARRANGEMENT_VIEW_TYPE = @"View Type";
static NSString* VIEW_TYPE_SPLITTER = @"Splitter";
static NSString* VIEW_TYPE_SESSIONVIEW = @"SessionView";
static NSString* SPLITTER_IS_VERTICAL = @"isVertical";
static NSString* TAB_ARRANGEMENT_SPLITTER_FRAME = @"frame";
static NSString* TAB_ARRANGEMENT_SPLITTER_ID = @"Splitter ID";
static NSString* TAB_ARRANGEMENT_SESSIONVIEW_FRAME = @"frame";
static NSString* TAB_WIDTH = @"width";
static NSString* TAB_HEIGHT = @"height";
static NSString* TAB_X = @"x";
static NSString* TAB_Y = @"y";
static NSString* SUBVIEWS = @"Subviews";
static NSString* TAB_ARRANGEMENT_SESSION = @"Session";
static NSString* TAB_ARRANGEMENT_IS_ACTIVE = @"Is Active";
static NSString* TAB_ARRANGEMENT_ID = @"ID";  // only for maximize/unmaximize
static NSString* TAB_ARRANGEMENT_IS_MAXIMIZED = @"Maximized";
static NSString* TAB_ARRANGEMENT_TMUX_WINDOW_PANE = @"tmux window pane";
static NSString* TAB_ARRANGEMENT_COLOR = @"Tab color";  // DEPRECATED - Each PTYSession has its own tab color now
static NSString* TAB_ARRANGEMENT_TITLE_OVERRIDE = @"Title Override";
static NSString* TAB_GUID = @"Tab GUID";

static const BOOL USE_THIN_SPLITTERS = YES;

static void SwapSize(NSSize* size) {
    NSSize temp = *size;
    size->height = temp.width;
    size->width = temp.height;
}

static void SwapPoint(NSPoint* point) {
    NSPoint temp = *point;
    point->x = temp.y;
    point->y = temp.x;
}

// The "grain" runs perpendicular to the splitters. An example with isVertical==YES:
// +----------------+
// |     |     |    |
// |     |     |    |
// |     |     |    |
// +----------------+
//
// <------grain----->

static CGFloat WithGrainDim(BOOL isVertical, NSSize size) {
    return isVertical ? size.width : size.height;
}

static CGFloat AgainstGrainDim(BOOL isVertical, NSSize size) {
    return WithGrainDim(!isVertical, size);
}

static void SetWithGrainDim(BOOL isVertical, NSSize *dest, CGFloat value) {
    if (isVertical) {
        dest->width = value;
    } else {
        dest->height = value;
    }
}

static void SetAgainstGrainDim(BOOL isVertical, NSSize *dest, CGFloat value) {
    SetWithGrainDim(!isVertical, dest, value);
}

@interface PTYTab()<iTermObject>
@property(nonatomic, strong) NSMapTable<SessionView *, PTYSession *> *viewToSessionMap;
@end

@implementation PTYTab {
    int _activityCounter;

    // Not really unique because it starts at 0 when the app is relaunched
    int _uniqueId;

    // Actually globally unique but rarely used.
    NSString *_guid;

    // See kPTYTab*State constants above.
    int _tabNumberForItermSessionId;

    // Owning tab view item
    __weak NSTabViewItem* tabViewItem_;

    __weak NSWindowController<iTermWindowController> *realParentWindow_;  // non-nil only if parent is PseudoTerminal*. Implements optional methods of protocol.
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
    __weak NSView *tabView_;

    // If there is a flexible root view, this is set and is the tabview's view.
    // Otherwise it is nil.
    iTermFlexibleView *flexibleView_;

    // The root of a tree of split views whose leaves are SessionViews. The root is the view of the
    // NSTabViewItem.
    //
    // NSTabView -> NSTabViewItem -> NSSplitView (root) -> ... -> SessionView -> PTYScrollView -> etc.
    NSSplitView* root_;

    // The active pane is maximized, meaning there are other panes that are hidden.
    BOOL isMaximized_;

    // Holds references to invisible session views. The key is a number that corresponds to the
    // TAB_ARRANGEMENT_ID in a saved arrangement. It is used when a split pane is maximized to
    // hold on to the SessionView's that are not currently visible. It used to be necessary to
    // prevent SessionView's from getting released, but now that PTYSession has a strong reference
    // to SessionView I'm not sure if we still need this.
    NSMutableDictionary<NSNumber *, SessionView *> *idMap_;

    NSDictionary* savedArrangement_;  // layout of splitters pre-maximize
    NSSize savedSize_;  // pre-maximize active session size.

    // If positive, then a tmux-originated resize is in progress and splitter
    // delegates won't interfere.
    int tmuxOriginatedResizeInProgress_;

    // The tmux controller used by all sessions in this tab.
    TmuxController *tmuxController_;

    // The last tmux parse tree
    NSMutableDictionary *parseTree_;
    NSMutableDictionary *visibleParseTree_;

    // Temporarily hidden live views (this is needed to hold a reference count).
    NSMutableArray *hiddenLiveViews_;  // SessionView objects

    // This tab broadcasts to all its sessions?
    BOOL broadcasting_;

    // Currently dragging a split pane in a tab that's also a tmux tab?
    BOOL _isDraggingSplitInTmuxTab;

    BOOL _resizingSplit;
    iTermSwiftyString *_tabTitleOverrideSwiftyString;

    NSInteger _numberOfSplitViewDragsInProgress;

    // If YES then force metal off. Does a hard reset when changing screens.
    BOOL _bounceMetal;
    NSString *_temporarilyUnmaximizedSessionGUID;

    NSMutableArray<PTYSession *> *_sessionsWithDeferredFontChanges;
    iTermVariableScope<iTermTabScope> *_variablesScope;

    // Capture of the session reading order when a session is maximized.
    // Used so next/previous session will work consistently post-maximization.
    NSArray<NSString *> *_orderedGUIDs;
    iTermBuiltInFunctions *_methods;
    iTermTmuxOptionMonitor *_tmuxTitleMonitor;
}

@synthesize parentWindow = parentWindow_;
@synthesize activeSession = activeSession_;
@synthesize broadcasting = broadcasting_;
@synthesize isMaximized = isMaximized_;
@synthesize tabViewItem = tabViewItem_;
@synthesize lockedSession = lockedSession_;

+ (NSImage *)bellImage {
    return [NSImage it_imageNamed:@"important" forClass:self.class];
}

+ (NSImage *)imageForNewOutputWithAppearance:(NSAppearance *)appearance {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch ((iTermPreferencesTabStyle)[appearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
            
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSImage it_imageNamed:@"NewOutput" forClass:self.class];
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSImage it_imageNamed:@"NewOutputForDarkTheme" forClass:self.class];
    }

    return [NSImage it_imageNamed:@"NewOutput" forClass:self.class];
}

+ (NSImage *)idleImageWithAppearance:(NSAppearance *)appearance {
    // There was a separate idle graphic, but I prefer NewOutput. The distinction is already drawn
    // because a spinner is present only while new output is being received. It's still in the git
    // repo, named "Idle.png".
    return [self imageForNewOutputWithAppearance:appearance];
}

+ (NSImage *)deadImageWithAppearance:(NSAppearance *)appearance {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch ((iTermPreferencesTabStyle)[appearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSImage it_imageNamed:@"dead" forClass:self.class];
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSImage it_imageNamed:@"DeadForDarkTheme" forClass:self.class];
    }
    return [NSImage it_imageNamed:@"dead" forClass:self.class];
}

+ (void)_recursiveRegisterSessionsInArrangement:(NSDictionary *)arrangement {
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        for (NSDictionary *subviewDict in arrangement[SUBVIEWS]) {
            [self _recursiveRegisterSessionsInArrangement:subviewDict];
        }
    } else {
        // Is a session view
        [PTYSession registerSessionInArrangement:arrangement[TAB_ARRANGEMENT_SESSION]];
    }
}

+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement {
    [self _recursiveRegisterSessionsInArrangement:arrangement[TAB_ARRANGEMENT_ROOT]];
}

+ (void)registerBuiltInFunctions {
    [iTermMoveTabToWindowBuiltInFunction registerBuiltInFunction];
    [MoveSessionBuiltInFunction registerBuiltInFunction];
}

+ (NSSize)cellSizeForBookmark:(Profile *)bookmark {
    NSFont *font;

    font = [ITAddressBookMgr fontWithDesc:[bookmark objectForKey:KEY_NORMAL_FONT]
                         ligaturesEnabled:[iTermProfilePreferences boolForKey:KEY_ASCII_LIGATURES
                                                                    inProfile:bookmark]];
    const CGFloat hspace = [iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:bookmark];
    const CGFloat vspace = [iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:bookmark];
    return [PTYTextView charSizeForFont:font
                      horizontalSpacing:hspace
                        verticalSpacing:vspace];
}

+ (NSDictionary *)frameToDict:(NSRect)frame {
    return @{ TAB_X: @(frame.origin.x),
              TAB_Y: @(frame.origin.y),
              TAB_WIDTH: @(frame.size.width),
              TAB_HEIGHT: @(frame.size.height) };
}

+ (NSRect)dictToFrame:(NSDictionary*)dict {
    return NSMakeRect([[dict objectForKey:TAB_X] doubleValue],
                      [[dict objectForKey:TAB_Y] doubleValue],
                      [[dict objectForKey:TAB_WIDTH] doubleValue],
                      [[dict objectForKey:TAB_HEIGHT] doubleValue]);
}

+ (NSString *)htmlNameForColor:(NSColor *)color {
    return [NSString stringWithFormat:@"%02x%02x%02x",
            (int) (color.redComponent * 255.0),
            (int) (color.greenComponent * 255.0),
            (int) (color.blueComponent * 255.0)];
}

+ (NSColor *)colorForHtmlName:(NSString *)name {
    if (!name || [name length] != 6) {
        return nil;
    }
    unsigned int i;
    [[NSScanner scannerWithString:name] scanHexInt:&i];
    CGFloat r = (i >> 16) & 0xff;
    CGFloat g = (i >> 8) & 0xff;
    CGFloat b = (i >> 0) & 0xff;
    return [NSColor colorWithCalibratedRed:r / 255.0
                                     green:g / 255.0
                                      blue:b / 255.0
                                     alpha:1.0];
}

+ (NSSize)sizeForTmuxWindowWithAffinity:(NSString *)affinity
                             controller:(TmuxController *)controller {
    if (affinity != nil) {
        NSSet *siblings = [controller savedAffinitiesForWindow:affinity];
        NSSize size = [controller sizeOfSmallestWindowAmong:siblings];
        if (size.width != INFINITY && size.height != INFINITY) {
            return size;
        }
    }
    // Creating a new window, not a new tab.
    Profile *profile = controller.sharedProfile;
    if (!profile) {
        return NSMakeSize(80, 25);
    }
    const int columns = MIN(iTermMaxInitialSessionSize,
                            [profile[KEY_COLUMNS] intValue]);
    const int rows = MIN(iTermMaxInitialSessionSize,
                         [profile[KEY_ROWS] intValue]);
    return NSMakeSize(columns ?: 80, rows ?: 25);
}

#pragma mark - NSObject

- (instancetype)initWithSession:(PTYSession *)session
                   parentWindow:(NSWindowController<iTermWindowController> *)parentWindow {
    self = [super init];
    if (self) {
        PtyLog(@"PTYTab initWithSession - begin %p", self);
        [self commonInit];
        activeSession_ = session;
        [session setActivityCounter:@(_activityCounter++)];
        [[session view] setDimmed:NO];
        [self setRoot:[[PTYSplitView alloc] init]];
        PTYTab *oldTab = (PTYTab *)[session delegate];
        if (oldTab && [oldTab tmuxWindow] >= 0) {
            self.tmuxWindow = [oldTab tmuxWindow];
            tmuxController_ = [oldTab tmuxController];
            parseTree_ = oldTab->parseTree_;
            visibleParseTree_ = oldTab->visibleParseTree_;
            [tmuxController_ changeWindow:self.tmuxWindow tabTo:self];
            [self updateTmuxTitleMonitor];
        }
        if (parentWindow) {
            [self setParentWindow:parentWindow];
        }
        session.delegate = self;
        [root_ addSubview:[session view]];
        [self.viewToSessionMap setObject:session forKey:session.view];
        PtyLog(@"PTYTab initWithSession - end %p", self);
    }
    return self;
}

// This is used when restoring a window arrangement. A tree of splits and
// sessionviews is passed in but the sessionviews don't have sessions yet.
- (instancetype)initWithRoot:(NSSplitView *)root
                    sessions:(NSMapTable<SessionView *, PTYSession *> *)sessions {
    self = [super init];
    if (self) {
        PtyLog(@"PTYTab initWithRoot - begin %p", self);
        [self commonInit];
        [self setRoot:root];
        [PTYTab _recursiveSetDelegateIn:root_ to:self];
        for (SessionView *sessionView in [self sessionViews]) {
            [self.viewToSessionMap setObject:[sessions objectForKey:sessionView] forKey:sessionView];
        }
        PtyLog(@"PTYTab initWithRoot - end %p", self);
    }
    return self;
}

- (void)commonInit {
    _guid = [[NSUUID UUID] UUIDString];
    self.viewToSessionMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
                                                      valueOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
                                                          capacity:1];
    _tabNumberForItermSessionId = -1;
    hiddenLiveViews_ = [[NSMutableArray alloc] init];
    _variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextTab
                                                   owner:self];
    _variables.primaryKey = @"id";
    _userVariables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextTab
                                                       owner:self];
    _userVariables.isUserWritable = YES;
    [self.variablesScope setValue:_userVariables forVariableNamed:@"user"];
    [self.variablesScope setValue:[iTermVariables globalInstance] forVariableNamed:iTermVariableKeyGlobalScopeName];
    [self.variablesScope setValue:[@(self.uniqueId) stringValue] forVariableNamed:iTermVariableKeyTabID];

    self.tmuxWindow = -1;
    _sessionsWithDeferredFontChanges = [[NSMutableArray alloc] init];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_refreshLabels:)
                                                 name:kUpdateLabelsNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateUseMetal)
                                                 name:iTermPowerManagerStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(metalSettingsDidChange:)
                                                 name:iTermMetalSettingsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tmuxDidFetchSetTitlesStringOption:)
                                                 name:kTmuxControllerDidFetchSetTitlesStringOption
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(annotationVisibilityDidChange:)
                                                 name:iTermAnnotationVisibilityDidChange
                                               object:nil];
    [iTermPreferenceDidChangeNotification subscribe:self selector:@selector(preferenceDidChange:)];
    _tabTitleOverrideSwiftyString = [[iTermSwiftyString alloc] initWithScope:self.variablesScope
                                                                  sourcePath:iTermVariableKeyTabTitleOverrideFormat
                                                             destinationPath:iTermVariableKeyTabTitleOverride];
    __weak __typeof(self) weakSelf = self;
    _tabTitleOverrideSwiftyString.observer = ^(NSString * _Nonnull newValue, NSError *error) {
        if (error) {
            return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
        }
        [weakSelf updateTitleOverrideFromFormatVariable];
        return newValue;
    };
}

- (void)encodeWithCoder:(NSCoder *)coder {
    // NSTabViewItem called this in one crash. We don't have a decoder, but at least we can
    // avoid dying by implementing a do-nothing method. It doesn't seem to be common.
}

- (void)dealloc {
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabClosing"
                                                        object:self
                                                      userInfo:nil];
    PtyLog(@"PTYTab dealloc");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (PTYSession *aSession in [self sessions]) {
        aSession.delegate = nil;
    }

    for (id key in idMap_) {
        SessionView* aView = [idMap_ objectForKey:key];

        PTYSession* aSession = [self sessionForSessionView:aView];
        aSession.active = NO;
        aSession.delegate = nil;
    }

    root_ = nil;
    flexibleView_ = nil;
}

- (NSString *)description {
    if (self.tmuxTab) {
        return [NSString stringWithFormat:@"<%@: %p label=%@ objectCount=%@ tmuxWindow=%@ tmuxController=%@>",
                NSStringFromClass([self class]),
                self,
                tabViewItem_.label,
                @(objectCount_),
                @(self.tmuxWindow),
                self.tmuxController];
    }
    return [NSString stringWithFormat:@"<%@: %p label=%@ objectCount=%@>",
            NSStringFromClass([self class]),
            self,
            tabViewItem_.label,
            @(objectCount_)];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    DLog(@"Making a copy of tab %@", self);
    NSDictionary *arrangement = [self arrangementForDuplication];
    PTYTab *theCopy = [PTYTab tabWithArrangement:arrangement
                                           named:nil
                                      inTerminal:[self realParentWindow]
                                 hasFlexibleView:flexibleView_ != nil
                                         viewMap:nil
                                      sessionMap:nil
                                  tmuxController:tmuxController_
                              partialAttachments:nil
                                reservedTabGUIDs:[NSSet set]
                                         options:nil];
    return theCopy;
}

#pragma mark - Everything else

- (void)setDelegate:(id<PTYTabDelegate>)delegate {
    _delegate = delegate;
    [self.variablesScope setValue:[delegate tabWindowVariables:self]
                 forVariableNamed:iTermVariableKeyTabWindow
                             weak:YES];
}

- (NSView *)rootView {
    return root_;
}

- (NSView *)realRootView {
    if (flexibleView_) {
        return flexibleView_;
    }
    return root_;
}

- (BOOL)useSeparateStatusbarsPerPane {
    if (![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]) {
        return NO;
    }
    if (self.tmuxTab) {
        return NO;
    }
    return YES;
}

- (BOOL)updatePaneTitles {
    BOOL anyChange = NO;
    const BOOL showTitles = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
    NSArray *sessions = [self sessions];
    const BOOL perPaneStatusBars = [self useSeparateStatusbarsPerPane];
    const BOOL statusBarsOnTop = (([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition] == iTermStatusBarPositionTop) &&
                                  perPaneStatusBars);
    const BOOL anySessionHasTopStatusBar = statusBarsOnTop && [sessions anyWithBlock:^BOOL(PTYSession *session) {
        return [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:session.profile];
    }];
    const BOOL shouldShowTitles = (showTitles && [sessions count] > 1) || anySessionHasTopStatusBar;
    for (PTYSession *aSession in sessions) {
        const BOOL shouldShowBottomStatusBar = (perPaneStatusBars &&
                                                !statusBarsOnTop &&
                                                [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR
                                                                          inProfile:aSession.profile]);
        const BOOL changedTitle = [[aSession view] setShowTitle:shouldShowTitles
                                     adjustScrollView:![self isTmuxTab]];
        const BOOL changedBottomStatusBar = [aSession.view setShowBottomStatusBar:shouldShowBottomStatusBar
                                                                 adjustScrollView:!self.isTmuxTab];
        if (changedTitle || changedBottomStatusBar) {
            if (![self isTmuxTab]) {
                if ([self fitSessionToCurrentViewSize:aSession]) {
                    anyChange = YES;
                }
            } else {
                // Get the proper size and return yes if it should change.
                NSSize size = [self sessionSizeForViewSize:aSession];
                if (size.width != [aSession columns] ||
                    size.height != [aSession rows]) {
                    anyChange = YES;
                }
            }
        }
    }
    return anyChange;
}

- (void)numberOfSessionsDidChange {
    if ([self updatePaneTitles] && [self isTmuxTab]) {
        DLog(@"PTYTab numberOfSessionsDidChange triggering windowDidResize");
        [tmuxController_ windowDidResize:realParentWindow_];
    }
    [self updateSessionOrdinals];
    [realParentWindow_ invalidateRestorableState];
    if (self.isBroadcasting) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermBroadcastDomainsDidChangeNotification object:nil];
    }
    [_delegate numberOfSessionsDidChangeInTab:self];
}

- (void)updateSessionOrdinals {
    int i = 1;
    NSArray *orderedSessions = [self orderedSessions];
    for (PTYSession *aSession in orderedSessions) {
        if (i < 9) {
            aSession.view.ordinal = i++;
        } else {
            aSession.view.ordinal = 0;
        }
    }
    if (i == 9) {
        [(SessionView *)[[orderedSessions lastObject] view] setOrdinal:9];
    }
}

+ (void)_recursiveSetDelegateIn:(NSSplitView *)node to:(id)delegate {
    [node setDelegate:delegate];
    for (NSView *subView in [node subviews]) {
        if ([subView isKindOfClass:[NSSplitView class]]) {
            [PTYTab _recursiveSetDelegateIn:(NSSplitView *)subView to:delegate];
        }
    }
}

- (int)uniqueId {
    static int gNextId;
    if (!_uniqueId) {
        _uniqueId = ++gNextId;
    }
    return _uniqueId;
}

- (PTYSession *)sessionForSessionView:(SessionView *)sessionView {
    return [self.viewToSessionMap objectForKey:sessionView];
}

- (NSRect)absoluteFrame {
    NSRect result;
    result.origin = [root_ convertPoint:NSMakePoint(0, 0) toView:nil];
    result.origin = [[root_ window] pointToScreenCoords:result.origin];
    result.size = [root_ frame].size;
    return result;
}

- (NSString *)labelForActiveSession {
    NSString *title = [[self activeSession] name];
    return [self stringByAppendingSubtitleForActiveSession:title];
}

- (NSString *)stringByAppendingSubtitleForActiveSession:(NSString *)title {
    NSString *subtitle = self.activeSession.subtitle;
    return [NSString stringWithFormat:@"%@\n%@", title, subtitle];
}

- (void)_refreshLabels:(id)sender {
    if ([self activeSession]) {
        [tabViewItem_ setLabel:[self labelForActiveSession]];
        [parentWindow_ setWindowTitle];
    }
}

- (void)setBell:(BOOL)flag {
    PtyLog(@"setBell:%d", (int)flag);
    if (flag) {
        [self setState:kPTYTabBellState reset:0];
    } else {
        [self setState:0 reset:kPTYTabBellState];
    }
}

- (void)setState:(NSUInteger)flagsToSet reset:(NSUInteger)flagsToReset {
    NSUInteger before = _state;
    _state |= flagsToSet;
    _state &= ~flagsToReset;
    if (_state != before) {
        DLog(@"Set state of %@ from %@ to %@", self, @(before), @(_state));
        [self updateIcon];
        [_delegate tab:self didChangeToState:_state];
    }
}

- (void)updateIcon {
    if (_state & kPTYTabDeadState) {
        [self setIcon:[PTYTab deadImageWithAppearance:self.realParentWindow.window.effectiveAppearance]];
    } else if (_state & kPTYTabBellState) {
        [self setIcon:[PTYTab bellImage]];
    } else if ([iTermPreferences boolForKey:kPreferenceKeyShowNewOutputIndicator] &&
               (_state & (kPTYTabNewOutputState))) {
        [self setIcon:[PTYTab imageForNewOutputWithAppearance:self.realParentWindow.window.effectiveAppearance]];
    } else if ([iTermPreferences boolForKey:kPreferenceKeyShowNewOutputIndicator] &&
               (_state & kPTYTabIdleState)) {
        [self setIcon:[PTYTab idleImageWithAppearance:self.realParentWindow.window.effectiveAppearance]];
    } else {
        [self setIcon:nil];
    }
}

- (void)loadTitleFromSession {
    tabViewItem_.label = self.activeSession.name;
}

- (void)nameOfSession:(PTYSession *)session didChangeTo:(NSString*)newName {
    if ([self activeSession] == session) {
        [self updateTabTitleForCurrentSessionName:newName];
    }
}

- (void)updateTabTitleForCurrentSessionName:(NSString *)newName {
    NSString *const tmuxPrefix = [iTermAdvancedSettingsModel tmuxTitlePrefix];
    NSString *value = self.variablesScope.tabTitleOverride;
    if (value.length == 0) {
        if (self.tmuxTab) {
            NSString *tmuxWindowName = [self.variablesScope valueForVariableName:iTermVariableKeyTabTmuxWindowName];
            if (newName.length) {
                value = newName;
            } else if (tmuxWindowName.length) {
                value = [tmuxPrefix stringByAppendingString:tmuxWindowName];
            } else {
                value = [tmuxPrefix stringByAppendingString:self.activeSession.name];
            }
        } else {
            value = newName ?: @"";
        }
    } else if (self.tmuxTab && ![value hasPrefix:tmuxPrefix]) {
        value = [tmuxPrefix stringByAppendingString:value];
    }
    [self.variablesScope setValue:value forVariableNamed:iTermVariableKeyTabTitle];
    [tabViewItem_ setLabel:[self stringByAppendingSubtitleForActiveSession:value]];  // PSM uses bindings to bind the label to its title
    [self.realParentWindow tabTitleDidChange:self];
}

- (BOOL)isForegroundTab {
    return [[tabViewItem_ tabView] selectedTabViewItem] == tabViewItem_;
}

- (void)sessionDidChangeTmuxWindowNameTo:(NSString *)newName {
    [self setTmuxWindowName:newName];
}

- (void)makeActive {
    PTYSession *activeSession = [self activeSession];
    [[self.realParentWindow tabView] selectTabViewItemWithIdentifier:self];
    if ([self activeSession] != activeSession && [self.sessions containsObject:activeSession]) {
        [self setActiveSession:activeSession];
    }
}
- (void)willDeselectTab {
    DLog(@"willDeselectTab %@", self);
    for (PTYSession *session in self.sessions) {
        [session enclosingTabWillBeDeselected];
    }
}

- (void)didSelectTab {
    DLog(@"didSelectTab %@", self);
    for (PTYSession *session in self.sessions) {
        [session enclosingTabDidBecomeSelected];
    }
}

- (void)sessionSelectContainingTab {
    [self makeActive];
}

- (BOOL)sessionInitiatedResize:(PTYSession *)session width:(int)width height:(int)height {
    return [parentWindow_ sessionInitiatedResize:session width:width height:height];
}

- (void)addSession:(PTYSession *)session toRestorableSession:(iTermRestorableSession *)restorableSession {
    DLog(@"Add %@ to restorable session", session);
    NSArray *sessions = restorableSession.sessions ?: @[];
    restorableSession.sessions = [sessions arrayByAddingObject:session];
    restorableSession.terminalGuid = self.realParentWindow.terminalGuid;
    restorableSession.tabUniqueId = self.uniqueId;
    restorableSession.arrangement = self.arrangement;
    restorableSession.group = kiTermRestorableSessionGroupSession;
    [realParentWindow_ storeWindowStateInRestorableSession:restorableSession];
}

- (void)setActiveSession:(PTYSession *)session {
    [self setActiveSession:session updateActivityCounter:YES];
}

- (void)setActiveSession:(PTYSession *)session updateActivityCounter:(BOOL)updateActivityCounter {
    PtyLog(@"PTYTab setActiveSession:%p", session);
    if (activeSession_ &&  activeSession_ != session && [activeSession_ dvr]) {
        [realParentWindow_ closeInstantReplay:self orTerminateSession:NO];
    }
    BOOL changed = session != activeSession_;
    if (changed && updateActivityCounter) {
        [activeSession_ setActivityCounter:@(_activityCounter++)];
        [session setActivityCounter:@(_activityCounter++)];
    }
    activeSession_ = session;
    if (activeSession_ == nil) {
        [self recheckBlur];
        [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeyTabCurrentSession];
        return;
    }
    if (changed) {
        [parentWindow_ setWindowTitle];
        [tabViewItem_ setLabel:[self labelForActiveSession]];
        if ([realParentWindow_ currentTab] == self) {
            // If you set a textview in a non-current tab to the first responder and
            // then close that tab, it crashes with NSTextInput calling
            // -[PTYTextView respondsToSelector:] on a deallocated instance of the
            // first responder. This kind of hacky workaround keeps us from making
            // a invisible textview the first responder.
            [[realParentWindow_ window] makeFirstResponder:[session mainResponder]];
        }
        [realParentWindow_ setDimmingForSessions];
    }
    // TODO: It's dangerous to call refresh here because it causes side effects to run.
    // I need to audit every call to refresh and remove them all if possible.
    // I don't know why this one is here. It has been here since the beginning of time.
    /*
    for (PTYSession *aSession in [self sessions]) {
        [[aSession textview] refresh];
        [[aSession textview] requestDelegateRedraw];
    }
     */
    [self updateLabelAttributes];
    [self.variablesScope setValue:activeSession_.variables forVariableNamed:iTermVariableKeyTabCurrentSession];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionBecameKey
                                                        object:activeSession_
                                                      userInfo:@{ @"changed": @(changed) }];
    // If the active session changed in the active tab in the key window then update the
    // focused state of all sessions in that window.
    if ([[self realParentWindow] currentTab] == self &&
        [[[self realParentWindow] window] isKeyWindow]) {
      for (PTYSession *aSession in [[self realParentWindow] allSessions]) {
        [aSession setFocused:(aSession == session)];
      }
    }

    [realParentWindow_ invalidateRestorableState];

    if (changed) {
        [[self realParentWindow] tabActiveSessionDidChange];
        [self.delegate tab:self
        setBackgroundImage:self.activeSession.backgroundImage
                      mode:self.activeSession.backgroundImageMode
           backgroundColor:self.activeSession.effectiveProcessedBackgroundColor];
    }

    [[self realParentWindow] updateTabColors];
    [self recheckBlur];

    if (!session.exited) {
        DLog(@"Clear dead state");
        [self setState:0 reset:kPTYTabDeadState];
    }
    [self updateTabTitle];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermCurrentSessionDidChange
                                                        object:activeSession_
                                                      userInfo:nil];
}

- (void)sessionActivate:(PTYSession *)session {
    if (self.activeSession == session) {
        return;
    }
    const BOOL wasMaximized = isMaximized_;
    if (wasMaximized) {
        [self unmaximize];
    }
    [self setActiveSession:session];
    if (wasMaximized) {
        [self maximize];
    }
}

// Do a depth-first search for a leaf with viewId==requestedId. Returns nil if not found under 'node'.
- (SessionView *)_recursiveSessionViewWithId:(int)requestedId atNode:(NSSplitView *)node {
    for (NSView *v in [node subviews]) {
        if ([v isKindOfClass:[NSSplitView class]]) {
            SessionView *sv = [self _recursiveSessionViewWithId:requestedId atNode:(NSSplitView *)v];
            if (sv) {
                return sv;
            }
        } else {
            SessionView *sv = (SessionView *)v;
            if ([sv viewId] == requestedId) {
                return sv;
            }
        }
    }
    return nil;
}

- (PTYSession *)sessionWithViewId:(int)viewId {
    SessionView *sv = [self _recursiveSessionViewWithId:viewId atNode:root_];
    return [self sessionForSessionView:sv];
}

- (NSPoint)rootRelativeOriginOfSession:(PTYSession *)session {
    if (!isMaximized_) {
        return [root_ convertPoint:session.view.frame.origin
                          fromView:session.view.superview];
    } else {
        return session.savedRootRelativeOrigin;
    }
}

- (NSArray *)orderedSessions {
    if ([iTermAdvancedSettingsModel navigatePanesInReadingOrder]) {
        if (self.isMaximized) {
            return [_orderedGUIDs mapWithBlock:^id(NSString *guid) {
                return [self sessionWithGUID:guid];
            }];
        }
        BOOL useTrueReadingOrder = !root_.isVertical;
        return [[self sessions] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSPoint origin1 = [self rootRelativeOriginOfSession:obj1];
            NSPoint origin2 = [self rootRelativeOriginOfSession:obj2];
            if (useTrueReadingOrder) {
                // True reading order--top to bottom, then left to right.
                if (fabs(origin1.y - origin2.y) < 1) {
                    return [@(origin1.x) compare:@(origin2.x)];
                } else {
                    return [@(origin1.y) compare:@(origin2.y)];
                }
            } else {
                // Inverted reading order. Left to right, then top to bottom.
                // Generally makes more sense when the root split is vertical.
                if (fabs(origin1.x - origin2.x) < 1) {
                    return [@(origin1.y) compare:@(origin2.y)];
                } else {
                    return [@(origin1.x) compare:@(origin2.x)];
                }
            }
        }];
    } else {
        return [[self sessions] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            PTYSession *session1 = obj1;
            PTYSession *session2 = obj2;
            return [session1.activityCounter compare:session2.activityCounter];
        }];
    }
}

- (void)setActiveSessionPreservingMaximization:(PTYSession *)session {
    DLog(@"%@", session);
    BOOL maximize = NO;
    if (isMaximized_ && self.activeSession.isTmuxClient) {
        DLog(@"Set maximize to YES");
        maximize = YES;
        [self.activeSession toggleTmuxZoom];
    }
    if (isMaximized_) {
        [root_ replaceSubview:[[root_ subviews] objectAtIndex:0]
                         with:[session view]];
    }
    [self setActiveSession:session updateActivityCounter:NO];
    if (maximize) {
        [self.activeSession toggleTmuxZoom];
    }
}

- (BOOL)sessionBelongsToHotkeyWindow:(PTYSession *)session {
    return [self.delegate tabBelongsToHotkeyWindow:self];
}

- (void)sessionSwapWithSessionInDirection:(int)direction {
    PTYSession *session = [self sessionInDirection:direction];
    if (session == self.activeSession || !session) {
        return;
    }
    [self swapSession:self.activeSession withSession:session];
}

- (PTYSession *)sessionInDirection:(int)offset {
    DLog(@"offset=%@", @(offset));
    NSArray *orderedSessions = [self orderedSessions];
    NSUInteger index = [orderedSessions indexOfObject:[self activeSession]];
    if (index == NSNotFound) {
        return nil;
    }
    index = (index + orderedSessions.count + offset) % orderedSessions.count;
    return orderedSessions[index];
}

- (void)activateSessionInDirection:(int)offset {
    DLog(@"offset=%@", @(offset));
    BOOL maximize = NO;
    if (isMaximized_ && self.activeSession.isTmuxClient) {
        DLog(@"Set maximize to YES");
        maximize = YES;
        [self.activeSession toggleTmuxZoom];
    }
    PTYSession *session = [self sessionInDirection:offset];
    if (session) {
        if (isMaximized_) {
            [root_ replaceSubview:[[root_ subviews] objectAtIndex:0]
                             with:session.view];
        }
        [self setActiveSession:session updateActivityCounter:NO];
    }
    if (maximize) {
        [self.activeSession toggleTmuxZoom];
    }
}

- (void)previousSession {
    [self activateSessionInDirection:-1];
}

- (void)nextSession {
    [self activateSessionInDirection:1];
}

- (int)indexOfSessionView:(SessionView*)sessionView {
    return [[self sessionViews] indexOfObject:sessionView];
}

- (NSWindowController<iTermWindowController> *)realParentWindow {
    return realParentWindow_;
}

- (NSColor *)flexibleViewColor {
    if ([realParentWindow_ anyFullScreen] && [iTermAdvancedSettingsModel useBlackFillerColorForTmuxInFullScreen]) {
        return [NSColor blackColor];
    }

    NSColor *backgroundColor = [self.activeSession.screen.colorMap colorForKey:kColorMapBackground];
    CGFloat components[4];
    [backgroundColor getComponents:components];
    CGFloat mix;
    if (backgroundColor.brightnessComponent < 0.5) {
        mix = 1;
    } else {
        mix = 0;
    }
    const CGFloat a = 0.1;
    for (int i = 0; i < 3; i++) {
        components[i] = a * mix + (1 - a) * components[i];
    }
    const CGFloat alpha = self.realParentWindow.useTransparency ? (1.0 - self.activeSession.transparency) : 1.0;
    return [NSColor colorWithCalibratedRed:components[0] green:components[1] blue:components[2] alpha:alpha];
}

- (void)updateFlexibleViewColors {
    if (!flexibleView_) {
        return;
    }
    Profile *profile = [self.tmuxController profileForWindow:self.tmuxWindow];
    NSSize cellSize = [PTYTab cellSizeForBookmark:profile];
    const NSSize delta = NSMakeSize(flexibleView_.frame.size.width - root_.frame.size.width,
                                    flexibleView_.frame.size.height - root_.frame.size.height);
    if (![realParentWindow_ anyFullScreen] &&
        delta.width >= 0 && delta.width < cellSize.width &&
        delta.height >= 0 && delta.height < cellSize.height) {
        DLog(@"Root is slightly smaller than flexible view so use terminal background color for flexible view's background");
        // Root is just slightly smaller than flexibleView, by less than the size of a character.
        // Set flexible view's color to the default background color for tmux tabs.
        NSColor *bgColor = [iTermProfilePreferences colorForKey:KEY_BACKGROUND_COLOR
                                                           dark:root_.effectiveAppearance.it_isDark
                                                        profile:profile];
        if ([self.delegate tabShouldUseTransparency:self]) {
            CGFloat alpha = 1.0 - [iTermProfilePreferences floatForKey:KEY_TRANSPARENCY inProfile:profile];
            if (alpha < 1) {
                bgColor = [bgColor colorWithAlphaComponent:alpha];
            }
        }


        [flexibleView_ setColor:bgColor];
    } else {
        // Fullscreen, overly large flexible view, or exact size flex view.
        [flexibleView_ setColor:[self flexibleViewColor]];
    }
}

- (void)setParentWindow:(NSWindowController<iTermWindowController> *)theParent {
    // Parent holds a reference to us (indirectly) so we mustn't reference it.
    if (parentWindow_ && theParent && parentWindow_ != theParent) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermTabDidChangeWindowNotification object:self];
    }
    parentWindow_ = realParentWindow_ = theParent;
    [self updateFlexibleViewColors];
    for (PTYSession *session in self.sessions) {
        [session useTransparencyDidChange];
        [session didMoveSession];
    }
}

- (void)setFakeParentWindow:(FakeWindow *)theParent {
    parentWindow_ = fakeParentWindow_ = theParent;
}

- (void)setLockedSession:(PTYSession*)lockedSession {
    PtyLog(@"PTYTab setLockedSession:%p", lockedSession);
    lockedSession_ = lockedSession;
}

- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem {
    PtyLog(@"PTYTab setTabViewItem:%p", theTabViewItem);
    // The tab view item holds a reference to us. So we don't hold a reference to it.
    tabViewItem_ = theTabViewItem;
    if (theTabViewItem != nil) {
        // While Lion-restoring windows, there may be no active session.
        if ([self activeSession]) {
            [tabViewItem_ setLabel:[self labelForActiveSession]];
        } else {
            [tabViewItem_ setLabel:@""];
        }
        [tabViewItem_ setView:tabView_];
    }
}

- (int)number {
    return [[tabViewItem_ tabView] indexOfTabViewItem:tabViewItem_];
}

- (int)tabNumber {
    return objectCount_;
}

- (NSImage *)psmTabGraphic {
    return self.activeSession.tabGraphic;
}

- (int)objectCount {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabNumber] ? 0 : objectCount_;
}

- (void)setObjectCount:(int)value {
    objectCount_ = value;
    [_delegate tab:self didChangeObjectCount:self.objectCount];
}

- (NSImage *)icon {
    return icon_;
}

- (void)setIcon:(NSImage *)anIcon {
    icon_ = anIcon;
    [_delegate tab:self didChangeIcon:anIcon];
}

- (BOOL)realIsProcessing {
    return isProcessing_;
}

// This is KVO-observed by PSMTabBarControl and determines whether the activity indicator is visible.
- (BOOL)isProcessing {
    return (![iTermPreferences hideTabActivityIndicator] &&
            isProcessing_ &&
            ![self isForegroundTab]);
}

- (void)setIsProcessing:(BOOL)aFlag {
    if (aFlag != isProcessing_) {
        DLog(@"Set processing flag of %@ from %@ to %@", self, @(isProcessing_), @(aFlag));
        isProcessing_ = aFlag;
        [_delegate tab:self didChangeProcessingStatus:self.isProcessing];
    }
}

- (BOOL)anySessionIsProcessing {
    for (PTYSession *session in self.sessions) {
        if (session.isProcessing) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)anySessionHasNewOutput:(BOOL *)okToNotify {
    *okToNotify = NO;
    BOOL result = NO;
    for (PTYSession* session in [self sessions]) {
        if ([session newOutput]) {
            if ([session shouldPostUserNotification]) {
                *okToNotify = YES;
            }
            result = YES;
        }
    }
    return result;
}

- (NSArray<PTYSession *> *)sessionsAtTop {
    if (isMaximized_) {
        return @[self.activeSession];
    }
    return [self.sessions minimumsWithComparator:^NSComparisonResult(PTYSession *_Nonnull session1, PTYSession *_Nonnull session2) {
        const CGFloat y1 = round(NSMinY([root_ convertRect:session1.view.bounds fromView:session1.view]));
        const CGFloat y2 = round(NSMinY([root_ convertRect:session2.view.bounds fromView:session2.view]));
        return [@(y1) compare:@(y2)];
    }];
}

- (NSArray<PTYSession *> *)sessionsAtLeft {
    if (isMaximized_) {
        return @[self.activeSession];
    }
    return [self.sessions minimumsWithComparator:^NSComparisonResult(PTYSession *_Nonnull session1, PTYSession *_Nonnull session2) {
        const CGFloat y1 = round(NSMinX([root_ convertRect:session1.view.bounds fromView:session1.view]));
        const CGFloat y2 = round(NSMinX([root_ convertRect:session2.view.bounds fromView:session2.view]));
        return [@(y1) compare:@(y2)];
    }];
}

- (NSArray<PTYSession *> *)sessionsAtBottom {
    if (isMaximized_) {
        return @[self.activeSession];
    }
    return [self.sessions maximumsWithComparator:^NSComparisonResult(PTYSession *_Nonnull session1, PTYSession *_Nonnull session2) {
        const CGFloat y1 = round(NSMaxY([root_ convertRect:session1.view.bounds fromView:session1.view]));
        const CGFloat y2 = round(NSMaxY([root_ convertRect:session2.view.bounds fromView:session2.view]));
        return [@(y1) compare:@(y2)];
    }];
}

// The following adjacency code works on this thesis:
//
// B is adjacent-right-of A if:
//   B != A, AND
//   B.bottom >= A.top, AND
//   B.top < A.bottom, AND
//   B.left >= A.right, AND
//   No C exists where:
//     C != A, AND
//     C != B, AND
//     C.bottom >= A.top, AND
//     C.top < A.bottom, AND
//     C.bottom >= B.top, AND
//     C.top < B.bottom, AND
//     C.left >= A.right, AND
//     C.right < B.left, AND
//
// To select adjacent-right-of instead of adjacent-left-of, multiply use -1*right where it says left and -1*left where it says right.
// To select adjacent-below instead of adjacent-right-of, swap all axes.
// To select adjacent-above instead of adjacent-right-of, first swap all axes and then use -right and -left in place of left and right.
//
// As an example:
//
// +-------+------+----+
// |       |   X1 |    |
// |   A   +------+ x3 |
// |       |   X2 |    |
// +-------+------+----+
// |           D       |
// +-------------------+
//
// X1, X2, and X3 all sit "in the projection" of A, looking right.
// D does not and can be ignored.
//
// For each B in {X1, X2, X3} we check if any C sits between A and B.
// X1 sits between A and X3, so X3 is not adjacent-right-of A.
// X1 and X2 have no such C, so they are adjacent-right-of A.
// We did not consider D since it isn't in the projection.

- (NSArray<PTYSession *> *)sessionsSatisfying:(BOOL (^)(PTYSession *otherSession))condition {
    return [self.sessions filteredArrayUsingBlock:^BOOL(PTYSession *anObject) {
        return condition(anObject);
    }];
}

- (NSArray<PTYSession *> *)sessionsInProjectionOfSession:(PTYSession *)aSession
                                       verticalDirection:(BOOL)verticalDirection
                                                   after:(BOOL)after {
    NSRect aRect = [root_ convertRect:aSession.view.frame fromView:aSession.view.superview];
    if (verticalDirection) {
        SwapSize(&aRect.size);
        SwapPoint(&aRect.origin);
    }

    const CGFloat aTop = NSMinY(aRect);
    const CGFloat aBottom = NSMaxY(aRect);
    const CGFloat safetyMargin = 1;

    return [self sessionsSatisfying:^BOOL(PTYSession *b) {
        if (b == aSession) {
            return NO;
        }
        NSRect bRect = [self->root_ convertRect:b.view.frame fromView:b.view.superview];
        if (verticalDirection) {
            SwapSize(&bRect.size);
            SwapPoint(&bRect.origin);
        }

        const CGFloat bTop = NSMinY(bRect);
        const CGFloat bBottom = NSMaxY(bRect);

        const CGFloat bLeft = after ? NSMinX(bRect) : -NSMaxX(bRect);
        const CGFloat aRight = after ? NSMaxX(aRect) : -NSMinX(aRect);

        return (bBottom >= aTop + safetyMargin &&
                bTop + safetyMargin < aBottom &&
                bLeft >= aRight);
    }];
}

- (NSArray<PTYSession *> *)sessionsAdjacentToSession:(PTYSession *)aSession
                                         verticalDir:(BOOL)verticalDir
                                               after:(BOOL)after {
    NSArray<PTYSession *> *bCandidates = [self sessionsInProjectionOfSession:aSession verticalDirection:verticalDir after:after];
    return [bCandidates filteredArrayUsingBlock:^BOOL(PTYSession *b) {
        BOOL cExists = [bCandidates anyWithBlock:^BOOL(PTYSession *cCandidate) {
            return [self session:cCandidate sitsBetween:aSession andSession:b verticalDir:verticalDir after:after];
        }];
        return !cExists;
    }];
}

- (BOOL)session:(PTYSession *)c sitsBetween:(PTYSession *)a andSession:(PTYSession *)b verticalDir:(BOOL)verticalDir after:(BOOL)after {
    if (c == a || c == b) {
        return NO;
    }
    NSRect aRect = [root_ convertRect:a.view.frame fromView:a.view.superview];
    NSRect bRect = [root_ convertRect:b.view.frame fromView:b.view.superview];
    NSRect cRect = [root_ convertRect:c.view.frame fromView:c.view.superview];

    if (verticalDir) {
        SwapSize(&aRect.size);
        SwapPoint(&aRect.origin);

        SwapSize(&bRect.size);
        SwapPoint(&bRect.origin);

        SwapSize(&cRect.size);
        SwapPoint(&cRect.origin);
    }

    const CGFloat aTop = NSMinY(aRect);
    const CGFloat aBottom = NSMaxY(aRect);
    const CGFloat aRight = after ? NSMaxX(aRect) : -NSMinX(aRect);

    const CGFloat bTop = NSMinY(bRect);
    const CGFloat bBottom = NSMaxY(bRect);
    const CGFloat bLeft = after ? NSMinX(bRect) : -NSMaxX(bRect);

    const CGFloat cTop = NSMinY(cRect);
    const CGFloat cBottom = NSMaxY(cRect);
    const CGFloat cLeft = after ? NSMinX(cRect) : -NSMaxX(cRect);
    const CGFloat cRight = after ? NSMaxX(cRect) : -NSMinX(cRect);

    return (cBottom >= aTop &&
            cTop < aBottom &&
            cBottom >= bTop &&
            cTop < bBottom &&
            cLeft >= aRight &&
            cRight < bLeft);
}

- (PTYSession *)sessionAdjacentTo:(PTYSession *)session
                      verticalDir:(BOOL)verticalDir
                            after:(BOOL)after {
    NSArray<PTYSession *> *sessions = [self sessionsAdjacentToSession:session verticalDir:verticalDir after:after];
    if (sessions.count || ![iTermAdvancedSettingsModel wrapFocus]) {
        return [sessions maxWithComparator:^NSComparisonResult(PTYSession *a, PTYSession *b) {
            return [a.activityCounter compare:b.activityCounter];
        }];
    } else {
        sessions = [self sessionsInProjectionOfSession:session verticalDirection:verticalDir after:!after];
        NSArray<PTYSession *> *wraparounds = [sessions minimumsWithComparator:^NSComparisonResult(PTYSession *a, PTYSession *b) {
            NSRect aRect = [self->root_ convertRect:a.view.frame fromView:a.view.superview];
            NSRect bRect = [self->root_ convertRect:b.view.frame fromView:b.view.superview];
            if (verticalDir) {
                SwapSize(&aRect.size);
                SwapPoint(&aRect.origin);
                SwapSize(&bRect.size);
                SwapPoint(&bRect.origin);
            }

            const CGFloat bLeft = after ? NSMinX(bRect) : -NSMaxX(bRect);
            const CGFloat aLeft = after ? NSMinX(aRect) : -NSMaxX(aRect);
            return [@(aLeft) compare:@(bLeft)];
        }];
        return [wraparounds maxWithComparator:^NSComparisonResult(PTYSession *a, PTYSession *b) {
            return [a.activityCounter compare:b.activityCounter];
        }];
    }
}

- (PTYSession*)sessionLeftOf:(PTYSession*)session {
    return [self sessionAdjacentTo:session verticalDir:NO after:NO];
}

- (PTYSession*)sessionRightOf:(PTYSession*)session {
    return [self sessionAdjacentTo:session verticalDir:NO after:YES];
}

- (PTYSession*)sessionAbove:(PTYSession*)session {
    return [self sessionAdjacentTo:session verticalDir:YES after:NO];
}

- (PTYSession*)sessionBelow:(PTYSession*)session {
    return [self sessionAdjacentTo:session verticalDir:YES after:YES];
}

- (void)updateLabelAttributes {
    DLog(@"PTYTab updateLabelAttributes for tab %d", objectCount_);

    if ([[self activeSession] exited]) {
        // Session has terminated.
        [self setLabelAttributesForDeadSession];
    } else {
        if (![self anySessionIsProcessing]) {
            DLog(@"No session is processing");
            // Too much time has passed since activity occurred and we're idle.
            [self setLabelAttributesForIdleTab];
        } else {
            DLog(@"Some session is processing");
            // Less than 2 seconds has passed since the last output in the session.
            BOOL okToNotify;
            if ([self anySessionHasNewOutput:&okToNotify]) {
                DLog(@"Some session has new output");
                [self setLabelAttributesForActiveTab:okToNotify];
            }
        }
        // If possible, reset label attributes on this tab.
        [self resetLabelAttributesIfAppropriate];
    }
}

- (void)closeSession:(PTYSession *)session {
    [[self parentWindow] closeSession:session];
}

- (void)softCloseSession:(PTYSession *)session {
    [[self realParentWindow] softCloseSession:session];
}

- (void)terminateAllSessions {
    [self.sessions makeObjectsPerformSelector:@selector(terminate)];
}

- (NSArray<NSNumber *> *)windowPanes {
    NSArray *sessions = [self sessions];
    NSMutableArray *panes = [NSMutableArray array];
    for (PTYSession *session in sessions) {
        [panes addObject:@([session tmuxPane])];
    }
    return panes;
}

- (NSArray *)sessions {
    if (idMap_) {
        NSArray<SessionView *> *sessionViews = [idMap_ allValues];
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:[sessionViews count]];
        for (SessionView* sessionView in sessionViews) {
            [result addObject:[self sessionForSessionView:sessionView]];
        }
        return result;
    } else {
        return [self _recursiveSessions:[NSMutableArray arrayWithCapacity:1] atNode:root_];
    }
}

- (NSArray<PTYSession *> *)_recursiveSessions:(NSMutableArray<PTYSession *> *)sessions
                                       atNode:(NSSplitView *)node {
    for (id subview in [node subviews]) {
        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveSessions:sessions atNode:(NSSplitView*)subview];
        } else {
            SessionView* sessionView = (SessionView*)subview;
            PTYSession* session = [self sessionForSessionView:sessionView];
            if (session) {
                [sessions addObject:session];
            }
        }
    }
    return sessions;
}

- (NSArray<SessionView *> *)sessionViews {
    if (idMap_) {
        return [idMap_ allValues];
    } else {
        return [self _recursiveSessionViews:[NSMutableArray arrayWithCapacity:1] atNode:root_];
    }
}

- (NSArray<SessionView *> *)_recursiveSessionViews:(NSMutableArray<SessionView *> *)sessionViews
                                            atNode:(NSSplitView*)node {
    for (id subview in [node subviews]) {
        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveSessionViews:sessionViews atNode:(NSSplitView*)subview];
        } else {
            SessionView* sessionView = (SessionView*)subview;
            if (sessionView) {
                [sessionViews addObject:sessionView];
            }
        }
    }
    return sessionViews;
}

- (void)addHiddenLiveView:(SessionView *)hiddenLiveView {
    [hiddenLiveViews_ addObject:hiddenLiveView];
}

- (void)session:(PTYSession *)synthetic setLiveSession:(PTYSession *)live {
    [hiddenLiveViews_ addObject:live.view];
    synthetic.liveSession = live;
    [self setFakeParentWindow:[[FakeWindow alloc] initFromRealWindow:realParentWindow_
                                                             session:live]];
    [realParentWindow_.window makeFirstResponder:synthetic.mainResponder];
    [self.viewToSessionMap setObject:live forKey:live.view];
}

- (void)setFilter:(NSString *)query inSession:(PTYSession *)oldSession {
    // Join out of caution. I don't want oldSession changing unexpectedly during this method. setFilter:
    // also joins out of necessity which could cause a state update.
    [oldSession resetMode];
    [oldSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        if (oldSession.filter != nil) {
            if (query.length == 0) {
                PTYSession *live = oldSession.liveSession;
                oldSession.filter = nil;
                [self.delegate tabEndSyntheticSession:oldSession];
                [live.view.findDriver setFilterWithoutSideEffects:@""];
            } else {
                oldSession.filter = query;
            }
            return;
        }
        if (!query.length) {
            return;
        }
        PTYSession *syntheticSession = [self.realParentWindow syntheticSessionForSession:oldSession];
        if (!syntheticSession) {
            DLog(@"syntheticSessionForSession:%@ returned nl", oldSession);
            return;
        }
        [syntheticSession divorceAddressBookEntryFromPreferences];
        [syntheticSession setSessionSpecificProfileValues:@{ KEY_UNLIMITED_SCROLLBACK: @YES }];
        [syntheticSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            mutableState.cursorVisible = NO;
        }];
        [self replaceActiveSessionWithSyntheticSession:syntheticSession];
        syntheticSession.filter = query;
        [syntheticSession showFilter];
        [syntheticSession.view.findDriver setFilterWithoutSideEffects:query];
    }];
}

- (void)replaceActiveSessionWithSyntheticSession:(PTYSession *)newSession {
    PtyLog(@"PTYTab setDvrInSession:%p", newSession);
    PTYSession* oldSession = [self activeSession];
    assert(oldSession != newSession);

    // Swap views between newSession and oldSession.
    SessionView* newView = [newSession view];
    SessionView* oldView = [oldSession view];
    newView.frame = oldView.frame;
    NSSplitView* parentSplit = (NSSplitView*)[oldView superview];
    [hiddenLiveViews_ addObject:oldView];
    [parentSplit replaceSubview:oldView with:newView];

    [newSession.nameController setNeedsUpdate];

    newSession.liveSession = oldSession;
    activeSession_ = newSession;

    // TODO(georgen): the hidden window can resize itself and the FakeWindow
    // needs to pass that on to the screen. Otherwise the DVR playback into the
    // time after cmd-d was pressed (but before the present) has the wrong
    // window size.
    [self setFakeParentWindow:[[FakeWindow alloc] initFromRealWindow:realParentWindow_
                                                             session:oldSession]];

    // This starts the new session's update timer
    [newSession updateDisplayBecause:@"replacing active session with synthetic"];
    [realParentWindow_.window makeFirstResponder:newSession.mainResponder];

    // Keep the live session in self.viewToSessionMap so it doesn't get released.
    [self.viewToSessionMap setObject:newSession forKey:newSession.view];
}

- (int)tabNumberForItermSessionId {
    if (_tabNumberForItermSessionId != -1) {
        return _tabNumberForItermSessionId;
    }

    NSMutableSet *tabNumbersInUse = [NSMutableSet set];
    for (PTYTab *tab in realParentWindow_.tabs) {
        [tabNumbersInUse addObject:@(tab->_tabNumberForItermSessionId)];
    }
    int i = objectCount_ - 1;
    int next = 0;
    while ([tabNumbersInUse containsObject:@(i)]) {
        i = next;
        next++;
    }
    _tabNumberForItermSessionId = i;
    return i;
}


- (void)setDvrInSession:(PTYSession*)newSession {
    PTYSession *oldSession = activeSession_;
    [self replaceActiveSessionWithSyntheticSession:newSession];
    [newSession setDvr:[[oldSession screen] dvr] liveSession:oldSession];
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession {
    PtyLog(@"PTYTab showLiveSession:%p", liveSession);
    replaySession.active = NO;
    [liveSession willRetireSyntheticSession:replaySession];
    SessionView* oldView = [replaySession view];
    SessionView* newView = [liveSession view];
    NSSplitView* parentSplit = (NSSplitView*)[oldView superview];
    [parentSplit replaceSubview:oldView with:newView];
    [hiddenLiveViews_ removeObject:newView];
    activeSession_ = liveSession;

    [fakeParentWindow_ rejoin:realParentWindow_];
    replaySession.liveSession = nil;
    fakeParentWindow_ = nil;

    [self.viewToSessionMap removeObjectForKey:replaySession.view];
}

- (void)_dumpView:(__kindof NSView *)view withPrefix:(NSString *)prefix {
    if ([view isKindOfClass:[SessionView class]]) {
        PtyLog(@"%@%@", prefix, NSStringFromSize(view.frame.size));
    } else {
        NSSplitView* sv = view;
        for (NSView *v in [sv subviews]) {
            [self _dumpView:v withPrefix:[NSString stringWithFormat:@"  %@", prefix]];
        }
    }
}

- (void)dump {
    for (NSView *v in [root_ subviews]) {
        [self _dumpView:v withPrefix:@""];
    }
}

// When removing a view some invariants must be maintained:
// 1. A non-root splitview must have at least two children.
// 2. The root splitview may have exactly one child iff that child is a SessionView
// 3. A non-root splitview's orientation must be the opposite of its parent's.
//
// The algorithm is:
// Remove the view from its parent.
// Clean up the parent.
//
// Where "clean up splitView" consists of:
// If splitView (orientation -1^n) has one child
//   If that child (orientation -1^(n+1) is a splitview
//     If splitView is root:
//       Remove only child
//       swap splitView's orientation (to -1^(n+1), matching child's)
//       move grandchildren into splitView
//     else if splitView is not root:
//       Move grandchildren into splitView's parent (orientation -1^(n-1), same as child)
//   else if only child is a session:
//     If splitView is root:
//       Do nothing. This is allowed.
//     else if splitView is not root:
//       Replace splitView with child in its parent.
// else if splitView has no children:
//   Remove splitView from its parent

- (void)checkInvariants:(NSSplitView *)node when:(NSString *)when {
    DLog(@"checkInvariants for %@", when);
    if (node != root_) {
        if ([node isKindOfClass:[NSSplitView class]]) {
            // 1. A non-root splitview must have at least two children.
            ITCriticalError([[node subviews] count] > 1, @"A non-root splitview must have at least two children. %@", when);
            NSSplitView* parentSplit = (NSSplitView*)[node superview];
            // 3. A non-root splitview's orientation must be the opposite of its parent's.
            ITCriticalError([node isVertical] != [parentSplit isVertical], @"A non-root splitview's orientation must be the opposite of its parent's. %@", when);
        } else {
            if ([[node subviews] count] == 1) {
                NSView* onlyChild = [[node subviews] objectAtIndex:0];
                // The root splitview may have exactly one child iff that child is a SessionView.
                ITCriticalError([onlyChild isKindOfClass:[SessionView class]], @"The root splitview may have exactly one child iff that child is a SessionView. %@", when);
            }
        }
    }

    if ([node isKindOfClass:[NSSplitView class]]) {
        for (NSView* subView in [node subviews]) {
            if ([subView isKindOfClass:[NSSplitView class]]) {
                [self checkInvariants:(NSSplitView*)subView when:when];
            }
        }
    }
}

- (void)cleanupAfterRemove:(NSSplitView *)splitView {
    const int initialNumberOfSubviews = [[splitView subviews] count];
    if (initialNumberOfSubviews == 1) {
        NSView *onlyChild = [[splitView subviews] objectAtIndex:0];
        if ([onlyChild isKindOfClass:[NSSplitView class]]) {
            if (splitView == root_) {
                PtyLog(@"Case 1");
                // Remove only child.
                [onlyChild removeFromSuperview];

                // Swap splitView's orientation to match child's
                [splitView setVertical:![splitView isVertical]];

                // Move grandchildren into splitView
                for (NSView *grandchild in [[onlyChild subviews] copy]) {
                    [grandchild removeFromSuperview];
                    [splitView addSubview:grandchild];
                }
            } else {
                PtyLog(@"Case 2");
                // splitView is not root
                NSSplitView *splitViewParent = (NSSplitView *)[splitView superview];

                NSUInteger splitViewIndex = [[splitViewParent subviews] indexOfObjectIdenticalTo:splitView];
                assert(splitViewIndex != NSNotFound);
                NSView *referencePoint = splitViewIndex > 0 ? [[splitViewParent subviews] objectAtIndex:splitViewIndex - 1] : nil;

                // Remove splitView
                [splitView removeFromSuperview];

                // Move grandchildren into grandparent.
                for (NSView *grandchild in [[onlyChild subviews] copy]) {
                    [grandchild removeFromSuperview];
                    [splitViewParent addSubview:grandchild positioned:NSWindowAbove relativeTo:referencePoint];
                    ++splitViewIndex;
                    referencePoint = [[splitViewParent subviews] objectAtIndex:splitViewIndex - 1];
                }
            }
        } else {
            // onlyChild is a session
            if (splitView != root_) {
                PtyLog(@"Case 3");
                // Replace splitView with child in its parent.
                NSSplitView *splitViewParent = (NSSplitView*)[splitView superview];
                [splitViewParent replaceSubview:splitView with:onlyChild];
            }
        }
    } else if (initialNumberOfSubviews == 0) {
        if (splitView != root_) {
            PtyLog(@"Case 4");
            [self _recursiveRemoveView:splitView];
        }
    }
}

- (void)checkInvariants:(NSString *)when {
    [self checkInvariants:root_ when:when];
}

- (void)_recursiveRemoveView:(NSView *)theView {
    NSSplitView *parentSplit = (NSSplitView *)[theView superview];
    if (parentSplit) {
        // When a session is in instant replay, both the live session (which has no superview)
        // and the fakey DVR session are called here. If parentSplit is null the it's the live
        // session and there's nothing to do here. Otherwise, it's the one that is visible and
        // we take this path.
        [self checkInvariants:root_ when:@"Before removal"];
        [theView removeFromSuperview];
        [self cleanupAfterRemove:parentSplit];
        [self checkInvariants:root_ when:@"After removal"];
    }
}

- (NSRect)_recursiveViewFrame:(NSView*)aView {
    NSRect localFrame = [aView frame];
    if (aView != root_) {
        NSRect parentFrame = [self _recursiveViewFrame:[aView superview]];
        localFrame.origin.x += parentFrame.origin.x;
        localFrame.origin.y += parentFrame.origin.y;
    } else {
        localFrame.origin.x = 0;
        localFrame.origin.y = 0;
    }
    return localFrame;
}

- (PTYSession*)_recursiveSessionAtPoint:(NSPoint)point relativeTo:(__kindof NSView *)node {
    NSRect nodeFrame = [node frame];
    if (!NSPointInRect(point, nodeFrame)) {
        return nil;
    }
    if ([node isKindOfClass:[SessionView class]]) {
        SessionView *sessionView = node;
        return [self sessionForSessionView:sessionView];
    } else {
        NSSplitView *splitView = (NSSplitView*)node;
        if (node != root_) {
            point.x -= nodeFrame.origin.x;
            point.y -= nodeFrame.origin.y;
        }
        for (NSView *child in [splitView subviews]) {
            PTYSession *theSession = [self _recursiveSessionAtPoint:point relativeTo:child];
            if (theSession) {
                return theSession;
            }
        }
    }
    return nil;
}

- (void)fitSubviewsToRoot {
    // Make SessionViews full-size.
    [root_ adjustSubviews];

    // Make scrollbars the right size and put them at the tops of their session views.
    for (PTYSession *theSession in [self sessions]) {
        NSSize theSize = [theSession idealScrollViewSizeWithStyle:[parentWindow_ scrollerStyle]];
        [[theSession.view scrollview] setFrame:NSMakeRect(0,
                                                          0,
                                                          theSize.width,
                                                          theSize.height)];
        [[theSession view] updateTitleFrame];
    }
}

- (BOOL)sessionBelongsToVisibleTab {
    return [self isForegroundTab];
}

- (void)setDeferFontChanges:(BOOL)deferFontChanges {
    if (deferFontChanges == _deferFontChanges) {
        return;
    }
    _deferFontChanges = deferFontChanges;
    if (!deferFontChanges) {
        for (PTYSession *session in _sessionsWithDeferredFontChanges) {
            [self reallyChangeSessionFontSize:session adjustWindow:YES];
        }
        [_sessionsWithDeferredFontChanges removeAllObjects];
    }
}

- (void)sessionDidChangeFontSize:(PTYSession *)session
                    adjustWindow:(BOOL)adjustWindow {
    if (self.deferFontChanges) {
        if (![_sessionsWithDeferredFontChanges containsObject:session]) {
            [_sessionsWithDeferredFontChanges addObject:session];
        }
        return;
    }
    [self reallyChangeSessionFontSize:session adjustWindow:adjustWindow];
}

- (void)reallyChangeSessionFontSize:(PTYSession *)session
                       adjustWindow:(BOOL)adjustWindow {
    if (adjustWindow &&
        ![[self parentWindow] anyFullScreen] &&
        [iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange]) {
        [[self parentWindow] fitWindowToTab:self];
    }

    // If the window isn't able to adjust, or adjust enough, make the session
    // work with whatever size we ended up having.
    if ([session isTmuxClient]) {
        DLog(@"font size change triggering windowDidResize:");
        [session.tmuxController windowDidResize:[self realParentWindow]];
    } else {
        [self fitSessionToCurrentViewSize:session];
    }
    [self updateUseMetal];
}

- (SessionView *)nearestNeighborOfSession:(PTYSession *)aSession {
    NSSplitView *parentSplit = (NSSplitView*)[[aSession view] superview];
    NSView *nearestNeighbor;
    if ([[parentSplit subviews] count] > 1) {
        // Do a depth-first search to find the first descendent of the neighbor that is a
        // SessionView and make it active.
        int theIndex = [[parentSplit subviews] indexOfObjectIdenticalTo:[aSession view]];
        int neighborIndex = theIndex > 0 ? theIndex - 1 : theIndex + 1;
        nearestNeighbor = [[parentSplit subviews] objectAtIndex:neighborIndex];
        while ([nearestNeighbor isKindOfClass:[NSSplitView class]]) {
            if ([[nearestNeighbor subviews] count] == 0) {
                // This happens during replaceViewHierarchyWithParseTree
                nearestNeighbor = nil;
                break;
            }
            nearestNeighbor = [[nearestNeighbor subviews] objectAtIndex:0];
        }
    } else {
        // The window is about to close.
        nearestNeighbor = nil;
    }
    return (SessionView *)nearestNeighbor;
}

- (void)removeSession:(PTYSession*)aSession {
    SessionView *theView = aSession.view;

    if (idMap_) {
        [self unmaximize];
    }
    PtyLog(@"PTYTab removeSession:%p", aSession);
    // Grab the nearest neighbor (arbitrarily, the subview before if there is on or after if not)
    // to make its earliest descendent that is a session active.
    SessionView *nearestNeighbor = [self nearestNeighborOfSession:aSession];

    // Remove the session.
    [self _recursiveRemoveView:[aSession view]];

    if (aSession == activeSession_) {
        [self setActiveSession:[self sessionForSessionView:nearestNeighbor]];
    }

    [self recheckBlur];
    [realParentWindow_ sessionWasRemoved];
    if ([self isTmuxTab]) {
        [self fitSubviewsToRoot];
    }
    [self numberOfSessionsDidChange];

    [self.viewToSessionMap removeObjectForKey:theView];
}

- (BOOL)canSplitVertically:(BOOL)isVertical withSize:(NSSize)newSessionSize {
    NSSplitView *parentSplit = (NSSplitView *)[[activeSession_ view] superview];
    if (isVertical == [parentSplit isVertical]) {
        // Add a child to parentSplit.
        // This is a slightly bogus heuristic: if any sibling of the active session has a violated min
        // size constraint then splits are no longer possible.
        for (NSView *aView in [parentSplit subviews]) {
            NSSize actualSize = [aView frame].size;
            NSSize minSize;
            if ([aView isKindOfClass:[NSSplitView class]]) {
                NSSplitView *splitView = (NSSplitView *)aView;
                minSize = [self _recursiveMinSize:splitView respectPinning:YES];
            } else {
                SessionView *sessionView = (SessionView *)aView;
                minSize = [self _minSessionSize:sessionView respectPinning:YES];
            }
            if (isVertical && actualSize.width < minSize.width) {
                DLog(@"Not enough width for vertical split");
                return NO;
            }
            if (!isVertical && actualSize.height < minSize.height) {
                DLog(@"Not enough height for horizontal split");
                return NO;
            }
        }
        return YES;
    } else {
        // Active session will be replaced with a splitter.
        // Another bogus heuristic: if the active session's constraints have been violated then you
        // can't split.
        NSSize actualSize = [[activeSession_ view] frame].size;
        NSSize minSize = [self _minSessionSize:[activeSession_ view]
                                respectPinning:isVertical];
        if (isVertical && actualSize.width < minSize.width) {
            DLog(@"Not enough width for vertical split");
            return NO;
        }
        if (!isVertical && actualSize.height < minSize.height) {
            DLog(@"Not enough height for horizontal split");
            return NO;
        }
        return YES;
    }
}

- (void)dumpSubviewsOf:(NSSplitView *)split {
    for (NSView *v in [split subviews]) {
        PtyLog(@"View %p has height %f", v, [v frame].size.height);
    }
}

- (void)adjustSubviewsOf:(NSSplitView *)split {
    PtyLog(@"--- adjust ---");
    [split adjustSubviews];
    [self splitView:split resizeSubviewsWithOldSize:split.frame.size];
    PtyLog(@">>AFTER:");
    [self dumpSubviewsOf:split];
    PtyLog(@"<<<<<<<< end dump");
}

- (void)arrangeSplitPanesEvenly {
    [self arrangeSplitPanesEvenlyInSplitView:root_];
}

- (void)arrangeSplitPanesEvenlyInSplitView:(NSSplitView *)splitView {
    if (self.isTmuxTab) {
        [self arrangeTmuxSplitPanesEvenly];
        return;
    }
    CGFloat size;
    if (splitView.vertical) {
        size = splitView.frame.size.width - splitView.subviews.count * splitView.dividerThickness;
    } else {
        size = splitView.frame.size.height - splitView.subviews.count * splitView.dividerThickness;
    }
    size /= splitView.subviews.count;
    CGFloat offset = 0;
    for (NSView *view in splitView.subviews) {
        NSRect frame = view.frame;
        if (splitView.vertical) {
            frame.origin.x = offset;
            frame.size.width = size;
        } else {
            frame.origin.y = offset;
            frame.size.height = size;
        }
        view.frame = frame;
        NSSplitView *child = [NSSplitView castFrom:view];
        if (child) {
            [self arrangeSplitPanesEvenlyInSplitView:child];
        }
        offset += size;
        offset += splitView.dividerThickness;
    }
    [self adjustSubviewsOf:splitView];
    [self _splitViewDidResizeSubviews:splitView];
}

- (BOOL)allSplitsAreVertical:(NSSplitView *)node {
    if (!node.isVertical) {
        return NO;
    }
    for (NSView *subview in node.subviews) {
        NSSplitView *split = [NSSplitView castFrom:subview];
        if (split) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)allSplitsAreHorizontal:(NSSplitView *)node {
    if (node.isVertical) {
        return NO;
    }
    for (NSView *subview in node.subviews) {
        NSSplitView *split = [NSSplitView castFrom:subview];
        if (split) {
            return NO;
        }
    }
    return YES;
}

- (void)arrangeTmuxSplitPanesEvenly {
    if ([self allSplitsAreVertical:root_]) {
        [tmuxController_ setLayoutInWindow:self.tmuxWindow toLayout:@"even-horizontal"];
    } else if ([self allSplitsAreHorizontal:root_]) {
        [tmuxController_ setLayoutInWindow:self.tmuxWindow toLayout:@"even-vertical"];
    } else {
        [tmuxController_ setLayoutInWindow:self.tmuxWindow toLayout:@"tiled"];
    }
}

- (void)splitVertically:(BOOL)isVertical
             newSession:(PTYSession *)newSession
                 before:(BOOL)before
          targetSession:(PTYSession *)targetSession  {
    if (isMaximized_) {
        [self unmaximize];
    }
    PtyLog(@"PTYTab splitVertically");
    SessionView *targetSessionView = [targetSession view];
    NSSplitView *parentSplit = (NSSplitView*) [targetSessionView superview];
    SessionView *newView = [[SessionView alloc] initWithFrame:[targetSessionView frame]];

    // There has to be an active session, so the parent must have one child.
    assert([[parentSplit subviews] count] != 0);
    PtyLog(@"Before:");
    [self dump];
    [self checkInvariants:@"Before splitting"];
    if ([[parentSplit subviews] count] == 1) {
        PtyLog(@"PTYTab splitVertically: one child");
        // If the parent split has only one child then it must also be the root.
        assert(parentSplit == root_);

        // Set its orientation to vertical and add the new view.
        [parentSplit setVertical:isVertical];
        [parentSplit addSubview:newView
                     positioned:before ? NSWindowBelow : NSWindowAbove
                     relativeTo:targetSessionView];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [self _splitViewDidResizeSubviews:parentSplit];
    } else if ([parentSplit isVertical] != isVertical) {
        PtyLog(@"PTYTab splitVertically parent has opposite orientation");
        // The parent has the opposite orientation splits and has many children. We need to do this:
        // 1. Remove the active SessionView from its parent
        // 2. Replace it with an 'isVertical'-orientation NSSplitView
        // 3. Add two children to the 'isVertical'-orientation NSSplitView: the active session and the new view.
        NSSplitView* newSplit = [[PTYSplitView alloc] initWithFrame:[targetSessionView frame]];
        if (USE_THIN_SPLITTERS) {
            [newSplit setDividerStyle:NSSplitViewDividerStyleThin];
        }
        [newSplit setAutoresizesSubviews:YES];
        [newSplit setDelegate:self];
        [newSplit setVertical:isVertical];
        [[targetSessionView superview] replaceSubview:targetSessionView with:newSplit];
        [newSplit addSubview:before ? newView : targetSessionView];
        [newSplit addSubview:before ? targetSessionView : newView];
        [self adjustSplitSubviewSizesForPinnedSizes:newSplit];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [newSplit adjustSubviews];
        [self _splitViewDidResizeSubviews:newSplit];
    } else {
        PtyLog(@"PTYTab splitVertically multiple children");
        // The parent has same-orientation splits and there is more than one child.
        [parentSplit addSubview:newView
                     positioned:before ? NSWindowBelow : NSWindowAbove
                     relativeTo:targetSessionView];

        // Resize all subviews the same size to accommodate the new view.
        [self adjustSubviewsOf:parentSplit];
        [self _splitViewDidResizeSubviews:parentSplit];
    }
    PtyLog(@"After:");
    [self dump];
    newSession.delegate = self;
    newSession.view = newView;
    [self.viewToSessionMap setObject:newSession forKey:newView];
    [self checkInvariants:@"After splitting"];
    newSession.useMetal = NO;
    [self updateUseMetal];
}

+ (NSSize)_sessionSizeWithCellSize:(NSSize)cellSize
                        dimensions:(NSSize)dimensions
                        showTitles:(BOOL)showTitles
               showBottomStatusBar:(BOOL)showBottomStatusBar
                        rightExtra:(CGFloat)rightExtra
                        inTerminal:(id<WindowControllerInterface>)term {
    int rows = dimensions.height;
    int columns = dimensions.width;
    double charWidth = cellSize.width;
    double lineHeight = cellSize.height;
    NSSize size;
    DLog(@"    calculating session size based on %dx%d cells", columns, rows);
    DLog(@"    cell size is %@", NSStringFromSize(NSMakeSize(charWidth, lineHeight)));
    size.width = columns * charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2;
    size.height = rows * lineHeight + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;
    DLog(@"    size for content is %@", NSStringFromSize(size));
    BOOL hasScrollbar = [term scrollbarShouldBeVisible];
    DLog(@"    term=%@, hasScrollbar=%@, scrollerStyle=%@, NSScroller.preferredScrollerStyle=%@", term, @(hasScrollbar), @([term scrollerStyle]), @([NSScroller preferredScrollerStyle]));
    NSSize outerSize =
        [PTYScrollView frameSizeForContentSize:size
                       horizontalScrollerClass:nil
                         verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                    borderType:NSNoBorder
                                   controlSize:NSControlSizeRegular
                                 scrollerStyle:[term scrollerStyle]
                                    rightExtra:rightExtra];
    if (showTitles) {
        outerSize.height += [SessionView titleHeight];
    }
    if (showBottomStatusBar) {
        outerSize.height += iTermGetStatusBarHeight();
    }
    DLog(@"session size, including space for the scrollview's decoration, is %@", NSStringFromSize(outerSize));
    return outerSize;
}

- (NSSize)_sessionSize:(SessionView *)sessionView {
    PTYSession *session = [self sessionForSessionView:sessionView];
    DLog(@"Compute size of session %@", session);
    return [PTYTab _sessionSizeWithCellSize:NSMakeSize([[session textview] charWidth], [[session textview] lineHeight])
                                 dimensions:NSMakeSize([session columns], [session rows])
                                 showTitles:[sessionView showTitle]
                        showBottomStatusBar:sessionView.showBottomStatusBar
                                 rightExtra:session.desiredRightExtra
                                 inTerminal:parentWindow_];
}

- (NSSize)_minSessionSize:(SessionView*)sessionView respectPinning:(BOOL)respectPinning {
    NSSize size;
    PTYSession *session = [self sessionForSessionView:sessionView];
    size.width = kVT100ScreenMinColumns * [[session textview] charWidth] + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2;
    size.height = kVT100ScreenMinRows * [[session textview] lineHeight] + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;

    BOOL hasScrollbar = [parentWindow_ scrollbarShouldBeVisible];
    NSSize scrollViewSize =
        [PTYScrollView frameSizeForContentSize:size
                       horizontalScrollerClass:nil
                         verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                    borderType:NSNoBorder
                                   controlSize:NSControlSizeRegular
                                 scrollerStyle:[parentWindow_ scrollerStyle]
                                    rightExtra:session.desiredRightExtra];
    if (respectPinning && sessionView.preferredWidth != nil) {
        scrollViewSize.width = sessionView.preferredWidth.doubleValue;
    }
    return scrollViewSize;
}

// Return the size of a tree of splits based on the rows/cols in each session.
// If any session locked, sets *containsLockOut to YES. A locked session is one
// whose size is "canonical" when its size differs from that of its siblings.
- (NSSize)_recursiveSize:(NSSplitView *)node containsLock:(BOOL *)containsLockOut {
    PtyLog(@"Computing recursive size for node %p", node);
    NSSize size;
    size.width = 0;
    size.height = 0;

    NSSize dividerSize = NSZeroSize;
    if ([node isVertical]) {
        dividerSize.width = [node dividerThickness];
    } else {
        dividerSize.height = [node dividerThickness];
    }
    *containsLockOut = NO;

    BOOL first = YES;
    BOOL haveFoundLock = NO;
    // Iterate over each subview and add up the width/height of each plus dividers.
    // If there is a discrepancy in height/width, prefer the subview that contains
    // a locked session; else, take the max.
    for (id subview in [node subviews]) {
        NSSize subviewSize;
        if (first) {
            first = NO;
        } else {
            // Add the size of the splitter between this pane and the previous one.
            size.width += dividerSize.width;
            size.height += dividerSize.height;
            PtyLog(@"  add %lf for divider", dividerSize.height);
        }

        BOOL subviewContainsLock = NO;
        if ([subview isKindOfClass:[NSSplitView class]]) {
            // Get size of child tree at this subview.
            subviewSize = [self _recursiveSize:(NSSplitView*)subview containsLock:&subviewContainsLock];
            PtyLog(@"  add %lf for child split", subviewSize.height);
        } else {
            // Get size of session at this subview.
            SessionView* sessionView = (SessionView*)subview;
            subviewSize = [self _sessionSize:sessionView];
            PtyLog(@"  add %lf for session", subviewSize.height);
            if ([self sessionForSessionView:sessionView] == lockedSession_) {
                subviewContainsLock = YES;
            }
        }
        if (subviewContainsLock) {
            *containsLockOut = YES;
        }
        if ([node isVertical]) {
            // Vertical splitters have their subviews arranged horizontally so widths add and
            // height goes to the tallest.
            if (size.height == 0) {
                // Take the cross-grain size of the first subview.
                size.height = subviewSize.height;
            } else if ((int)size.height != (int)subviewSize.height) {
                // There's a discrepancy in cross-grain sizes among subviews.
                if (subviewContainsLock) {
                    // Prefer the locked subview.
                    size.height = subviewSize.height;
                } else if (!haveFoundLock) {
                    // This could happen if a session's font changes size.
                    size.height = MAX(size.height, subviewSize.height);
                }
            }
            size.width += subviewSize.width;
        } else {
            // Nonvertical splitters have subviews arranged vertically so heights add and width
            // goes to the widest.
            size.height += subviewSize.height;
            if (size.width == 0) {
                // Take the cross-grain size of the first subview.
                size.width = subviewSize.width;
            } else if ((int)size.width != (int)subviewSize.width) {
                // There's a discrepancy in cross-grain sizes among subviews.
                if (subviewContainsLock) {
                    // Prefer the locked subview.
                    size.width = subviewSize.width;
                } else if (!haveFoundLock) {
                    // This could happen if a session's font changes size.
                    size.width = MAX(size.width, subviewSize.width);
                }
            }
        }
        if (subviewContainsLock) {
            haveFoundLock = YES;
        }
    }

    DLog(@"Size is %@", NSStringFromSize(size));
    return size;
}

// Return the minimum size of a tree of splits so that no session is smaller than
// MIN_SESSION_COLUMNS columns by MIN_SESSION_ROWS rows.
- (NSSize)_recursiveMinSize:(NSSplitView *)node
             respectPinning:(BOOL)respectPinning {
    NSSize size;
    size.width = 0;
    size.height = 0;

    NSSize dividerSize = NSZeroSize;
    if ([node isVertical]) {
        dividerSize.width = [node dividerThickness];
    } else {
        dividerSize.height = [node dividerThickness];
    }

    BOOL first = YES;
    for (id subview in [node subviews]) {
        NSSize subviewSize;
        if (first) {
            first = NO;
        } else {
            // Add the size of the splitter between this pane and the previous one.
            size.width += dividerSize.width;
            size.height += dividerSize.height;
        }

        if ([subview isKindOfClass:[NSSplitView class]]) {
            // Get size of child tree at this subview.
            subviewSize = [self _recursiveMinSize:(NSSplitView*)subview
                                   respectPinning:respectPinning];
        } else {
            // Get size of session at this subview.
            SessionView* sessionView = (SessionView*)subview;
            subviewSize = [self _minSessionSize:sessionView
                                 respectPinning:respectPinning];
            if (node.vertical && respectPinning && sessionView.preferredWidth != nil) {
                subviewSize.width = sessionView.preferredWidth.doubleValue;
            }
        }
        if ([node isVertical]) {
            // Vertical splitters have their subviews arranged horizontally so widths add and
            // height goes to the tallest.
            if (size.height == 0) {
                // Take the cross-grain size of the first subview.
                size.height = subviewSize.height;
            } else if ((int)size.height != (int)subviewSize.height) {
                size.height = MAX(size.height, subviewSize.height);
            }
            size.width += subviewSize.width;
        } else {
            // Nonvertical splitters have subviews arranged vertically so heights add and width
            // goes to the widest.
            size.height += subviewSize.height;
            if (size.width == 0) {
                // Take the cross-grain size of the first subview.
                size.width = subviewSize.width;
            } else if ((int)size.width != (int)subviewSize.width) {
                // There's a discrepancy in cross-grain sizes among subviews.
                size.width = MAX(size.width, subviewSize.width);
            }
        }
    }
    return size;
}

// This returns the content size that would best fit the existing panes. It is the minimum size that
// fits them without having to resize downwards.
- (NSSize)size {
    BOOL ignore;
    return [self _recursiveSize:root_ containsLock:&ignore];
}

- (void)setReportIdealSizeAsCurrent:(BOOL)v {
    DLog(@"set reportIdealSizeAsCurrent=%@ for tab %@", @(v), self);
    _reportIdeal = v;
}

// This returns the current size
- (NSSize)currentSize {
    if (_reportIdeal) {
        DLog(@"Reporting ideal size %@ for tab %@", NSStringFromSize(self.size), self);
        return [self size];
    } else {
        DLog(@"Reporting size %@ of root frame for tab %@", NSStringFromSize(root_.frame.size), self);
        return [root_ frame].size;
    }
}

- (NSSize)minSize {
    return [self _recursiveMinSize:root_ respectPinning:YES];
}

- (void)setSize:(NSSize)newSize {
    if ([self isTmuxTab]) {
        [tabView_ setFrameSize:newSize];
    } else {
        PtyLog(@"PTYTab setSize:%fx%f", (float)newSize.width, (float)newSize.height);
        [self dumpSubviewsOf:root_];
        [root_ setFrameSize:newSize];
        [self adjustSubviewsOf:root_];
        [self _splitViewDidResizeSubviews:root_];
    }
}

- (void)_drawSession:(PTYSession *)session inImage:(NSImage *)viewImage atOrigin:(NSPoint)origin {
    NSImage *textviewImage = [session snapshot];

    origin.y = [viewImage size].height - [textviewImage size].height - origin.y;
    [viewImage lockFocus];
    [textviewImage drawAtPoint:origin
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1];
    [viewImage unlockFocus];
}

- (void)_recursiveDrawSplit:(NSSplitView *)splitView
                    inImage:(NSImage *)viewImage
                   atOrigin:(NSPoint)splitOrigin {
    NSPoint origin = splitOrigin;
    CGFloat myHeight = [viewImage size].height;
    BOOL first = YES;
    for (NSView *subview in [splitView subviews]) {
        if (first) {
            // No divider left/above first pane.
            first = NO;
        } else {
            // Draw the divider
            [viewImage lockFocus];
            [[splitView dividerColor] set];
            CGFloat dx = 0;
            CGFloat dy = 0;
            CGFloat hx = 0;
            CGFloat hy = 0;
            CGFloat thickness = [splitView dividerThickness];
            if ([splitView isVertical]) {
                dx = thickness;
                hy = [subview frame].size.height;
            } else {
                dy = thickness;
                hx = [subview frame].size.width;
            }
            // flip the y coordinate for drawing
            NSRectFill(NSMakeRect(origin.x, myHeight - origin.y - (dy + hy),
                                  dx + hx, dy + hy));
            [viewImage unlockFocus];

            // Advance the origin past the divider.
            origin.x += dx;
            origin.y += dy;
        }

        if ([subview isKindOfClass:[NSSplitView class]]) {
            [self _recursiveDrawSplit:(NSSplitView*)subview inImage:viewImage atOrigin:origin];
        } else {
            SessionView *sessionView = (SessionView *)subview;
            // flip the y coordinate for drawing
            CGFloat y = myHeight - origin.y - [subview frame].size.height;
            [self _drawSession:[self sessionForSessionView:sessionView]
                       inImage:viewImage
                      atOrigin:NSMakePoint(origin.x, y)];
        }
        if ([splitView isVertical]) {
            origin.x += [subview frame].size.width;
        } else {
            origin.y += [subview frame].size.height;
        }
    }
}

- (NSImage*)image:(BOOL)withSpaceForFrame {
    PtyLog(@"PTYTab image");
    NSRect tabFrame = [[realParentWindow_ tabBarControl] frame];
    NSSize viewSize = [root_ frame].size;
    CGFloat yOrigin = 0;
    CGFloat xOrigin = 0;
    if (withSpaceForFrame) {
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_BottomTab:
                viewSize.height += tabFrame.size.height;
                yOrigin += tabFrame.size.height;
                break;

            case PSMTab_TopTab:
                viewSize.height += tabFrame.size.height;
                break;

            case PSMTab_LeftTab:
                xOrigin = tabFrame.size.width;
                viewSize.width += tabFrame.size.width;
                break;
        }
    }

    if (viewSize.width == 0 || viewSize.height == 0) {
        return nil;
    }
    NSImage* viewImage = [[NSImage alloc] initWithSize:viewSize];
    [viewImage lockFocus];
    [[NSColor clearColor] set];
    NSRectFill(NSMakeRect(0, 0, viewSize.width, viewSize.height));
    [viewImage unlockFocus];

    [self _recursiveDrawSplit:root_ inImage:viewImage atOrigin:NSMakePoint(xOrigin, yOrigin)];

    return viewImage;
}

- (NSSize)_recursiveRecompact:(NSSplitView *)splitView {
    double offset = 0;
    double maxAgainstGrain = 0;
    double dividerThickness = [splitView dividerThickness];
    BOOL isVertical = [splitView isVertical];
    for (NSView *node in [splitView subviews]) {
        if ([node isKindOfClass:[NSSplitView class]]) {
            NSSize size = [self _recursiveRecompact:(NSSplitView *)node];
            if (isVertical) {
                offset += node.frame.size.width + dividerThickness;
                [node setFrame:NSMakeRect(0, offset, size.width, size.height)];
                maxAgainstGrain = MAX(maxAgainstGrain, size.height);
            } else {
                offset += node.frame.size.height + dividerThickness;
                [node setFrame:NSMakeRect(offset, 0, size.width, size.height)];
                maxAgainstGrain = MAX(maxAgainstGrain, size.width);
            }
        } else {
            SessionView *sv = (SessionView *)node;
            NSRect frame;
            frame.size = [sv compactFrame];
            if (isVertical) {
                frame.origin.x = offset;
                frame.origin.y = 0;
                offset += frame.size.width + dividerThickness;
                maxAgainstGrain = MAX(maxAgainstGrain, frame.size.height);
            } else {
                frame.origin.x = 0;
                frame.origin.y = offset;
                offset += frame.size.height + dividerThickness;
                maxAgainstGrain = MAX(maxAgainstGrain, frame.size.width);
            }
            [sv setFrame:frame];
        }
    }
    return (isVertical ?
            NSMakeSize(offset - dividerThickness, maxAgainstGrain) :
            NSMakeSize(maxAgainstGrain, offset - dividerThickness));
}

- (void)recompact {
    NSSize size = [self _recursiveRecompact:root_];
    DLog(@"Change size of root frame from %@ to %@", NSStringFromSize(root_.frame.size), NSStringFromSize(size));
    [root_ setFrame:NSMakeRect(0, 0, size.width, size.height)];
    [self fitSubviewsToRoot];
}

- (NSSize)sessionSizeForViewSize:(PTYSession *)aSession {
    PtyLog(@"PTYTab fitSessionToCurrentViewSzie");
    PtyLog(@"fitSessionToCurrentViewSize begins");
    [aSession setScrollBarVisible:[parentWindow_ scrollbarShouldBeVisible]
                            style:[parentWindow_ scrollerStyle]];
    NSSize size = [[aSession view] maximumPossibleScrollViewContentSize];
    DLog(@"Max size is %@", [NSValue valueWithSize:size]);
    const NSSize cellSize = NSMakeSize(MAX(1.0, [[aSession textview] charWidth]),
                                       MAX(1.0, [[aSession textview] lineHeight]));
    int width = (size.width - [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2) / cellSize.width;
    int height = (size.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / cellSize.height;
    PtyLog(@"fitSessionToCurrentViewSize %@ gives %d rows", [NSValue valueWithSize:size], height);
    if (width <= 0) {
        XLog(@"WARNING: Session has %d width", width);
        width = 1;
    }
    if (height <= 0) {
        XLog(@"WARNING: Session has %d height", height);
        height = 1;
    }

    PtyLog(@"PTYTab sessionSizeForViewSize: view is %fx%f, set screen to %dx%d", size.width, size.height, width, height);
    return NSMakeSize(width, height);
}

// Resize a session's rows and columns for the existing pixel size of its
// containing view.
- (BOOL)fitSessionToCurrentViewSize:(PTYSession *)aSession {
    __block BOOL result = NO;
    [aSession resetMode];
    [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        DLog(@"fitSessionToCurrentViewSize:%@", aSession);
        if ([aSession isTmuxClient]) {
            result = NO;
            return;
        }
        NSSize temp = [self sessionSizeForViewSize:aSession];
        result = [self resizeSession:aSession toSize:VT100GridSizeMake(temp.width, temp.height)];
    }];
    return result;
}

- (BOOL)resizeSession:(PTYSession *)aSession toSize:(VT100GridSize)newSize {
    if ([aSession rows] == newSize.height &&
        [aSession columns] == newSize.width) {
        PtyLog(@"PTYTab fitSessionToCurrentViewSize: noop");
        return NO;
    }
    if (newSize.width == [aSession columns] && newSize.height == [aSession rows]) {
        PtyLog(@"fitSessionToWindow - terminating early because session size doesn't change");
        return NO;
    }

    PtyLog(@"fitSessionToCurrentViewSize -  calling setSize:%@", VT100GridSizeDescription(newSize));
    [aSession setSize:newSize];
    [[aSession.view scrollview] setLineScroll:[[aSession textview] lineHeight]];
    [[aSession.view scrollview] setPageScroll:2 * [[aSession textview] lineHeight]];
    if ([aSession backgroundImagePath]) {
        [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
    }
    PtyLog(@"PTYTab fitSessionToCurrentViewSize returns");
    return YES;
}

- (BOOL)hasMultipleSessions {
    return [[root_ subviews] count] > 1;
}

// Return the left/top offset of some divider from its container's origin.
- (CGFloat)_positionOfDivider:(int)theIndex inSplitView:(NSSplitView *)splitView {
    CGFloat p = 0;
    NSArray<NSView *> *subviews = [splitView subviews];
    for (int i = 0; i <= theIndex; ++i) {
        if ([splitView isVertical]) {
            p += [[subviews objectAtIndex:i] frame].size.width;
        } else {
            p += [[subviews objectAtIndex:i] frame].size.height;
        }
        if (i > 0) {
            p += [splitView dividerThickness];
        }
    }
    return p;
}

- (NSSize)_minSizeOfView:(NSView*)view respectPinning:(BOOL)respectPinning {
    if ([view isKindOfClass:[SessionView class]]) {
        SessionView *sessionView = (SessionView*)view;
        return [self _minSessionSize:sessionView
                      respectPinning:respectPinning];
    } else {
        return [self _recursiveMinSize:(NSSplitView*)view
                        respectPinning:respectPinning];
    }
}

// Blur the window if any session is blurred.
- (BOOL)blur {
    int y = 0;
    NSArray<PTYSession *> *sessions = [self sessions];
    for (PTYSession *session in sessions) {
        if ([session transparency] > 0 &&
            [[session textview] useTransparency] &&
            [[[session profile] objectForKey:KEY_BLUR] boolValue]) {
            ++y;
        }
    }
    return y > 0;
}

- (double)blurRadius {
    double sum = 0;
    double count = 0;
    NSArray<PTYSession *> *sessions = [self sessions];
    for (PTYSession *session in sessions) {
        if ([[[session profile] objectForKey:KEY_BLUR] boolValue]) {
            sum += [[session profile] objectForKey:KEY_BLUR_RADIUS] ? [[[session profile] objectForKey:KEY_BLUR_RADIUS] floatValue] : 2.0;
            ++count;
        }
    }
    if (count > 0) {
        return MIN(iTermMaxBlurRadius(), sum / count);
    } else {
        // This shouldn't actually happen, but better safe than divide by zero.
        return 2.0;
    }
}

- (void)recheckBlur {
    PtyLog(@"PTYTab recheckBlur");
    if ([realParentWindow_ currentTab] == self &&
        ![[realParentWindow_ window] isMiniaturized]) {
        if ([self blur]) {
            [parentWindow_ enableBlur:[self blurRadius]];
        } else {
            [parentWindow_ disableBlur];
        }
    }

    // Handles a change to the parent window's useTransparency setting.
    [self updateFlexibleViewColors];
}

- (SessionView *)sessionViewWithGUID:(NSString *)guid {
    for (SessionView *view in [self sessionViews]) {
        PTYSession *session = [self sessionForSessionView:view];
        if ([session.guid isEqualToString:guid]) {
            return view;
        }
    }
    return nil;
}

// NOTE: This has a side effect of updating idMap. It maps a number (the "arrangement ID") to a
// sessionView. It also calls -[SessionView saveFrameSize].
- (BOOL)_recursiveEncodeArrangementForView:(NSView *)view
                                     idMap:(NSMutableDictionary<NSNumber *, SessionView *> *)idMap
                               isMaximized:(BOOL)isMaximized
                                  contents:(BOOL)contents
                                   encoder:(id<iTermEncoderAdapter>)encoder
                                   options:(NSDictionary *)options {
    DLog(@"Encode view %@", view);
    if (isMaximized && options[PTYTabArrangementOptionsOnlySessionID] == nil) {
        encoder[TAB_ARRANGEMENT_IS_MAXIMIZED] = @YES;
    }
    isMaximized = NO;
    if ([view isKindOfClass:[NSSplitView class]]) {
        PTYSplitView *splitView = (PTYSplitView *)view;
        encoder[TAB_ARRANGEMENT_VIEW_TYPE] = VIEW_TYPE_SPLITTER;
        encoder[TAB_ARRANGEMENT_SPLITTER_FRAME] = [PTYTab frameToDict:[view frame]];
        encoder[TAB_ARRANGEMENT_SPLITTER_ID] = splitView.stringUniqueIdentifier;
        encoder[SPLITTER_IS_VERTICAL] = @(splitView.isVertical);

        NSArray<NSView *> *subviews = splitView.subviews;
        if (options[PTYTabArrangementOptionsOnlySessionID] != nil) {
            subviews = @[ [self sessionViewWithGUID:options[PTYTabArrangementOptionsOnlySessionID]] ];
        }
        iTermOrderedDictionary<NSString *, __kindof NSView *> *index =
        [iTermOrderedDictionary byMapping:subviews
                                    block:^id _Nonnull(NSUInteger i, __kindof NSView *_Nonnull view) {
            if ([view isKindOfClass:[PTYSplitView class]]) {
                PTYSplitView *splitView = view;
                return splitView.stringUniqueIdentifier;
            }
            PTYSession *session = [self sessionForSessionView:view];
            return session.stringUniqueIdentifier;
        }];
        [encoder encodeArrayWithKey:SUBVIEWS
                        identifiers:index.keys
                         generation:iTermGenerationAlwaysEncode
                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder,
                                          NSInteger i,
                                          NSString * _Nonnull identifier,
                                          BOOL *stop) {
            return [self _recursiveEncodeArrangementForView:index[identifier]
                                                      idMap:idMap
                                                isMaximized:isMaximized
                                                   contents:contents
                                                    encoder:encoder
                                                    options:options];
        }];
        DLog(@"Done encoding splitter view %@", view);
        return YES;
    }
    SessionView *sessionView = (SessionView*)view;
    PTYSession *session = [self sessionForSessionView:sessionView];
    if (!session) {
        DLog(@"Failed to find session for view %@", view);
        return NO;
    }
    DLog(@"Will encode session %@", session);
    encoder[TAB_ARRANGEMENT_VIEW_TYPE] = VIEW_TYPE_SESSIONVIEW;
    encoder[TAB_ARRANGEMENT_SESSIONVIEW_FRAME] = [PTYTab frameToDict:[view frame]];
    [encoder encodeDictionaryWithKey:TAB_ARRANGEMENT_SESSION
                          generation:iTermGenerationAlwaysEncode
                               block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
        return [session encodeArrangementWithContents:contents
                                              encoder:encoder
                                   replacementProfile:options[PTYTabArrangementOptionsReplacementProfile]
                                          saveProgram:[options[PTYTabArrangementOptionsReplacementSaveProgram] ?: @YES boolValue]
                                         pendingJumps:options[PTYTabArrangementOptionsPendingJumps]
                                              options:options];
    }];
    encoder[TAB_ARRANGEMENT_IS_ACTIVE] = @(session == [self activeSession] || options[PTYTabArrangementOptionsOnlySessionID] != nil);

    if (idMap) {
        const NSUInteger arrangementID = idMap.count;
        encoder[TAB_ARRANGEMENT_ID] = @(arrangementID);
        [sessionView saveFrameSize];
        idMap[@(arrangementID)] = sessionView;
    }

    return YES;
}

+ (void)_recursiveDrawArrangementPreview:(NSDictionary*)arrangement frame:(NSRect)frame dark:(BOOL)dark {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        BOOL isVerticalSplitter = [[arrangement objectForKey:SPLITTER_IS_VERTICAL] boolValue];
        float xExtent = 0;
        float yExtent = 0;
        float dx = 0;
        float dy = 0;
        float pw, ph;
        NSArray *subviews = [arrangement objectForKey:SUBVIEWS];
        if (isVerticalSplitter) {
            yExtent = frame.size.height;
            dx = frame.size.width / [subviews count];
            pw = dx;
            ph = yExtent;
        } else {
            xExtent = frame.size.width;
            dy = frame.size.height / [subviews count];
            pw = xExtent;
            ph = dy;
        }
        double x = frame.origin.x;
        double y = frame.origin.y;
        for (int i = 0; i < [subviews count]; i++) {
            NSDictionary* subArrangement = [subviews objectAtIndex:i];
            NSRect subFrame = NSMakeRect(x, y, pw, ph);
            [PTYTab _recursiveDrawArrangementPreview:subArrangement frame:subFrame dark:dark];
            x += dx;
            y += dy;
        }
        [[NSColor grayColor] set];
        x = frame.origin.x;
        y = frame.origin.y;
        for (int i = 0; i < [subviews count]; i++) {
            NSBezierPath *line = [[NSBezierPath alloc] init];
            [line moveToPoint:NSMakePoint(x, y)];
            [line lineToPoint:NSMakePoint(x + xExtent, y + yExtent)];
            [line stroke];
            x += dx;
            y += dy;
        }
    } else {
        [PTYSession drawArrangementPreview:[arrangement objectForKey:TAB_ARRANGEMENT_SESSION] frame:frame dark:dark];
    }
}

+ (__kindof NSView *)_recursiveRestoreSplitters:(NSDictionary<NSString *, id> *)arrangement
                                      fromIdMap:(NSDictionary<NSNumber *, SessionView *> *)idMap
                                     sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap
                                revivedSessions:(NSMutableArray<PTYSession *> *)revivedSessions {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSRect frame = [PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SPLITTER_FRAME]];
        NSSplitView *splitter = [[PTYSplitView alloc] initWithFrame:frame
                                                   uniqueIdentifier:arrangement[TAB_ARRANGEMENT_SPLITTER_ID]];
        if (USE_THIN_SPLITTERS) {
            [splitter setDividerStyle:NSSplitViewDividerStyleThin];
        }
        [splitter setVertical:[[arrangement objectForKey:SPLITTER_IS_VERTICAL] boolValue]];

        NSArray<NSDictionary *> *subviews = [arrangement objectForKey:SUBVIEWS];
        for (NSDictionary *subArrangement in subviews) {
            NSView* subView = [PTYTab _recursiveRestoreSplitters:subArrangement
                                                       fromIdMap:idMap
                                                      sessionMap:sessionMap
                                                 revivedSessions:revivedSessions];
            if (subView) {
                [splitter addSubview:subView];
            }
        }
        return splitter;
    } else {
        if (idMap || sessionMap) {
            SessionView *sessionView = nil;
            id tabArrangementId = arrangement[TAB_ARRANGEMENT_ID];
            if (tabArrangementId && idMap[tabArrangementId]) {
                // Exiting a maximized-pane state, so we can get a session view from theMap, a map from arrangement id -> SessionView*
                // where arrangement IDs are stored in the arrangement dict.
                sessionView = [idMap objectForKey:[arrangement objectForKey:TAB_ARRANGEMENT_ID]];
                [sessionView restoreFrameSize];
                return sessionView;
            }

            NSNumber *windowPaneNumber = [arrangement objectForKey:TAB_ARRANGEMENT_TMUX_WINDOW_PANE];
            NSString *uniqueId = [PTYSession guidInArrangement:arrangement[TAB_ARRANGEMENT_SESSION]];
            if (windowPaneNumber && idMap[windowPaneNumber]) {
                // Creating splitters for a tmux tab. The arrangement is marked
                // up with window pane IDs, which may or may not already exist.
                // When restoring a tmux tab, then all session dicts in the
                // arrangement have a window pane. The presence of a
                // TAB_ARRANGEMENT_TMUX_WINDOW_PANE implies that theMap is
                // window pane->SessionView.
                sessionView = idMap[windowPaneNumber];
            } else if (uniqueId) {
                PTYSession *session = sessionMap[uniqueId];
                [revivedSessions addObject:session];
                sessionView = [session view];
            }
            NSRect frame = [PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]];
            if (sessionView) {
                // Recycle an existing session view.
                [sessionView setFrame:frame];
            } else {
                // This session is new, so set a nonnegative pending window
                // pane and we'll create a session for it later.
                sessionView = [[SessionView alloc] initWithFrame:frame];
            }
            return sessionView;
        } else {
            NSRect frame = [PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]];
            return [[SessionView alloc] initWithFrame:frame];
        }
    }
}

+ (BOOL)recursiveArrangementNode:(NSDictionary *)arrangement
                      passesTest:(BOOL (^NS_NOESCAPE)(NSDictionary *candidate))closure {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        for (NSDictionary<NSString *, id> *subArrangement in arrangement[SUBVIEWS]) {
            if ([PTYTab recursiveArrangementNode:subArrangement passesTest:closure]) {
                return YES;
            }
        }
        return NO;
    } else {
        return [PTYSession arrangement:arrangement[TAB_ARRANGEMENT_SESSION] passesTest:closure];
    }
}

+ (NSDictionary *)recursiveModifiedArrangementNode:(NSDictionary *)arrangement
                                           mutator:(NSDictionary *(^)(NSDictionary *))mutator {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSMutableArray *repairedSubviews = [NSMutableArray array];
        for (NSDictionary<NSString *, id> *subArrangement in arrangement[SUBVIEWS]) {
            [repairedSubviews addObject:[PTYTab recursiveModifiedArrangementNode:subArrangement
                                                                         mutator:mutator]];
        }
        NSMutableDictionary *result = [arrangement mutableCopy];
        result[SUBVIEWS] = repairedSubviews;
        return result;
    } else {
        NSDictionary *repairedSession = [PTYSession modifiedArrangement:arrangement[TAB_ARRANGEMENT_SESSION] mutator:mutator];
        NSMutableDictionary *result = [arrangement mutableCopy];
        result[TAB_ARRANGEMENT_SESSION] = repairedSession;
        return result;
    }
}

+ (NSDictionary *)recursiveRepairedArrangementNode:(NSDictionary *)arrangement
                          replacingProfileWithGUID:(NSString *)badGuid
                                       withProfile:(Profile *)goodProfile {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSMutableArray *repairedSubviews = [NSMutableArray array];
        for (NSDictionary<NSString *, id> *subArrangement in arrangement[SUBVIEWS]) {
            [repairedSubviews addObject:[PTYTab recursiveRepairedArrangementNode:subArrangement
                                                        replacingProfileWithGUID:badGuid
                                                                     withProfile:goodProfile]];
        }
        NSMutableDictionary *result = [arrangement mutableCopy];
        result[SUBVIEWS] = repairedSubviews;
        return result;
    } else {
        NSDictionary *repairedSession = [PTYSession repairedArrangement:arrangement[TAB_ARRANGEMENT_SESSION] replacingProfileWithGUID:badGuid withProfile:goodProfile];
        NSMutableDictionary *result = [arrangement mutableCopy];
        result[TAB_ARRANGEMENT_SESSION] = repairedSession;
        return result;
    }
}

+ (NSDictionary *)recursiveRepairedArrangementNode:(NSDictionary *)arrangement
                  replacingOldCWDOfSessionWithGUID:(NSString *)guid
                                        withOldCWD:(NSString *)replacementOldCWD {
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSArray *subviews = arrangement[SUBVIEWS];
        NSArray *repairedSubviews = [subviews mapWithBlock:^id(NSDictionary<NSString *, id> *subArrangement) {
            return [PTYTab recursiveRepairedArrangementNode:subArrangement
                           replacingOldCWDOfSessionWithGUID:guid
                                                 withOldCWD:replacementOldCWD];
        }];
        return [arrangement dictionaryBySettingObject:repairedSubviews forKey:SUBVIEWS];
    }

    return [arrangement dictionaryBySettingObject:[PTYSession repairedArrangement:arrangement[TAB_ARRANGEMENT_SESSION]
                                                 replacingOldCWDOfSessionWithGUID:guid
                                                                       withOldCWD:replacementOldCWD]
                                           forKey:TAB_ARRANGEMENT_SESSION];
}

+ (NSDictionary *)recursiveFindSessionArrangementWithGUID:(NSString *)sessionGUID
                                                     node:(NSDictionary *)arrangement {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        for (NSDictionary<NSString *, id> *subArrangement in arrangement[SUBVIEWS]) {
            NSDictionary *result = [PTYTab recursiveFindSessionArrangementWithGUID:sessionGUID node:subArrangement];
            if (result) {
                return result;
            }
        }
        return nil;
    }
    NSString *guid = [PTYSession guidInArrangement:arrangement[TAB_ARRANGEMENT_SESSION]];
    if (!guid) {
        return nil;
    }
    return [sessionGUID isEqualToString:guid] ? arrangement[TAB_ARRANGEMENT_SESSION] : nil;
}

+ (NSDictionary *)recursiveRepairedArrangementNode:(NSDictionary *)arrangement
                                    profileMutator:(Profile *(^)(Profile *))profileMutator {
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSArray *subviews = arrangement[SUBVIEWS];
        NSArray *repairedSubviews = [subviews mapWithBlock:^id(NSDictionary<NSString *, id> *subArrangement) {
            return [PTYTab recursiveRepairedArrangementNode:subArrangement
                                             profileMutator:profileMutator];
        }];
        return [arrangement dictionaryBySettingObject:repairedSubviews forKey:SUBVIEWS];
    }

    return [arrangement dictionaryBySettingObject:[PTYSession repairedArrangement:arrangement[TAB_ARRANGEMENT_SESSION]
                                                                   profileMutator:profileMutator]
                                           forKey:TAB_ARRANGEMENT_SESSION];
}

+ (NSDictionary *)recursiveRepairedArrangementNode:(NSDictionary *)arrangement
                               settingCustomLocale:(NSString *)lang {
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        NSArray *subviews = arrangement[SUBVIEWS];
        NSArray *repairedSubviews = [subviews mapWithBlock:^id(NSDictionary<NSString *, id> *subArrangement) {
            return [PTYTab recursiveRepairedArrangementNode:subArrangement
                                        settingCustomLocale:lang];
        }];
        return [arrangement dictionaryBySettingObject:repairedSubviews forKey:SUBVIEWS];
    }

    return [arrangement dictionaryBySettingObject:[PTYSession repairedArrangement:arrangement[TAB_ARRANGEMENT_SESSION]
                                                              settingCustomLocale:lang]
                                           forKey:TAB_ARRANGEMENT_SESSION];
}

- (PTYSession *)_recursiveRestoreSessions:(NSDictionary<NSString *, id> *)arrangement
                                    named:(NSString *)arrangementName
                                   atNode:(__kindof NSView *)view
                                    inTab:(PTYTab *)theTab
                            forObjectType:(iTermObjectType)objectType
                       partialAttachments:(NSDictionary *)partialAttachments
                                  options:(NSDictionary *)options {
    if ([[arrangement objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        assert([view isKindOfClass:[NSSplitView class]]);
        NSSplitView* splitter = (NSSplitView*)view;
        NSArray<NSDictionary<NSString *, id> *> *subArrangements = [arrangement objectForKey:SUBVIEWS];
        PTYSession* active = nil;
        iTermObjectType subObjectType = objectType;
        for (NSInteger i = 0; i < [subArrangements count] && i < splitter.subviews.count; ++i) {
            NSDictionary<NSString *, id> *subArrangement = subArrangements[i];
            PTYSession *session = [self _recursiveRestoreSessions:subArrangement
                                                            named:arrangementName
                                                           atNode:[[splitter subviews] objectAtIndex:i]
                                                            inTab:theTab
                                                    forObjectType:subObjectType
                                               partialAttachments:partialAttachments
                                                          options:options];
            if (session) {
                active = session;
            }
            subObjectType = iTermPaneObject;
        }
        return active;
    } else {
        assert([view isKindOfClass:[SessionView class]]);
        SessionView *sessionView = view;

        NSNumber *windowPaneNumber = [arrangement objectForKey:TAB_ARRANGEMENT_TMUX_WINDOW_PANE];
        NSString *uniqueId = [PTYSession guidInArrangement:arrangement[TAB_ARRANGEMENT_SESSION]];
        PTYSession *session;
        if (uniqueId && [self sessionForSessionView:sessionView]) {  // TODO: Is it right to check if session exists here?
            session = [self sessionForSessionView:sessionView];
            session.delegate = self;
        } else if (windowPaneNumber && [self sessionForSessionView:sessionView]) {
            // Re-use existing session because the session view was recycled
            // from the existing view hierarchy when the tmux layout changed but
            // this session was not added or removed.
            session = [self sessionForSessionView:sessionView];
            [session setSizeFromArrangement:[arrangement objectForKey:TAB_ARRANGEMENT_SESSION]];
        } else {
            session = [PTYSession sessionFromArrangement:[arrangement objectForKey:TAB_ARRANGEMENT_SESSION]
                                                   named:arrangementName
                                                  inView:view
                                            withDelegate:theTab
                                           forObjectType:objectType
                                      partialAttachments:partialAttachments
                                                 options:options];
            [self.viewToSessionMap setObject:session forKey:view];
        }
        if ([[arrangement objectForKey:TAB_ARRANGEMENT_IS_ACTIVE] boolValue]) {
            return session;
        } else {
            return nil;
        }
    }
}

+ (void)drawArrangementPreview:(NSDictionary*)arrangement frame:(NSRect)frame dark:(BOOL)dark {
    [PTYTab _recursiveDrawArrangementPreview:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                       frame:frame
                                        dark:dark];
}

- (NSArray *)_recursiveSplittersFromNode:(NSSplitView *)node
                               splitters:(NSArray<NSSplitView *> *)splitters {
    NSArray<NSSplitView *> *result = [splitters arrayByAddingObject:node];
    for (id subview in node.subviews) {
        if ([subview isKindOfClass:[NSSplitView class]]) {
            result = [self _recursiveSplittersFromNode:subview splitters:result];
        }
    }
    return result;
}

- (NSArray<NSSplitView *> *)splitters {
    return [self _recursiveSplittersFromNode:root_ splitters:@[ ]];
}

- (void)replaceWithContentsOfTab:(PTYTab *)tabToGut {
    for (PTYSession *aSession in [tabToGut sessions]) {
        aSession.delegate = self;
    }
    for (PTYSplitView *splitview in [self splitters]) {
        if (splitview != root_) {
            splitview.delegate = nil;
        }
    }
    for (PTYSplitView *splitview in [tabToGut splitters]) {
        if (splitview != tabToGut->root_) {
            splitview.delegate = self;
        }
    }

    while (root_.subviews.count) {
        [root_.subviews[0] removeFromSuperview];
    }
    [root_ setVertical:tabToGut->root_.isVertical];
    while (tabToGut->root_.subviews.count) {
        [root_ addSubview:tabToGut->root_.subviews[0]];
    }
    for (SessionView *sessionView in tabToGut.viewToSessionMap) {
        [self.viewToSessionMap setObject:[tabToGut.viewToSessionMap objectForKey:sessionView]
                                  forKey:sessionView];
    }
    [tabToGut.viewToSessionMap removeAllObjects];
}

- (void)enableFlexibleView {
    assert(!flexibleView_);
    // Interpose a vew between the tab and the root so the root can be smaller than the tab.
    flexibleView_ = [[iTermFlexibleView alloc] initWithFrame:root_.frame
                                                       color:[self flexibleViewColor]];
    [flexibleView_ setFlipped:YES];
    tabView_ = flexibleView_;
    [root_ setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [tabView_ setAutoresizesSubviews:YES];
    [root_ removeFromSuperview];
    [tabView_ addSubview:root_];
    [tabViewItem_ setView:tabView_];
}

- (void)notifyWindowChanged {
    if ([self isTmuxTab]) {
        if (!flexibleView_) {
            [self enableFlexibleView];
        }
        [self updateFlexibleViewColors];
        [flexibleView_ setFrameSize:[[realParentWindow_ tabView] frame].size];
        for (PTYSession *aSession in [self sessions]) {
            // Because it's a tmux view it won't automatically resize.
            [[aSession view] updateTitleFrame];
        }
    }
}

+ (void)_recursiveOpenPartialAttachments:(NSDictionary *)arrangement
                              completion:(void (^)(NSDictionary *))completion {
    static id lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSObject alloc] init];
    });
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        DLog(@"_recursiveOpenPartialAttachments: found splitter");
        NSArray<NSDictionary<NSString *, id> *> *subArrangements = [arrangement objectForKey:SUBVIEWS];
        __block NSDictionary *result = [[NSDictionary alloc] init];
        dispatch_group_t group = dispatch_group_create();
        for (NSDictionary *subArrangement in subArrangements) {
            dispatch_group_enter(group);
            DLog(@"_recursiveOpenPartialAttachments: recurse");
            [self _recursiveOpenPartialAttachments:subArrangement completion:^(NSDictionary *dict) {
                DLog(@"_recursiveOpenPartialAttachments: got a result from a subview");
                @synchronized(lock) {
                    result = [result dictionaryByMergingDictionary:[dict copy]];
                }
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            DLog(@"_recursiveOpenPartialAttachments: got results from all subviews");
            completion(result);
        });
    } else {
        DLog(@"_recursiveOpenPartialAttachments: found session");
        [PTYSession openPartialAttachmentsForArrangement:arrangement[TAB_ARRANGEMENT_SESSION]
                                              completion:completion];
    }
}

+ (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                  completion:(void (^)(NSDictionary *))completion {
    [self _recursiveOpenPartialAttachments:arrangement[TAB_ARRANGEMENT_ROOT]
                                completion:completion];
}

// reservedTabGUIDs gives GUIDs of other tabs which are not reachable through
// iTermController.terminals because they are siblings of a window that is still being created.
// It's passed in to ensure that tab GUIDs are truly globally unique.
+ (PTYTab *)tabWithArrangement:(NSDictionary*)arrangement
                         named:(NSString *)arrangementName
                    inTerminal:(NSWindowController<iTermWindowController> *)term
               hasFlexibleView:(BOOL)hasFlexible
                       viewMap:(NSDictionary<NSNumber *, SessionView *> *)viewMap
                    sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap
                tmuxController:(TmuxController *)tmuxController
            partialAttachments:(NSDictionary *)partialAttachments
              reservedTabGUIDs:(NSSet<NSString *> *)reservedTabGUIDs
                       options:(NSDictionary *)options {
    PTYTab *theTab;
    NSMutableArray<PTYSession *> *revivedSessions = [NSMutableArray array];
    // Build a tree with splitters and SessionViews but no PTYSessions.
    NSSplitView *newRoot = (NSSplitView *)[PTYTab _recursiveRestoreSplitters:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                                   fromIdMap:viewMap
                                                                  sessionMap:sessionMap
                                                             revivedSessions:revivedSessions];

    // Create a tab.
    theTab = [[PTYTab alloc] initWithRoot:newRoot sessions:nil];
    theTab->tmuxController_ = tmuxController;
    if (hasFlexible) {
        [theTab enableFlexibleView];
    }
    [theTab setParentWindow:term];
    theTab.delegate = term;
    [theTab->tabViewItem_ setLabel:@"Restoring..."];

    [theTab setObjectCount:[term numberOfTabs] + 1];

    // Instantiate sessions in the skeleton view tree.
    iTermObjectType objectType;
    if ([term numberOfTabs] == 0) {
        objectType = iTermWindowObject;
    } else {
        objectType = iTermTabObject;
    }
    // Give the tab a mapping from view to session for sessions that were revived. These come from
    // _recursiveRestoreSplitters:fromIdMap:sessionMap:revivedSession: matching up sessions in
    // revivedSessions with their uinque IDs in the arrangement.
    for (PTYSession *session in revivedSessions) {
        [theTab.viewToSessionMap setObject:session forKey:session.view];
    }
    [theTab setActiveSession:[theTab _recursiveRestoreSessions:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                         named:arrangementName
                                                        atNode:theTab->root_
                                                         inTab:theTab
                                                 forObjectType:objectType
                                            partialAttachments:partialAttachments
                                                       options:options]];
    theTab.titleOverride = [arrangement[TAB_ARRANGEMENT_TITLE_OVERRIDE] nilIfNull];
    NSString *guid = arrangement[TAB_GUID];
    if (guid) {
        if ([[iTermController sharedInstance] tabWithGUID:guid] ||
            [reservedTabGUIDs containsObject:guid]) {
            theTab->_guid = [[NSUUID UUID] UUIDString];
        } else {
            theTab->_guid = arrangement[TAB_GUID];
        }
    }
    [theTab updateTmuxTitleMonitor];
    return theTab;
}

+ (BOOL)arrangement:(NSDictionary *)arrangement
         passesTest:(BOOL (^NS_NOESCAPE)(NSDictionary *candidate))closure {
    return [PTYTab recursiveArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT] passesTest:closure];
}

+ (NSDictionary *)modifiedArrangement:(NSDictionary *)arrangement
                              mutator:(NSDictionary *(^)(NSDictionary *))mutator {
    NSDictionary *newRoot = [PTYTab recursiveModifiedArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT]
                                                             mutator:mutator];
    NSMutableDictionary *result = [arrangement mutableCopy];
    result[TAB_ARRANGEMENT_ROOT] = newRoot;
    return result;
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile {
    NSDictionary *newRoot = [PTYTab recursiveRepairedArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT]
                                            replacingProfileWithGUID:badGuid
                                                         withProfile:goodProfile];
    NSMutableDictionary *result = [arrangement mutableCopy];
    result[TAB_ARRANGEMENT_ROOT] = newRoot;
    return result;
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD {
    NSDictionary *newRoot = [PTYTab recursiveRepairedArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT]
                                    replacingOldCWDOfSessionWithGUID:guid
                                                          withOldCWD:replacementOldCWD];
    NSMutableDictionary *result = [arrangement mutableCopy];
    result[TAB_ARRANGEMENT_ROOT] = newRoot;
    return result;
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                       profileMutator:(Profile *(^)(Profile *))profileMutator {
    NSDictionary *newRoot = [PTYTab recursiveRepairedArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT]
                                                      profileMutator:profileMutator];
    NSMutableDictionary *result = [arrangement mutableCopy];
    result[TAB_ARRANGEMENT_ROOT] = newRoot;
    return result;
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
                  settingCustomLocale:(NSString *)lang {
    NSDictionary *newRoot = [PTYTab recursiveRepairedArrangementNode:arrangement[TAB_ARRANGEMENT_ROOT]
                                                 settingCustomLocale:lang];
    NSMutableDictionary *result = [arrangement mutableCopy];
    result[TAB_ARRANGEMENT_ROOT] = newRoot;
    return result;
}

+ (NSDictionary *)arrangementForSessionWithGUID:(NSString *)sessionGUID
                                  inArrangement:(NSDictionary *)arrangement {
    return [PTYTab recursiveFindSessionArrangementWithGUID:sessionGUID
                                                      node:arrangement[TAB_ARRANGEMENT_ROOT]];
}

// This can only be used in conjunction with
// +[tabWithArrangement:inTerminal:hasFlexibleView:viewMap:].
- (void)didAddToTerminal:(NSWindowController<iTermWindowController> *)term
         withArrangement:(NSDictionary *)arrangement {
    NSDictionary* root = [arrangement objectForKey:TAB_ARRANGEMENT_ROOT];
    if ([root[TAB_ARRANGEMENT_IS_MAXIMIZED] boolValue]) {
        [self maximize];
    }

    [self numberOfSessionsDidChange];
    [term setDimmingForSessions];

    // Handle old-style (now deprecated) tab color field.
    NSString *colorName = [arrangement objectForKey:TAB_ARRANGEMENT_COLOR];
    NSColor *tabColor = [[self class] colorForHtmlName:colorName];
    if (tabColor) {
        PTYSession *session = [self activeSession];
        [session setSessionSpecificProfileValues:@{ [session amendedColorKey:KEY_TAB_COLOR]: [tabColor dictionaryValue],
                                                     [session amendedColorKey:KEY_USE_TAB_COLOR]: @YES }];
    } else {
        [term updateTabColors];
    }
    for (PTYSession *session in self.sessions) {
        [session didFinishRestoration];
    }
}

// Uses idMap_ to reconstitute the TAB_ARRANGEMENT_SESSION elements of an arrangement including their
// contents.
- (BOOL)encodeArrangementNodeWithContents:(BOOL)includeContents
                      fromArrangementNode:(NSDictionary *)node
                                  encoder:(id<iTermEncoderAdapter>)encoder
                                  options:(NSDictionary *)options {
    DLog(@"Encode arragnement for %@ from node %@", self, node);
    if ([node[TAB_ARRANGEMENT_VIEW_TYPE] isEqual:VIEW_TYPE_SPLITTER]) {
        // Add everything in node except SUBVIEWS
        [node enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            if ([key isEqual:SUBVIEWS]) {
                return;
            }
            encoder[key] = obj;
        }];

        iTermOrderedDictionary<NSString *, NSDictionary *> *index =
        [iTermOrderedDictionary byMapping:node[SUBVIEWS]
                                    block:^id _Nonnull(NSUInteger i,
                                                       NSDictionary * _Nonnull subnode) {
            if ([subnode[TAB_ARRANGEMENT_VIEW_TYPE] isEqual:VIEW_TYPE_SPLITTER]) {
                return subnode[TAB_ARRANGEMENT_SPLITTER_ID] ?: [@(i) stringValue];
            } else {
                return [PTYSession guidInArrangement:subnode[TAB_ARRANGEMENT_SESSION]] ?: [@(i) stringValue];
            }
        }];
        __block BOOL ok = YES;
        [encoder encodeArrayWithKey:SUBVIEWS
                        identifiers:index.keys
                         generation:iTermGenerationAlwaysEncode
                              block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder,
                                          NSInteger i,
                                          NSString * _Nonnull identifier,
                                          BOOL *stop) {
            NSDictionary *subnode = index[identifier];
            if (![self encodeArrangementNodeWithContents:includeContents
                                     fromArrangementNode:subnode
                                                 encoder:encoder
                                                 options:options]) {
                // If one leaf fails to encode, toss the whole tab out because it'll be a disaster
                // trying to restore it.
                ok = NO;
                return NO;
            }
            return YES;
        }];
        return ok;
    }

    // Leaf node case.
    // Add everything in node except TAB_ARRANGEMENT_SESSION.
    [node enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([key isEqual:TAB_ARRANGEMENT_SESSION]) {
            return;
        }
        encoder[key] = obj;
    }];

    // If something should go wrong, it's better to do nothing than to
    // assert. Bad inputs are always possible.
    NSNumber *sessionId = node[TAB_ARRANGEMENT_ID];
    if (!sessionId) {
        XLog(@"No session ID in arrangement node %@", node);
        return NO;
    }

    SessionView *sessionView = idMap_[sessionId];
    if (![sessionView isKindOfClass:[SessionView class]]) {
        XLog(@"Bogus value in idmap for key %@: %@", sessionId, sessionView);
        return NO;
    }
    PTYSession *session = [self sessionForSessionView:sessionView];
    if (!session) {
        XLog(@"No session for view");
        return NO;
    }
    return [encoder encodeDictionaryWithKey:TAB_ARRANGEMENT_SESSION
                                 generation:iTermGenerationAlwaysEncode
                                      block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
        return [session encodeArrangementWithContents:includeContents
                                              encoder:encoder
                                   replacementProfile:nil
                                          saveProgram:YES
                                         pendingJumps:nil
                                              options:options];
    }];
}

static NSString *const PTYTabArrangementOptionsOnlySessionID = @"PTYTabArrangementOptionsOnlySessionID";
static NSString *const PTYTabArrangementOptionsReplacementProfile = @"PTYTabArrangementOptionsReplacementProfile";
static NSString *const PTYTabArrangementOptionsReplacementSaveProgram = @"PTYTabArrangementOptionsReplacementSaveProgram";
static NSString *const PTYTabArrangementOptionsPendingJumps = @"PTYTabArrangementOptionsPendingJumps";

// This method used to take a gross shortcut and call -unmaximize and
// -maximize. Because we support 10.7 window restoration, it gets called
// periodically. Issue 3389 calls out a "flash" that happens because of this.
// In the future make sure this method doesn't do anything that could affect
// the view's appearance, such as temporary resizing.
- (NSDictionary *)arrangementConstructingIdMap:(BOOL)constructIdMap
                                      contents:(BOOL)contents {
    return [self arrangementConstructingIdMap:constructIdMap contents:contents options:@{}];
}

- (NSDictionary *)arrangementConstructingIdMap:(BOOL)constructIdMap
                                      contents:(BOOL)contents
                                       options:(NSDictionary *)options {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    iTermMutableDictionaryEncoderAdapter *adapter = [[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict];
    const BOOL commit = [self encodeWithContents:contents
                                  constructIdMap:constructIdMap
                                         encoder:adapter
                                         options:options];
    if (!commit) {
        return nil;
    }
    return dict;
}

- (NSDictionary *)arrangementWithOnlySession:(PTYSession *)session
                                     profile:(Profile *)profile
                                 saveProgram:(BOOL)saveProgram
                                pendingJumps:(NSArray<iTermSSHReconnectionInfo *> *)pendingJumps {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    iTermMutableDictionaryEncoderAdapter *adapter = [[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict];

    NSDictionary *options = [@{ PTYTabArrangementOptionsOnlySessionID: session.guid,
                                PTYTabArrangementOptionsReplacementProfile: profile,
                                PTYTabArrangementOptionsPendingJumps: pendingJumps ?: [NSNull null],
                                PTYTabArrangementOptionsReplacementSaveProgram: @(saveProgram),
                             } dictionaryByRemovingNullValues];
    const BOOL commit = [self encodeWithContents:NO
                                  constructIdMap:NO
                                         encoder:adapter
                                         options:options];
    if (!commit) {
        return nil;
    }
    return dict;
}

- (BOOL)encodeWithContents:(BOOL)contents
                   encoder:(id<iTermEncoderAdapter>)encoder {
    return [self encodeWithContents:contents constructIdMap:NO encoder:encoder options:@{}];
}

- (BOOL)encodeWithContents:(BOOL)contents
            constructIdMap:(BOOL)constructIdMap
                   encoder:(id<iTermEncoderAdapter>)encoder
                   options:(NSDictionary *)options {
    DLog(@"Encode tab %@", self);
    encoder[TAB_GUID] = _guid;
    encoder[TAB_ARRANGEMENT_TITLE_OVERRIDE] = self.titleOverride.length ? self.titleOverride : nil;

    if (isMaximized_ && options[PTYTabArrangementOptionsOnlySessionID] == nil) {
        DLog(@"Tab is maximized");
        // We never construct id map in this case because it must already exist.
        assert(!constructIdMap);
        assert(savedArrangement_);

        // Add contents to savedArrangement_ and return that.
        // When maximized, savedArrangement_  contains the unmaximized
        // arrangement, including the maximized session. However, it is old
        // (created when the session was maximized), and doesn't have contents.
        // We need to return an updated version of it with the current
        // contents.

        // Set the maximized flag in the root.
        NSMutableDictionary *mutableRootNode =
            [savedArrangement_[TAB_ARRANGEMENT_ROOT] mutableCopy];
        mutableRootNode[TAB_ARRANGEMENT_IS_MAXIMIZED] = @YES;

        // Fill in the contents.
        return [encoder encodeDictionaryWithKey:TAB_ARRANGEMENT_ROOT
                                     generation:iTermGenerationAlwaysEncode
                                          block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
            return [self encodeArrangementNodeWithContents:contents
                                       fromArrangementNode:mutableRootNode
                                                   encoder:encoder
                                                   options:options];
        }];
    }
    // Build a new arrangement. If |constructIdMap| is set then pass in
    // idMap_, and it will get filled in with number->SessionView entries.
    if (constructIdMap) {
        assert(idMap_);
    }
    DLog(@"Will encode each view in tab");
    return [encoder encodeDictionaryWithKey:TAB_ARRANGEMENT_ROOT
                                 generation:iTermGenerationAlwaysEncode
                                      block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
        return [self _recursiveEncodeArrangementForView:root_
                                                  idMap:constructIdMap ? idMap_ : nil
                                            isMaximized:NO
                                               contents:contents
                                                encoder:encoder
                                                options:options];
    }];
}


- (NSDictionary *)arrangementForDuplication {
    NSMutableDictionary *arrangement = [[self arrangementConstructingIdMap:NO contents:NO options:@{ PTYSessionArrangementOptionsForDuplication: @YES }] mutableCopy];
    arrangement[TAB_GUID] = [[NSUUID UUID] UUIDString];
    return arrangement;
}

- (NSDictionary*)arrangement {
    return [self arrangementConstructingIdMap:NO contents:NO];
}

- (NSDictionary*)arrangementWithContents:(BOOL)contents {
    return [self arrangementConstructingIdMap:NO contents:contents];
}

+ (BOOL)_recursiveBuildSessionMap:(NSMutableDictionary<NSString *, PTYSession *> *)sessionMap
                  withArrangement:(NSDictionary *)arrangement
                         sessions:(NSArray *)sessions {
    if ([arrangement[TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        for (NSDictionary *subviewDict in arrangement[SUBVIEWS]) {
            if (![self _recursiveBuildSessionMap:sessionMap
                                 withArrangement:subviewDict
                                        sessions:sessions]) {
                return NO;
            }
        }
        return YES;
    } else {
        // Is a session view
        NSString *sessionGuid = [PTYSession guidInArrangement:arrangement[TAB_ARRANGEMENT_SESSION]];
        if (!sessionGuid) {
            return NO;
        }
        PTYSession *session = nil;
        for (PTYSession *aSession in sessions) {
            if ([aSession.guid isEqualToString:sessionGuid]) {
                session = aSession;
                break;
            }
        }
        if (!session) {
            return NO;
        }
        sessionMap[sessionGuid] = session;
        return YES;
    }
}

+ (NSDictionary<NSString *, PTYSession *> *)sessionMapWithArrangement:(NSDictionary *)arrangement
                                                             sessions:(NSArray *)sessions {
    NSMutableDictionary<NSString *, PTYSession *> *sessionMap = [NSMutableDictionary dictionary];
    if (![self _recursiveBuildSessionMap:sessionMap
                         withArrangement:arrangement[TAB_ARRANGEMENT_ROOT]
                                sessions:sessions]) {
        return nil;
    } else {
        return sessionMap;
    }
}

typedef struct {
    NSSize minimumSize;
    NSSize maximumSize;
} iTermSizeRange;

+ (iTermSizeRange)_recursiveSetSizesInTmuxParseTree:(NSMutableDictionary *)parseTree
                                         showTitles:(BOOL)showTitles
                                showBottomStatusBar:(BOOL)showBottomStatusBar
                                           bookmark:(Profile *)profile
                                         inTerminal:(NSWindowController<iTermWindowController> *)term {
    CGFloat splitterSize = 1;  // hack: should use -[NSSplitView dividerThickness], but don't have an instance yet.
    iTermSizeRange totalSize = { NSZeroSize, NSZeroSize };

    DLog(@"recursiveSetSizesInTmuxParseTree for node:\n%@", parseTree);

    BOOL isVertical = NO;
    switch ([[parseTree objectForKey:kLayoutDictNodeType] intValue]) {
        case kLeafLayoutNode: {
            DLog(@"Leaf node. Compute size of session");
            const NSSize cellSize = [self cellSizeForBookmark:profile];
            const NSSize size = [PTYTab _sessionSizeWithCellSize:cellSize
                                                      dimensions:NSMakeSize([parseTree[kLayoutDictWidthKey] intValue],
                                                                            [parseTree[kLayoutDictHeightKey] intValue])
                                                      showTitles:showTitles
                                             showBottomStatusBar:showBottomStatusBar
                                                      rightExtra:[PTYSession desiredRightExtraForProfile:profile]
                                                      inTerminal:term];
            parseTree[kLayoutDictPixelWidthKey] = @(size.width);
            parseTree[kLayoutDictPixelHeightKey] = @(size.height);

            const NSSize maximumSize = NSMakeSize(size.width + cellSize.width,
                                                  size.height + cellSize.height);
            parseTree[kLayoutDictMaximumPixelWidthKey] = @(maximumSize.width);
            parseTree[kLayoutDictMaximumPixelHeightKey] = @(maximumSize.height);
            return (iTermSizeRange){ size, maximumSize };
        }
        case kVSplitLayoutNode:
            isVertical = YES;
        case kHSplitLayoutNode: {
            BOOL isFirst = YES;
            for (NSMutableDictionary *node in parseTree[kLayoutDictChildrenKey]) {
                const iTermSizeRange sizeRange =
                    [self _recursiveSetSizesInTmuxParseTree:node
                                                 showTitles:showTitles
                                        showBottomStatusBar:showBottomStatusBar
                                                   bookmark:profile
                                                 inTerminal:term];

                const CGFloat splitter = isFirst ? 0 : splitterSize;
                SetWithGrainDim(isVertical,
                                &totalSize.minimumSize,
                                (WithGrainDim(isVertical, totalSize.minimumSize) +
                                 WithGrainDim(isVertical, sizeRange.minimumSize) +
                                 splitter));
                SetAgainstGrainDim(isVertical,
                                   &totalSize.minimumSize,
                                   MAX(AgainstGrainDim(isVertical, totalSize.minimumSize),
                                       AgainstGrainDim(isVertical, sizeRange.minimumSize)));
                SetWithGrainDim(isVertical,
                                &totalSize.maximumSize,
                                (WithGrainDim(isVertical, totalSize.maximumSize) +
                                 WithGrainDim(isVertical, sizeRange.maximumSize) +
                                 splitter));
                SetAgainstGrainDim(isVertical,
                                   &totalSize.maximumSize,
                                   MAX(AgainstGrainDim(isVertical, totalSize.maximumSize),
                                       AgainstGrainDim(isVertical, sizeRange.maximumSize)));
                isFirst = NO;
            }
            parseTree[kLayoutDictPixelWidthKey] = @(totalSize.minimumSize.width);
            parseTree[kLayoutDictPixelHeightKey] = @(totalSize.minimumSize.height);

            parseTree[kLayoutDictMaximumPixelWidthKey] = @(totalSize.maximumSize.width);
            parseTree[kLayoutDictMaximumPixelHeightKey] = @(totalSize.maximumSize.height);
            break;
        }
    }
    return totalSize;
}

+ (NSDictionary *)_recursiveArrangementForDecoratedTmuxParseTree:(NSDictionary *)parseTree
                                                        bookmark:(Profile *)bookmark
                                                          origin:(NSPoint)origin
                                                activeWindowPane:(int)activeWp
                                                  tmuxController:(TmuxController *)tmuxController
                                                          window:(int)window {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    BOOL isVertical = YES;
    switch ([[parseTree objectForKey:kLayoutDictNodeType] intValue]) {
        case kLeafLayoutNode: {
            [dict setObject:VIEW_TYPE_SESSIONVIEW forKey:TAB_ARRANGEMENT_VIEW_TYPE];
            NSRect frame;
            frame.origin = origin;
            frame.size.width = [[parseTree objectForKey:kLayoutDictPixelWidthKey] intValue];
            frame.size.height = [[parseTree objectForKey:kLayoutDictPixelHeightKey] intValue];
            [dict setObject:[PTYTab frameToDict:frame] forKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME];
            [dict setObject:[PTYSession arrangementFromTmuxParsedLayout:parseTree
                                                               bookmark:bookmark
                                                         tmuxController:tmuxController
                                                                 window:window]
                     forKey:TAB_ARRANGEMENT_SESSION];
            int wp = [[parseTree objectForKey:kLayoutDictWindowPaneKey] intValue];
            [dict setObject:[NSNumber numberWithInt:wp]
                     forKey:TAB_ARRANGEMENT_TMUX_WINDOW_PANE];
            if (wp == activeWp) {
                [dict setObject:[NSNumber numberWithBool:YES] forKey:TAB_ARRANGEMENT_IS_ACTIVE];
            }
            break;
        }

        case kHSplitLayoutNode:
            isVertical = NO;
            // fall through
        case kVSplitLayoutNode: {
            [dict setObject:VIEW_TYPE_SPLITTER forKey:TAB_ARRANGEMENT_VIEW_TYPE];
            [dict setObject:[NSNumber numberWithBool:isVertical] forKey:SPLITTER_IS_VERTICAL];
            NSRect frame;
            frame.origin = origin;
            frame.size.width = [[parseTree objectForKey:kLayoutDictPixelWidthKey] intValue];
            frame.size.height = [[parseTree objectForKey:kLayoutDictPixelHeightKey] intValue];
            [dict setObject:[PTYTab frameToDict:frame] forKey:TAB_ARRANGEMENT_SPLITTER_FRAME];

            NSMutableArray *subviews = [NSMutableArray array];
            NSArray *children = [parseTree objectForKey:kLayoutDictChildrenKey];
            NSPoint childOrigin = NSZeroPoint;
            double dividerThickness = 1;  // HACK! Don't have a splitter yet :(
            for (NSDictionary *child in children) {
                NSDictionary *childDict = [PTYTab _recursiveArrangementForDecoratedTmuxParseTree:child
                                                                                        bookmark:bookmark
                                                                                          origin:childOrigin
                                                                                activeWindowPane:activeWp
                                                                                  tmuxController:tmuxController
                                                                                          window:window];
                [subviews addObject:childDict];
                NSRect childFrame = [PTYTab dictToFrame:[childDict objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]];
                if (isVertical) {
                    childOrigin.x += dividerThickness + childFrame.size.width;
                } else {
                    childOrigin.y += dividerThickness + childFrame.size.height;
                }
            }
            [dict setObject:subviews forKey:SUBVIEWS];
            break;
        }
    }
    return dict;
}

+ (NSDictionary *)arrangementForDecoratedTmuxParseTree:(NSDictionary *)parseTree
                                              bookmark:(Profile *)bookmark
                                      activeWindowPane:(int)activeWp
                                        tmuxController:(TmuxController *)tmuxController
                                                window:(int)window {
    NSMutableDictionary *arrangement = [NSMutableDictionary dictionary];
    [arrangement setObject:[PTYTab _recursiveArrangementForDecoratedTmuxParseTree:parseTree
                                                                         bookmark:bookmark
                                                                           origin:NSZeroPoint
                                                                 activeWindowPane:activeWp
                                                                   tmuxController:tmuxController
                                                                           window:window]
                    forKey:TAB_ARRANGEMENT_ROOT];
    // -- BEGIN HACK --
    // HACK! Set the first session we find as the active one.
    NSMutableDictionary *temp = [arrangement objectForKey:TAB_ARRANGEMENT_ROOT];
    while ([[temp objectForKey:TAB_ARRANGEMENT_VIEW_TYPE] isEqualToString:VIEW_TYPE_SPLITTER]) {
        temp = [[temp objectForKey:SUBVIEWS] objectAtIndex:0];
    }
    [temp setObject:[NSNumber numberWithBool:YES] forKey:TAB_ARRANGEMENT_IS_ACTIVE];
    // -- END HACK --

    return arrangement;
}

- (BOOL)isTmuxTab
{
    return tmuxController_ != nil;
}

- (int)tmuxWindow {
    ITBetaAssert(self.variablesScope.tmuxWindow != nil, @"No tmux window");
    return self.variablesScope.tmuxWindow.intValue;
}

- (void)setTmuxWindow:(int)window {
    assert(self.variables);
    assert([self variablesScope]);
    [[self variablesScope] setValue:@(window) forVariableNamed:iTermVariableKeyTabTmuxWindow];
}

- (NSString *)tmuxWindowName {
    return [self.variablesScope valueForVariableName:iTermVariableKeyTabTmuxWindowName];
}

// Note this is to inform of us of the window name, not to initiate a change of it.
- (void)setTmuxWindowName:(NSString *)tmuxWindowName {
    [[self realParentWindow] setWindowTitle];
    [self.variablesScope setValue:tmuxWindowName forVariableNamed:iTermVariableKeyTabTmuxWindowName];
    // In case the name change causes the title to change
    [_tmuxTitleMonitor updateOnce];
    [self updateTabTitle];
}

- (void)setTmuxFontTable:(iTermFontTable *)fontTable
                hSpacing:(double)hs
                vSpacing:(double)vs {
    [self.tmuxController setTmuxFontTable:fontTable
                                 hSpacing:hs
                                 vSpacing:vs
                                   window:self.tmuxWindow];
}

+ (void)setSizesInTmuxParseTree:(NSMutableDictionary *)parseTree
                     inTerminal:(NSWindowController<iTermWindowController> *)term
                         zoomed:(BOOL)zoomed
                        profile:(Profile *)profile {
    NSArray *theChildren = [parseTree objectForKey:kLayoutDictChildrenKey];
    BOOL haveMultipleSessions = ([theChildren count] > 1);
    const BOOL perPaneTitleBarEnabled = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
    // TODO: I'm not sure why zoomed is taken into account here but not in
    // other places like this that decide if titles should be shown.
    const BOOL showTitles = perPaneTitleBarEnabled && (zoomed || haveMultipleSessions);

    // Begin by decorating the tree with pixel sizes.
    [PTYTab _recursiveSetSizesInTmuxParseTree:parseTree
                                   showTitles:showTitles
                          showBottomStatusBar:NO
                                     bookmark:profile
                                   inTerminal:term];
}

+ (NSMutableDictionary *)parseTreeWithInjectedRootSplit:(NSMutableDictionary *)parseTree
{
    if ([[parseTree objectForKey:kLayoutDictNodeType] intValue] == kLeafLayoutNode) {
        // Inject a splitter at the root to follow our convention even if there is only one session.
        NSMutableDictionary *newRoot = [NSMutableDictionary dictionary];
        [newRoot setObject:[NSNumber numberWithInt:kVSplitLayoutNode] forKey:kLayoutDictNodeType];
        [newRoot setObject:[NSNumber numberWithInt:0] forKey:kLayoutDictXOffsetKey];
        [newRoot setObject:[NSNumber numberWithInt:0] forKey:kLayoutDictYOffsetKey];
        [newRoot setObject:[parseTree objectForKey:kLayoutDictWidthKey] forKey:kLayoutDictWidthKey];
        [newRoot setObject:[parseTree objectForKey:kLayoutDictHeightKey] forKey:kLayoutDictHeightKey];
        [newRoot setObject:[parseTree objectForKey:kLayoutDictPixelWidthKey] forKey:kLayoutDictPixelWidthKey];
        [newRoot setObject:[parseTree objectForKey:kLayoutDictPixelHeightKey] forKey:kLayoutDictPixelHeightKey];
        [newRoot setObject:[NSMutableArray arrayWithObject:parseTree] forKey:kLayoutDictChildrenKey];
        return newRoot;
    } else {
        return parseTree;
    }
}

- (void)reloadTmuxLayout {
    BOOL shouldZoom = isMaximized_;
    if (isMaximized_) {
        DLog(@"Unmaximizing");
        [self unmaximize];
    }
    [PTYTab setSizesInTmuxParseTree:parseTree_
                         inTerminal:realParentWindow_
                             zoomed:isMaximized_
                            profile:[self.tmuxController profileForWindow:self.tmuxWindow]];
    [self resizeViewsInViewHierarchy:root_ forNewLayout:parseTree_];
    if (shouldZoom) {
        [self maximizeAfterApplyingTmuxParseTree:visibleParseTree_ ?: parseTree_
                                  tmuxController:self.tmuxController];
    }
    [[root_ window] makeFirstResponder:[[self activeSession] mainResponder]];
}

+ (PTYTab *)openTabWithTmuxLayout:(NSMutableDictionary *)parseTree
                    visibleLayout:(NSMutableDictionary *)visibleParseTree
                       inTerminal:(NSWindowController<iTermWindowController> *)term
                       tmuxWindow:(int)tmuxWindow
                   tmuxController:(TmuxController *)tmuxController {
    Profile *profile = [tmuxController profileForWindow:tmuxWindow];
    [PTYTab setSizesInTmuxParseTree:parseTree
                         inTerminal:term
                             zoomed:NO
                            profile:profile];
    parseTree = [PTYTab parseTreeWithInjectedRootSplit:parseTree];

    // Grow the window to fit the tab before adding it
    NSSize rootSize = NSMakeSize([[parseTree objectForKey:kLayoutDictPixelWidthKey] intValue],
                                 [[parseTree objectForKey:kLayoutDictPixelHeightKey] intValue]);
    [term fitWindowToTabSize:rootSize];

    // Now we can make an arrangement and restore it.
    NSDictionary *arrangement = [PTYTab arrangementForDecoratedTmuxParseTree:parseTree
                                                                    bookmark:profile
                                                            activeWindowPane:0
                                                              tmuxController:tmuxController
                                                                      window:tmuxWindow];
    PTYTab *theTab = [self tabWithArrangement:arrangement
                                        named:nil
                                   inTerminal:term
                              hasFlexibleView:YES
                                      viewMap:nil
                                   sessionMap:nil
                               tmuxController:tmuxController
                           partialAttachments:nil
                             reservedTabGUIDs:[NSSet set]
                                      options:nil];

    NSArray *theChildren = [parseTree objectForKey:kLayoutDictChildrenKey];
    BOOL haveMultipleSessions = ([theChildren count] > 1);
    const BOOL titlesEnabled = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
    const BOOL shouldShowTitles = (titlesEnabled && haveMultipleSessions);
    if (shouldShowTitles) {
        // Set the showTitle flag so recompact does not make the views too small.
        for (PTYSession *aSession in [theTab sessions]) {
            [aSession.view setShowTitle:YES adjustScrollView:NO];
        }
    }
    // You have to update the scrollbar style before calling -appendTab: or else the calculated size
    // of the tmux client will be wrong in fullscreen when the system is configured for legacy scrollers.
    const BOOL hasScrollbar = [term scrollbarShouldBeVisible];
    const NSScrollerStyle style = [term scrollerStyle];
    for (PTYSession *session in [theTab sessions]) {
        [session setScrollBarVisible:hasScrollbar style:style];
    }
    theTab.tmuxWindow = tmuxWindow;
    theTab->parseTree_ = parseTree;
    theTab->visibleParseTree_ = visibleParseTree;

    if (parseTree[kLayoutDictTabIndex]) {
        // Add tab at a specified index.
        [term insertTab:theTab atIndex:[parseTree[kLayoutDictTabIndex] intValue]];
    } else if ([parseTree[kLayoutDictTabOpenedManually] boolValue] ||
               [parseTree[kLayoutDictAllInitialWindowsAdded] boolValue]) {
        [term addTabAtAutomaticallyDeterminedLocation:theTab];
    } else {
        [term appendTab:theTab];
    }
    [theTab didAddToTerminal:term withArrangement:arrangement];
    [theTab updateTmuxTitleMonitor];
    return theTab;
}

- (void)addSplitter:(NSSplitView *)splitter
        toIntervalMap:(IntervalMap *)intervalMap
          forHeight:(BOOL)forHeight
             origin:(NSPoint)origin {
    BOOL first = YES;
    int minPos, size;
    NSSize cellSize = [PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]];
    for (NSView *view in [splitter subviews]) {
        if (forHeight == [splitter isVertical]) {
            if ([splitter isVertical]) {
                // want to know height
                minPos = origin.x;
                size = view.frame.size.width;
            } else {
                // want to know width
                minPos = origin.y;
                size = view.frame.size.height;
            }
        } else {
            if ([splitter isVertical]) {
                // want to know width
                minPos = origin.y;
                size = view.frame.size.height;
            } else {
                // want to know height
                minPos = origin.x;
                size = view.frame.size.width;
            }
        }
        if ([view isKindOfClass:[NSSplitView class]]) {
            NSSplitView *sub = (NSSplitView *)view;
            [self addSplitter:sub
                  toIntervalMap:intervalMap
                    forHeight:forHeight
                       origin:origin];
        } else {
            SessionView *sv = (SessionView *)view;
            PTYSession *session = [self sessionForSessionView:sv];
            // Look at the amount of space this SessionView could possibly
            // contain. The PTYScrollView might be smaller than it so it's not
            // relevant.
            NSRect sessionViewFrame = [session.view.scrollview frame];
            NSSize contentSize = [PTYScrollView contentSizeForFrameSize:sessionViewFrame.size
                                                horizontalScrollerClass:nil
                                                  verticalScrollerClass:[realParentWindow_ scrollbarShouldBeVisible] ? [[session.view.scrollview verticalScroller] class] : nil
                                                             borderType:session.view.scrollview.borderType
                                                            controlSize:NSControlSizeRegular
                                                          scrollerStyle:session.view.scrollview.scrollerStyle
                                                             rightExtra:session.desiredRightExtra];

            int chars = forHeight ? (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / cellSize.height :
                                    (contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2) / cellSize.width;
            [intervalMap incrementNumbersBy:chars
                                    inRange:[IntRange rangeWithMin:minPos size:size]];
        }
        if (!first && [splitter isVertical] != forHeight) {
            // Splitters have to be counted and there is a splitter before this view
            [intervalMap incrementNumbersBy:1
                                    inRange:[IntRange rangeWithMin:minPos size:size]];
        }
        first = NO;
        if ([splitter isVertical]) {
            origin.x += view.frame.size.width + [splitter dividerThickness];
        } else {
            origin.y += view.frame.size.height + [splitter dividerThickness];
        }
    }
}

- (int)tmuxSizeForHeight:(BOOL)forHeight
{
    // The minimum size of a splitter is determined thus:
    // Keep an interval map M: [min, max) -> count
    // Where intervals are in the space perpendicular to the size we're measuring.
    // Increment [min, max) by the number of splitters.
    // If a subview is a splitter, recurse
    // If a subview is a sessionview, add its number of rows/cols based on pixels
    // Pick the largest interval

    // So:
    // When forHeight is true, we want the tallest column.
    // intervalMap maps (min x pixel, max x pixel) -> number of cells (plus 1 for each splitter)
    // Then the largest value is the last row/column.
    IntervalMap *intervalMap = [[IntervalMap alloc] init];
    [self addSplitter:root_
          toIntervalMap:intervalMap
            forHeight:forHeight
               origin:NSZeroPoint];
    NSArray *values = [intervalMap allValues];
    NSArray *sortedValues = [values sortedArrayUsingSelector:@selector(compare:)];
    return [[sortedValues lastObject] intValue];
}

// This is for tmux tabs. The decoration size is the total amount of space used
// within a split view or session view.
typedef struct {
    // Number of points consumed by title bar, status bar, scrollbars, and
    // margins. Anything that isn't cells.
    NSSize points;

    // Number of cells used as dividers between split panes.
    VT100GridSize cells;
} PTYTabDecorationSize;



- (NSSize)tmuxSize {
    if (self.tmuxController.variableWindowSize) {
        return [self variableTmuxSize];
    } else {
        return [self fixedTmuxSize];
    }
}

// Returns the size in characters of the window size that fits this tab's contents.
// Because our dividers+margins+titlebars may be either smaller or larger than tmux's dividers,
// we need to pick the largest value that fits our window. When you have a tab like this:
//
//  ┌───┬───┐
//  │   │ B │
//  │ A ├───┤
//  │   │ C │
//  └───┴───┘
//
// In the following discussion, h = cell height.
// If the divider between B and C is really thick, then you should report floor((B*h+C*h+1)/h) rows.
//   In this case, A will have some unused space at the bottom.
// If the divider between B and C is really thin, then you should report A rows.
//   In this case, C will have some unused space at the bottom.
//
// Let's draw it again with dividers.
// Suppose a cell is 16 points tall and sessions have 2 point margins.
// Notation for iTerm2 will be points(cells). Differences are noted with *.
//
//  Thin dividers                        Thick dividers
//  iTerm2             tmux              iTerm2             tmux
//  ┌──────┬────────┐  ┌──────┬─────┐    ┌──────┬────────┐  ┌──────┬─────┐
//  │      │672(42) │  │      │ 42  │    │      │652(40) │  │      │ 40  │
//  │ 1367 ├────1───┤  │  85  ├──1──┤    │ 1367 ├───41───┤  │  82* ├──1──┤
//  │ (85) │690(43) │  │      │ 42* │    │ (85) │670(41) │  │      │ 41  │
//  └──────┴────────┘  └──────┴─────┘    └──────┴────────┘  └──────┴─────┘
//
// The algorithm employed here is:
// * Slice the view up into columns. Slices are made at the extents of horizontal dividers and the x
//   coordinate of vertical dividers. All the sessions in a slice are stacked on top of each other.
//   There are never two horizontally adjacent in a column.
// * Vmax = number of horizontal dividers in column with the most horizontal dividers
// * Cmax = number of rows that would fit in that column
// * Vmin = number of horizontal dividers in column with the fewest horizontal dividers
// * Cmin = number of rows that would fit in that column
// * The height to give tmux is the smalles MIN(Vmin + Cmin, Vmax + Cmax among across all columns
//   slices.
//
// The same applies for width and horizontal splits.

- (NSSize)variableTmuxSize {
    // The size in points we need to get it to (at most). Only the current tab will have the proper
    // frame, but during window creation there might not be a current tab.
    PTYTab *currentTab = [realParentWindow_ currentTab];
    if (!currentTab) {
        currentTab = self;
    }
    DLog(@"Calculate variable tmux size for:\n%@", [root_ iterm_recursiveDescription]);

    // baseTmuxSize is how large the tmux window ought to be for the PTYSplitView.
    __block NSSize baseTmuxSize = NSZeroSize;

    // Size we will grow to. Note that we don't use the tabView's frame. That is because when the
    // tabbar is a titlebar accessory and it's about to be removed, we need to include its size in
    // the target size. The tabView hasn't been resized yet because AppKit.
    const NSSize targetSizePoints = [currentTab.delegate tabExpectedSize];

    // Current size
    const NSSize currentSize = root_.frame.size;

    DLog(@"Target size in points is %@. Current size is %@", NSStringFromSize(targetSizePoints),
         NSStringFromSize(currentSize));

    // The size of a cell.
    NSSize cellSize = [PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]];
    NSArray<SessionView *> *allSessionViews = self.isMaximized ? @[ self.activeSession.view ] : [self sessionViews];

    const CGSize margins = NSMakeSize([iTermPreferences intForKey:kPreferenceKeySideMargins] * 2,
                                      [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);
    const CGFloat dividerThickness = root_.dividerThickness;
    DLog(@"Margins are %@, divider thickness is %@, cell size is %@", NSStringFromSize(margins), @(dividerThickness), NSStringFromSize(cellSize));

    PTYSplitView *root = [PTYSplitView castFrom:root_];
    assert(root);

    // Get frames of horizontal dividers
    NSArray<PTYSplitViewDividerInfo *> *horizontalInfos = [root transitiveDividerLocationsVertical:NO];
    DLog(@"Horizontal divider info: %@", horizontalInfos);

    // Get frames of vertical dividers
    NSArray<PTYSplitViewDividerInfo *> *verticalInfos = [root transitiveDividerLocationsVertical:YES];
    DLog(@"Vertical infos: %@", verticalInfos);

    // Construct slice points for columns
    NSMutableIndexSet *columnSlicePoints = [NSMutableIndexSet indexSet];
    [horizontalInfos enumerateObjectsUsingBlock:^(PTYSplitViewDividerInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [columnSlicePoints addIndex:MAX(0, NSMinX(obj.frame))];
        [columnSlicePoints addIndex:MAX(0, NSMaxX(obj.frame))];
    }];
    [verticalInfos enumerateObjectsUsingBlock:^(PTYSplitViewDividerInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [columnSlicePoints addIndex:MAX(0, NSMinX(obj.frame))];
    }];
    [columnSlicePoints addIndex:0];
    [columnSlicePoints addIndex:MAX(0, currentSize.width)];
    DLog(@"Column slice points: %@", columnSlicePoints);

    baseTmuxSize.height = -1;
    __block NSInteger last = -1;
    [columnSlicePoints enumerateIndexesUsingBlock:^(NSUInteger point, BOOL * _Nonnull stop) {
        if (last == -1) {
            last = point;
            return;
        }
        // Column slice is [last, point).
        const NSRect columnFrame = NSMakeRect(last, 0, point - last, currentSize.height);
        DLog(@"Consider column frame %@", NSStringFromRect(columnFrame));

        // Find sessions in this column.
        NSArray<SessionView *> *sessionViewsInSlice =
        [allSessionViews filteredArrayUsingBlock:^BOOL(SessionView *view) {
            const NSRect sessionViewFrame = [root convertRect:view.bounds fromView:view];
            return NSIntersectsRect(sessionViewFrame, columnFrame);
        }];
        DLog(@"Contains these session views: %@", sessionViewsInSlice);

        if (sessionViewsInSlice.count == 0) {
            return;
        }
        const NSInteger numberOfDividers = sessionViewsInSlice.count - 1;
        DLog(@"Has %@ dividers", @(numberOfDividers));

        NSArray<NSNumber *> *decorationSizes =
        [sessionViewsInSlice mapWithBlock:^id(SessionView *sessionView) {
            DLog(@"%@ showTitle=%@ showBottomStatusBar=%@ ",
                 sessionView, @(sessionView.showTitle), @(sessionView.showBottomStatusBar));
            const CGFloat titleBarHeight = sessionView.showTitle ? SessionView.titleHeight : 0;
            // NOTE: At the time of writing tmux tabs can’t have per-pane status bars. Should that ever
            // change, this line of code might prevent a bug.
            const CGFloat statusBarHeight = sessionView.showBottomStatusBar ? iTermGetStatusBarHeight() : 0;
            return @(titleBarHeight + statusBarHeight + margins.height);
        }];
        DLog(@"Decoration sizes are %@", decorationSizes);
        const CGFloat totalDecorationSize = [decorationSizes sumOfNumbers] + numberOfDividers * dividerThickness;
        DLog(@"Total decoration size is %@", @(totalDecorationSize));
        const CGFloat C = floor((currentSize.height - totalDecorationSize) / cellSize.height);
        const CGFloat rows = numberOfDividers + C;
        DLog(@"C=%@, rows=%@", @(C), @(rows));
        if (baseTmuxSize.height < 0 || rows < baseTmuxSize.height) {
            DLog(@"Reduce height to %@", @(rows));
            baseTmuxSize.height = rows;
        }

        last = point;
    }];
    if (baseTmuxSize.height < 0) {
        DLog(@"Bump height to 0");
        baseTmuxSize.height = 0;
    }
    DLog(@"Resulting height is %@", @(baseTmuxSize.height));


    // Construct slice points for rows
    NSMutableIndexSet *rowSlicePoints = [NSMutableIndexSet indexSet];
    [verticalInfos enumerateObjectsUsingBlock:^(PTYSplitViewDividerInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [rowSlicePoints addIndex:MAX(0, NSMinY(obj.frame))];
        [rowSlicePoints addIndex:MAX(0, NSMaxY(obj.frame))];
    }];
    [horizontalInfos enumerateObjectsUsingBlock:^(PTYSplitViewDividerInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [rowSlicePoints addIndex:MAX(0, NSMinY(obj.frame))];
    }];
    [rowSlicePoints addIndex:0];
    [rowSlicePoints addIndex:MAX(0, currentSize.height)];

    [rowSlicePoints addIndex:0];
    [rowSlicePoints addIndex:currentSize.height];
    DLog(@"Row slice points: %@", rowSlicePoints);

    baseTmuxSize.width = -1;
    last = -1;
    [rowSlicePoints enumerateIndexesUsingBlock:^(NSUInteger point, BOOL * _Nonnull stop) {
        if (last == -1) {
            last = point;
            return;
        }
        // Row slice is [last, point).
        const NSRect rowFrame = NSMakeRect(0, last, currentSize.width, point - last);
        DLog(@"Row slice frame is %@", NSStringFromRect(rowFrame));

        // Find sessions in this row.
        NSArray<SessionView *> *sessionViewsInSlice =
        [allSessionViews filteredArrayUsingBlock:^BOOL(SessionView *view) {
            const NSRect sessionViewFrame = [root convertRect:view.bounds fromView:view];
            return NSIntersectsRect(sessionViewFrame, rowFrame);
        }];
        DLog(@"Contains sessions: %@", sessionViewsInSlice);

        if (sessionViewsInSlice.count == 0) {
            return;
        }
        const NSInteger numberOfDividers = sessionViewsInSlice.count - 1;
        DLog(@"Number of dividers is %@", @(numberOfDividers));

        NSArray<NSNumber *> *decorationSizes =
        [sessionViewsInSlice mapWithBlock:^id(SessionView *sessionView) {
            const NSSize scrollViewDecorationSize = [PTYScrollView frameSizeForContentSize:NSMakeSize(0, 0)
                                                                   horizontalScrollerClass:nil
                                                                     verticalScrollerClass:sessionView.scrollview.hasVerticalScroller ? sessionView.scrollview.verticalScroller.class : nil
                                                                                borderType:sessionView.scrollview.borderType
                                                                               controlSize:NSControlSizeRegular
                                                                             scrollerStyle:sessionView.scrollview.scrollerStyle
                                                                                rightExtra:sessionView.desiredRightExtra];
            return @(margins.width + scrollViewDecorationSize.width);
        }];
        const CGFloat totalDecorationSize = [decorationSizes sumOfNumbers] + numberOfDividers * dividerThickness;
        DLog(@"total decoration size is %@", @(totalDecorationSize));

        const CGFloat C = floor((currentSize.width - totalDecorationSize) / cellSize.width);
        const CGFloat columns = numberOfDividers + C;
        DLog(@"C=%@, columns=%@", @(C), @(columns));
        if (baseTmuxSize.width < 0 || columns < baseTmuxSize.width) {
            DLog(@"Reduce width to %@", @(columns));
            baseTmuxSize.width = columns;
        }

        last = point;
    }];
    if (baseTmuxSize.width < 0) {
        DLog(@"Bump width");
        baseTmuxSize.width = 0;
    }

    // Now adjust the result for the growth that is about to happen.

    // The pixel growth (+ for growth, - for shrinkage) needed to attain the target
    const NSSize sizeDiff = NSMakeSize(targetSizePoints.width - currentSize.width,
                                       targetSizePoints.height - currentSize.height);
    DLog(@"sizeDiff=%@", NSStringFromSize(sizeDiff));

    // The characters growth (+ growth, - shrinkage) needed to attain the target
    // The rationale for using floor() is this:
    //  If it needs to grow, we certainly don't want it to be too big. We expect there to be a bit of
    //  extra margin sometimes.
    //  If it needs to shrink, we'd rather it shrink too much than to little, for the same reason.
    NSSize charsDiff = NSMakeSize(floor(sizeDiff.width / cellSize.width),
                                  floor(sizeDiff.height / cellSize.height));
    DLog(@"charsDiff=%@", NSStringFromSize(charsDiff));

    // The character size closest to the target.
    const NSSize tmuxSize = NSMakeSize(floor(baseTmuxSize.width + charsDiff.width),
                                       floor(baseTmuxSize.height + charsDiff.height));
    DLog(@"RETURN: tmuxSize = %@ currentSize=%@ targetSize=%@", NSStringFromSize(tmuxSize),
          NSStringFromSize(currentSize), NSStringFromSize(targetSizePoints));
    return tmuxSize;
}

// Returns the size (in characters) of the window size that fits this tab's
// contents, while going over as little as possible.  It picks the smallest
// height that can contain every column and every row (counting characters and
// dividers as 1).
- (NSSize)fixedTmuxSize {
    DLog(@"Compute size in characters of the window that fits this tab's contents");

    // The current size of the sessions in this tab in characters
    // ** BUG **
    // This rounds off fractional parts. We really need to know the maximum capacity, and fractional parts can add up to more than one whole char.
    // Here's a real world example. When scrollbars come into being, every pane interior shrinks by 15px width.
    // In this case, there are two panes side-by-side [|], 345 and 338px. The sizeDiff is 30px. It should add up to 99 chars:
    // (gdb) p (345.0 - 10.0)/7.0 + (338.0 - 10.0)/7.0 + 30.0/7.0
    // $28 = 99
    // But rounding errors shrink it to 97 chars:
    // (gdb) p (345 - 10)/7 + (338 - 10)/7 + 30/7
    // $29 = 97
    // For now, we work around this problem with respect to scrollbars by handling them specially.
    NSSize rootSizeChars = NSMakeSize([self tmuxSizeForHeight:NO], [self tmuxSizeForHeight:YES]);

    // The size in pixels we need to get it to (at most). Only the current tab will have the proper
    // frame, but during window creation there might not be a current tab.
    PTYTab *currentTab = [realParentWindow_ currentTab];
    if (!currentTab) {
        currentTab = self;
    }
    NSSize targetSizePixels = [currentTab.delegate tabExpectedSize];

    // The current size in pixels
    NSSize rootSizePixels = [root_ frame].size;

    // The pixel growth (+ for growth, - for shrinkage) needed to attain the target
    NSSize sizeDiff = NSMakeSize(targetSizePixels.width - rootSizePixels.width,
                                 targetSizePixels.height - rootSizePixels.height);

    // The size of a character
    NSSize charSize = [PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]];

    // The characters growth (+ growth, - shrinkage) needed to attain the target
    NSSize charsDiff = NSMakeSize(floor(sizeDiff.width / charSize.width),
                                  floor(sizeDiff.height / charSize.height));

    // The character size closest to the target.
    NSSize tmuxSize = NSMakeSize(rootSizeChars.width + charsDiff.width,
                                 rootSizeChars.height + charsDiff.height);

    DLog(@"tmuxSize: rootSizeChars=%@, targetSizePixels=%@, rootSizePixels=%@, sizeDiff=%@, charSize=%@, charsDiff=%@, tmuxSize=%@",
         NSStringFromSize(rootSizeChars),
         NSStringFromSize(targetSizePixels),
         NSStringFromSize(rootSizePixels),
         NSStringFromSize(sizeDiff),
         NSStringFromSize(charSize),
         NSStringFromSize(charsDiff),
         NSStringFromSize(tmuxSize));

    return tmuxSize;
}

- (BOOL)_recursiveParseTree:(NSMutableDictionary *)parseTree matchesViewHierarchy:(NSView *)view {
    LayoutNodeType layoutNodeType = [[parseTree objectForKey:kLayoutDictNodeType] intValue];
    LayoutNodeType typeOfView;
    if ([view isKindOfClass:[NSSplitView class]]) {
        NSSplitView *split = (NSSplitView *) view;
        if ([split isVertical]) {
            typeOfView = kVSplitLayoutNode;
        } else {
            typeOfView = kHSplitLayoutNode;
        }
    } else {
        typeOfView = kLeafLayoutNode;
    }

    if (layoutNodeType != typeOfView) {
        return NO;
    }
    if (typeOfView == kLeafLayoutNode) {
        SessionView *sessionView = (SessionView *)view;
        PTYSession *session = [self sessionForSessionView:sessionView];
        return session.tmuxPane == [parseTree[kLayoutDictWindowPaneKey] intValue];
    }

    NSArray *treeChildren = [parseTree objectForKey:kLayoutDictChildrenKey];
    NSArray *subviews = [view subviews];
    if ([treeChildren count] != [subviews count]) {
        return NO;
    }
    for (int i = 0; i < treeChildren.count; i++) {
        if (![self _recursiveParseTree:[treeChildren objectAtIndex:i]
                  matchesViewHierarchy:[subviews objectAtIndex:i]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)parseTree:(NSMutableDictionary *)parseTree matchesViewHierarchy:(NSView *)view {
    DLog(@"Checking if a parse tree matches a view hierarchy.\nParse tree:\n%@\nView hierarchy:\n%@",
         parseTree,
         [view iterm_recursiveDescription]);
    return [self _recursiveParseTree:parseTree matchesViewHierarchy:view];
}

// NOTE: This is only called on tmux tabs.
// It updates the SessionView and nested PTYSplitView frames for a new layout.
- (void)_recursiveResizeViewsInViewHierarchy:(NSView *)view
                              forArrangement:(NSDictionary *)arrangement
{
    assert(arrangement);
    [view setNeedsDisplay:YES];
    if ([view isKindOfClass:[NSSplitView class]]) {
        NSDictionary *frameDict = [arrangement objectForKey:TAB_ARRANGEMENT_SPLITTER_FRAME];
        NSRect frame = [PTYTab dictToFrame:frameDict];
        [view setFrame:frame];

        int i = 0;
        NSArray *subarrangements = [arrangement objectForKey:SUBVIEWS];
        for (NSView *child in [view subviews]) {
            [self _recursiveResizeViewsInViewHierarchy:child
                                        forArrangement:[subarrangements objectAtIndex:i]];
            i++;
        }
    } else {
        SessionView *sessionView = (SessionView *)view;
        PTYSession *theSession = [self sessionForSessionView:sessionView];
        [theSession resizeFromArrangement:[arrangement objectForKey:TAB_ARRANGEMENT_SESSION]];
        assert([arrangement objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]);
        NSRect aFrame = [PTYTab dictToFrame:[arrangement objectForKey:TAB_ARRANGEMENT_SESSIONVIEW_FRAME]];
        [sessionView setFrame:aFrame];
        [[theSession view] updateTitleFrame];
    }
}

- (int)nodeSize:(ITMSplitTreeNode *)node width:(BOOL)sumWidths {
    int sum = 0;
    // Perpindicular is true if we're summing widths with a horizontal divider
    // or summing heights with a vertical divider. The size of the first child
    // is the result in this case.
    const BOOL perpindicular = ((sumWidths && !node.vertical) ||
                                (!sumWidths && node.vertical));
    for (ITMSplitTreeNode_SplitTreeLink *link in node.linksArray) {
        switch (link.childOneOfCase) {
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Node:
                sum += [self nodeSize:link.node width:sumWidths];
                break;
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Session:
                sum += link.session.gridSize.width;
                break;
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_GPBUnsetOneOfCase:
                assert(NO);
        }
        if (perpindicular) {
            return sum;
        }
    }
    return sum;
}

- (iTermTmuxLayoutBuilderLeafNode *)layoutBuilderLeafNodeForLink:(ITMSplitTreeNode_SplitTreeLink *)link {
    PTYSession *session = [self sessionWithGUID:link.session.uniqueIdentifier];
    if (!session) {
        return nil;
    }
    return [[iTermTmuxLayoutBuilderLeafNode alloc] initWithSessionOfSize:VT100GridSizeMake(link.session.gridSize.width,
                                                                                           link.session.gridSize.height)
                                                              windowPane:session.tmuxPane];
}

- (iTermTmuxLayoutBuilderNode *)layoutBuilderNodeForSplitTreeNode:(ITMSplitTreeNode *)node {
    if (node.linksArray.count == 1 &&
        node.linksArray[0].childOneOfCase == ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Node) {
        ITMSplitTreeNode_SplitTreeLink *link = node.linksArray[0];
        return [self layoutBuilderLeafNodeForLink:link];
    }
    
    iTermTmuxLayoutBuilderInteriorNode *result = [[iTermTmuxLayoutBuilderInteriorNode alloc] initWithVerticalDividers:node.vertical];
    for (ITMSplitTreeNode_SplitTreeLink *link in node.linksArray) {
        switch (link.childOneOfCase) {
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Node: {
                iTermTmuxLayoutBuilderNode *childNode = [self layoutBuilderNodeForSplitTreeNode:link.node];
                if (!childNode) {
                    return nil;
                }
                [result addNode:childNode];
                break;
            }
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_Session: {
                iTermTmuxLayoutBuilderLeafNode *leafNode = [self layoutBuilderLeafNodeForLink:link];
                if (!leafNode) {
                    return nil;
                }
                [result addNode:leafNode];
                break;
            }
            case ITMSplitTreeNode_SplitTreeLink_Child_OneOfCase_GPBUnsetOneOfCase:
                return nil;
        }
    }
    return result;
}

- (void)setTmuxSizesFromSplitTreeNode:(ITMSplitTreeNode *)node {
    iTermTmuxLayoutBuilderNode *root = [self layoutBuilderNodeForSplitTreeNode:node];
    iTermTmuxLayoutBuilder *builder = [[iTermTmuxLayoutBuilder alloc] initWithRootNode:root];
    if (!self.realParentWindow.anyFullScreen) {
        VT100GridSize clientSize = builder.clientSize;
        [self.tmuxController setSize:NSMakeSize(clientSize.width, clientSize.height)
                              window:self.tmuxWindow];
    }
    [self.tmuxController setLayoutInWindow:self.tmuxWindow toLayout:builder.layoutString];
}

- (void)setSizesFromSplitTreeNode:(ITMSplitTreeNode *)node {
    if (self.tmuxTab) {
        [self setTmuxSizesFromSplitTreeNode:node];
        return;
    }
    CGSize newRootSize = [self setSizesFromSplitTreeNode:node splitView:root_];
    if (!self.realParentWindow.anyFullScreen) {
        root_.frame = NSMakeRect(0, 0, newRootSize.width, newRootSize.height);
        [self recursiveAdjustSubviews:root_];
        [self.parentWindow fitWindowToTab:self];
    } else {
        [self recursiveAdjustSubviews:root_];
        for (PTYSession *session in self.sessions) {
            [self fitSessionToCurrentViewSize:session];
        }
    }
}

- (CGSize)setSizesFromSplitTreeNode:(ITMSplitTreeNode *)node splitView:(NSSplitView *)splitView {
    CGFloat x = 0;
    CGFloat y = 0;
    CGSize size = CGSizeMake(0, 0);
    for (NSInteger i = 0; i < splitView.subviews.count; i++) {
        NSView *subview = splitView.subviews[i];
        ITMSplitTreeNode_SplitTreeLink *link = node.linksArray[i];
        CGSize newSubviewSize;
        NSSplitView *splitView = [NSSplitView castFrom:subview];
        SessionView *sessionView = [SessionView castFrom:subview];
        if (splitView) {
            newSubviewSize = [self setSizesFromSplitTreeNode:link.node splitView:splitView];
        } else if (sessionView) {
            PTYSession *session = (PTYSession *)sessionView.delegate;
            newSubviewSize = [PTYTab _sessionSizeWithCellSize:[PTYTab cellSizeForBookmark:session.profile]
                                                   dimensions:NSMakeSize(link.session.gridSize.width,
                                                                         link.session.gridSize.height)
                                                   showTitles:sessionView.showTitle
                                          showBottomStatusBar:sessionView.showBottomStatusBar
                                                   rightExtra:session.desiredRightExtra
                                                   inTerminal:realParentWindow_];
        } else {
            assert(false);
        }
        subview.frame = NSMakeRect(x, y, newSubviewSize.width, newSubviewSize.height);
        if (node.vertical) {
            size.width += newSubviewSize.width;
            if (i > 0) {
                size.width += splitView.dividerThickness;
            }
            x = size.width;
            size.height = MAX(size.height, newSubviewSize.height);
        } else {
            size.height += newSubviewSize.height;
            if (i > 0) {
                size.height += splitView.dividerThickness;
            }
            y = size.height;
            size.width = MAX(size.width, newSubviewSize.width);
        }
    }
    return size;
}

- (void)recursiveAdjustSubviews:(NSSplitView *)splitView {
    [splitView adjustSubviews];
    for (id subview in splitView.subviews) {
        [[NSSplitView castFrom:subview] adjustSubviews];
    }
}

- (void)resizeViewsInViewHierarchy:(NSView *)view forNewLayout:(NSMutableDictionary *)parseTree {
    Profile *bookmark = [[ProfileModel sharedInstance] defaultBookmark];
    NSDictionary *arrangement = [PTYTab _recursiveArrangementForDecoratedTmuxParseTree:parseTree
                                                                              bookmark:bookmark
                                                                                origin:NSZeroPoint
                                                                      activeWindowPane:[activeSession_ tmuxPane]
                                                                        tmuxController:nil
                                                                                window:self.tmuxWindow];
    ++tmuxOriginatedResizeInProgress_;
    [realParentWindow_ beginTmuxOriginatedResize];
    [self _recursiveResizeViewsInViewHierarchy:view forArrangement:arrangement];
    [realParentWindow_ tmuxTabLayoutDidChange:NO tab:nil variableWindowSize:tmuxController_.variableWindowSize];
    [realParentWindow_ endTmuxOriginatedResize];
    --tmuxOriginatedResizeInProgress_;
    [root_ setNeedsDisplay:YES];
    [flexibleView_ setNeedsDisplay:YES];
}

- (void)setRoot:(NSSplitView *)newRoot
{
    root_ = newRoot;
    if (USE_THIN_SPLITTERS) {
        [root_ setDividerStyle:NSSplitViewDividerStyleThin];
    }
    [root_ setAutoresizesSubviews:YES];
    [root_ setDelegate:self];
    [PTYTab _recursiveSetDelegateIn:root_ to:self];
    [flexibleView_ setSubviews:[NSArray array]];
    [flexibleView_ addSubview:newRoot];
    if (!flexibleView_) {
        [root_ setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
        tabView_ = newRoot;
    }
    [tabViewItem_ setView:tabView_];
}

- (TmuxController *)tmuxController {
    return tmuxController_;
}

- (void)installTmuxTitleMonitor {
    assert(!_tmuxTitleMonitor);
    if (self.tmuxWindow < 0) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _tmuxTitleMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:tmuxController_.gateway
                                                                  scope:self.variablesScope
                                                   fallbackVariableName:iTermVariableKeySessionWindowName
                                                                 format:@"#{T:set-titles-string}"
                                                                 target:[NSString stringWithFormat:@"@%@", @(self.tmuxWindow)]
                                                           variableName:iTermVariableKeyTabTmuxWindowTitle
                                                                  block:^(NSString * _Nonnull newTitle) {
        [weakSelf tmuxTitleDidChange];
    }];
    [_tmuxTitleMonitor updateOnce];
    if (self.titleOverride.length == 0) {
        // Show the tmux window title if both the tmux option set-titles is on and the user hasn't
        // already set a title override.
        self.variablesScope.tabTitleOverrideFormat = [NSString stringWithFormat:@"%@\\(%@?)",
                                                      [iTermAdvancedSettingsModel tmuxTitlePrefix],
                                                      iTermVariableKeyTabTmuxWindowTitle];
    }
}

- (void)tmuxTitleDidChange {
    [self.activeSession tmuxWindowTitleDidChange];
}

- (void)uninstallTmuxTitleMonitor {
    assert(_tmuxTitleMonitor);
    [_tmuxTitleMonitor invalidate];
    _tmuxTitleMonitor = nil;
}

- (NSSize)rootViewSize {
    if (flexibleView_) {
        return flexibleView_.frame.size;
    }
    return root_.frame.size;
}

// Adjust the parse tree to minimize "holes" by allowing sessions to grow by just under one cell in size.
+ (NSMutableDictionary *)tweakedParseTree:(NSDictionary *)parseTree
                        fillingRootOfSize:(NSSize)desiredSize {
    NSMutableDictionary *dict = [parseTree mutableCopy];

    const NSSize actualSize = NSMakeSize([parseTree[kLayoutDictPixelWidthKey] intValue],
                                         [parseTree[kLayoutDictPixelHeightKey] intValue]);

    BOOL isVertical = NO;
    switch ((LayoutNodeType)[parseTree[kLayoutDictNodeType] intValue]) {
        case kLeafLayoutNode: {
            const NSSize maximumSize = NSMakeSize([parseTree[kLayoutDictMaximumPixelWidthKey] intValue],
                                                  [parseTree[kLayoutDictMaximumPixelHeightKey] intValue]);
            NSSize tweakedSize = actualSize;

            if (actualSize.width < desiredSize.width) {
                tweakedSize.width = MIN(desiredSize.width, maximumSize.width);
            }
            if (actualSize.height < desiredSize.height) {
                tweakedSize.height = MIN(desiredSize.height, maximumSize.height);
            }
            dict[kLayoutDictPixelWidthKey] = @(tweakedSize.width);
            dict[kLayoutDictPixelHeightKey] = @(tweakedSize.height);
            break;
        }

        case kVSplitLayoutNode:
            isVertical = YES;
        case kHSplitLayoutNode: {
            NSMutableArray *replacementChildren = [NSMutableArray array];
            NSSize desiredGrowth = NSMakeSize(desiredSize.width - actualSize.width,
                                              desiredSize.height - actualSize.height);
            NSSize tweakedSize = actualSize;
            for (NSMutableDictionary *node in parseTree[kLayoutDictChildrenKey]) {
                // Figure out how much this node would need to grow by and set `exaggeratedSize` to that size.
                const NSSize originalSize = NSMakeSize([node[kLayoutDictPixelWidthKey] intValue],
                                                       [node[kLayoutDictPixelHeightKey] intValue]);
                NSSize exaggeratedSize = originalSize;
                if (desiredGrowth.width > 0) {
                    exaggeratedSize.width += desiredGrowth.width;
                }
                if (desiredGrowth.height > 0) {
                    exaggeratedSize.height += desiredGrowth.height;
                }

                // Create an updated node that is hopefully larger.
                NSMutableDictionary *replacement = [self tweakedParseTree:node
                                                        fillingRootOfSize:exaggeratedSize];

                // Deduct its actual growth from the desired growth. It may take many siblings’
                // growth to satisfy all of the desired growth.
                const NSSize updatedSize = NSMakeSize([replacement[kLayoutDictPixelWidthKey] intValue],
                                                      [replacement[kLayoutDictPixelHeightKey] intValue]);
                const NSSize growth = NSMakeSize(updatedSize.width - originalSize.width,
                                                 updatedSize.height - originalSize.height);
                if (isVertical) {
                    desiredGrowth.width -= growth.width;
                    tweakedSize.width += growth.width;
                    tweakedSize.height = MAX(tweakedSize.height, updatedSize.height);
                } else {
                    desiredGrowth.height -= growth.height;
                    tweakedSize.height += growth.height;
                    tweakedSize.width = MAX(tweakedSize.width, updatedSize.width);
                }

                [replacementChildren addObject:replacement];
            }
            dict[kLayoutDictChildrenKey] = replacementChildren;
            dict[kLayoutDictPixelWidthKey] = @(tweakedSize.width);
            dict[kLayoutDictPixelHeightKey] = @(tweakedSize.height);
            break;
        }
    }
    return dict;
}

- (void)replaceViewHierarchyWithParseTree:(NSMutableDictionary *)parseTree
                           tmuxController:(TmuxController *)tmuxController {
    SessionView *nearestNeighbor = [self nearestNeighborOfSession:self.activeSession];

    NSMutableDictionary *arrangement = [NSMutableDictionary dictionary];
    parseTree = [PTYTab parseTreeWithInjectedRootSplit:parseTree];
    if (tmuxController.variableWindowSize) {
        parseTree = [PTYTab tweakedParseTree:parseTree fillingRootOfSize:self.rootViewSize];
        DLog(@"Tweaked parse tree:\n%@", parseTree);
    }
    [arrangement setObject:[PTYTab _recursiveArrangementForDecoratedTmuxParseTree:parseTree
                                                                         bookmark:[self.tmuxController profileForWindow:self.tmuxWindow]
                                                                           origin:NSZeroPoint
                                                                 activeWindowPane:[activeSession_ tmuxPane]
                                                                   tmuxController:tmuxController
                                                                           window:self.tmuxWindow]
                    forKey:TAB_ARRANGEMENT_ROOT];

    // Create a map of window pane -> SessionView *
    NSMutableDictionary<NSNumber *, SessionView *> *idMap = [NSMutableDictionary dictionary];
    for (PTYSession *aSession in [self sessions]) {
        idMap[@([aSession tmuxPane])] = aSession.view;
    }
    NSArray *preexistingPanes = [[idMap allKeys] copy];
    NSSplitView *newRoot = (NSSplitView *)[PTYTab _recursiveRestoreSplitters:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                                   fromIdMap:idMap
                                                                  sessionMap:nil
                                                             revivedSessions:nil];
    // Instantiate sessions in the skeleton view tree.
    iTermObjectType objectType;
    if ([realParentWindow_ numberOfTabs] == 0) {
        objectType = iTermWindowObject;
    } else {
        objectType = iTermTabObject;
    }
    // TODO does this preserve the active session correctly? i don't think so
    PTYSession *activeSession = [self _recursiveRestoreSessions:[arrangement objectForKey:TAB_ARRANGEMENT_ROOT]
                                                          named:nil
                                                         atNode:newRoot
                                                          inTab:self
                                                  forObjectType:objectType
                                             partialAttachments:nil
                                                        options:nil];
    if (activeSession) {
        [self setActiveSession:activeSession];
    }

    // All sessions that remain in this tab have had their parentage changed so
    // -[sessions] returns only the ones that are to be terminated.
    NSArray *sessionsToTerminate = [self sessions];

    // Swap in the new root split view.
    [self setRoot:newRoot];

    // Terminate sessions that were removed from this tab.
    for (PTYSession *aSession in sessionsToTerminate) {
        [aSession terminate];
    }

    if (!activeSession) {
        NSArray *sessions = [self sessions];
        if ([sessions count]) {
            PTYSession *session = nil;
            if (nearestNeighbor) {
                session = [self sessionForSessionView:nearestNeighbor];
            }
            if (!session) {
                session = sessions.firstObject;
            }
            [self setActiveSession:session];
        }
    }

    const BOOL perPaneTitleBarEnabled = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
    const BOOL haveMultipleSessions = self.sessions.count > 1;
    const BOOL showTitles = (perPaneTitleBarEnabled && haveMultipleSessions);

    for (PTYSession *aSession in [self sessions]) {
        NSNumber *n = [NSNumber numberWithInt:[aSession tmuxPane]];
        if (![preexistingPanes containsObject:n]) {
            // This is a new pane so register it.
            [tmuxController_ registerSession:aSession
                                    withPane:[aSession tmuxPane]
                                    inWindow:self.tmuxWindow];
            [aSession setTmuxController:tmuxController_];
        }
        [aSession.view setShowTitle:showTitles adjustScrollView:NO];
        [aSession.view setShowBottomStatusBar:NO adjustScrollView:NO];
    }
    [self fitSubviewsToRoot];
    [self numberOfSessionsDidChange];
    ++tmuxOriginatedResizeInProgress_;

    if (tmuxController.variableWindowSize) {
        [realParentWindow_ tmuxTabLayoutDidChange:YES tab:self variableWindowSize:tmuxController_.variableWindowSize];
    } else {
        [realParentWindow_ beginTmuxOriginatedResize];
        [realParentWindow_ tmuxTabLayoutDidChange:YES tab:self variableWindowSize:tmuxController_.variableWindowSize];
        [realParentWindow_ endTmuxOriginatedResize];
    }
    --tmuxOriginatedResizeInProgress_;
    [realParentWindow_ setDimmingForSessions];
}

- (void)maximizeAfterApplyingTmuxParseTree:(NSMutableDictionary *)parseTree tmuxController:(TmuxController *)tmuxController {
    DLog(@"Maximizing");
    [self maximize];

    NSMutableDictionary *maximizedParseTree = [self maximizedLayoutForParseTree:parseTree];
    [PTYTab setSizesInTmuxParseTree:maximizedParseTree
                         inTerminal:realParentWindow_
                             zoomed:YES
                            profile:[tmuxController profileForWindow:self.tmuxWindow]];
    DLog(@"PTYTab maximizeAfterApplyingTmuxParseTree using width of %@", parseTree[kLayoutDictMaximumPixelWidthKey]);
    [self resizeViewsInViewHierarchy:root_ forNewLayout:maximizedParseTree];
    DLog(@"After resizing views in maximize, root_.width=%f, flexibleView_.width=%f",
          root_.frame.size.width, flexibleView_.frame.size.width);
    [self fitSubviewsToRoot];
}

// For tmux pre-2.2, the passed-in layout will include the full tree with all sessions when zoomed.
// The approach below is to construct a fake parse tree with a single session whose size
// equals that of the window. See issue 5233.
//
// For tmux 2.2 and later, the passed-in layout will include only the zoomed session. See issue 10249.
- (NSMutableDictionary *)maximizedLayoutForParseTree:(NSDictionary *)parseTree {
    NSMutableDictionary *child = [@{
        kLayoutDictWidthKey: parseTree[kLayoutDictWidthKey],
        kLayoutDictHeightKey: parseTree[kLayoutDictHeightKey],
        kLayoutDictNodeType: @(kLeafLayoutNode),
        kLayoutDictWindowPaneKey: @(self.activeSession.tmuxPane),
        kLayoutDictXOffsetKey: @0,
        kLayoutDictYOffsetKey: @0,
    } mutableCopy];
    return [@{ kLayoutDictChildrenKey: @[ child ],
               kLayoutDictWidthKey: parseTree[kLayoutDictWidthKey],
               kLayoutDictHeightKey: parseTree[kLayoutDictHeightKey],
               kLayoutDictNodeType: @(kVSplitLayoutNode),
               kLayoutDictXOffsetKey: @0,
               kLayoutDictYOffsetKey: @0,
            } mutableCopy];
}

- (void)setTmuxLayout:(NSMutableDictionary *)parseTree
        visibleLayout:(NSMutableDictionary *)visibleParseTree
       tmuxController:(TmuxController *)tmuxController
               zoomed:(NSNumber *)zoomed {
    DLog(@"setTmuxLayout:tmuxController:%@zoomed:%@", tmuxController, zoomed);
    BOOL shouldZoom = isMaximized_;
    if (isMaximized_) {
        DLog(@"Unmaximizing");
        [self unmaximize];
    }
    if (zoomed) {
        shouldZoom = zoomed.boolValue;
    }
    [PTYTab setSizesInTmuxParseTree:parseTree
                         inTerminal:realParentWindow_
                             zoomed:shouldZoom
                            profile:[tmuxController profileForWindow:self.tmuxWindow]];
    DLog(@"Parse tree including sizes:\n%@", parseTree);
    if ([self parseTree:parseTree matchesViewHierarchy:root_]) {
        DLog(@"Parse tree matches the root's view hierarchy.");
        if (tmuxController.variableWindowSize) {
            parseTree = [PTYTab tweakedParseTree:parseTree fillingRootOfSize:[self rootViewSize]];
            DLog(@"Tweaked parse tree:\n%@", parseTree);
        }
        DLog(@"PTYTab setTmuxLayout %@ visible parse tree yielding width of %@px. Will resize views. root_ width before=%f, flexibleView_ width before=%f",
             visibleParseTree ? @"with" : @"without",
             parseTree[kLayoutDictMaximumPixelWidthKey],
             root_.frame.size.width,
             flexibleView_.frame.size.width);
        [self resizeViewsInViewHierarchy:root_ forNewLayout:parseTree];
        [self fitSubviewsToRoot];
    } else {
        DLog(@"Parse tree does not match the root's view hierarchy.");
        if ([[self realParentWindow] inInstantReplay]) {
            [[self realParentWindow] showHideInstantReplay];
        }
        [self replaceViewHierarchyWithParseTree:parseTree
                                 tmuxController:tmuxController];
        shouldZoom = NO;
    }
    [self updateFlexibleViewColors];
    [[root_ window] makeFirstResponder:[[self activeSession] mainResponder]];
    parseTree_ = parseTree;
    visibleParseTree_ = visibleParseTree;

    [self activateJuniorSession];

    if (shouldZoom) {
        [self maximizeAfterApplyingTmuxParseTree:visibleParseTree ?: parseTree
                                  tmuxController:tmuxController];
    }
    [realParentWindow_ tabDidChangeTmuxLayout:self];
}

// Find a session that is not "senior" to a tmux pane getting split by the user and make it
// active.
- (void)activateJuniorSession {
    DLog(@"activateJuniorSession");
    BOOL haveSenior = NO;
    for (PTYSession *aSession in self.sessions) {
        if (aSession.sessionIsSeniorToTmuxSplitPane) {
            haveSenior = YES;
            DLog(@"Found a senior session");
            break;
        }
    }
    if (!haveSenior) {
        // Just a layout change, not a user-driven split.
        DLog(@"No senior session found");
        return;
    }

    // Find a non-senior pane.
    PTYSession *newSession = nil;
    for (PTYSession *aSession in self.sessions) {
        if (!aSession.sessionIsSeniorToTmuxSplitPane) {
            newSession = aSession;
            DLog(@"Found a junior session");
            break;
        }
    }
    if (newSession) {
        DLog(@"Activate junior session");
        [self setActiveSession:newSession];
    }

    // Reset the flag so layout changes in the future because of resizing, dragging a split pane
    // divider, etc. won't change active session.
    for (PTYSession *aSession in self.sessions) {
        aSession.sessionIsSeniorToTmuxSplitPane = NO;
    }
}

- (BOOL)updatedTmuxLayoutRequiresAdjustment {
    if (!flexibleView_) {
        DLog(@"Not too large because there is no flexible view");
        return NO;
    }
    if ([iTermAdvancedSettingsModel disableTmuxWindowResizing]) {
        const CGFloat dx = root_.frame.size.width - flexibleView_.frame.size.width;
        const CGFloat dy = root_.frame.size.height - flexibleView_.frame.size.height;
        const NSSize cellSize = [PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]];
        DLog(@"updatedTmuxLayoutRequiresAdjustment: dx=%@ dy=%@ cellSize=%@ root.frame=%@ flexibleView.frame=%@",
             @(dx), @(dy), NSStringFromSize(cellSize), NSStringFromRect(root_.frame),
             NSStringFromRect(flexibleView_.frame));
        if (dx > 0 || fabs(dx) >= cellSize.width) {
            DLog(@"updatedTmuxLayoutRequiresAdjustment: YES");
            return YES;
        }
        if (dy > 0 || fabs(dy) >= cellSize.height) {
            DLog(@"updatedTmuxLayoutRequiresAdjustment: YES");
            return YES;
        }

        DLog(@"updatedTmuxLayoutRequiresAdjustment: NO");
        return NO;
    }
    DLog(@"updatedTmuxLayoutRequiresAdjustment: Using too-large check only. root %@ has size %@ vs flexible view %@ with size %@",
         root_, NSStringFromSize(root_.frame.size),
         flexibleView_, NSStringFromSize(flexibleView_.frame.size));
    return (root_.frame.size.width > flexibleView_.frame.size.width ||
            root_.frame.size.height > flexibleView_.frame.size.height);
}

- (BOOL)hasMaximizedPane {
    return isMaximized_;
}

- (void)maximize {
    DLog(@"maximize %@", self);
    for (PTYSession *session in [self sessions]) {
        session.savedRootRelativeOrigin = [self rootRelativeOriginOfSession:session];
    }

    assert(!savedArrangement_);
    assert(!idMap_);
    assert(!isMaximized_);

    _orderedGUIDs = [[self orderedSessions] mapWithBlock:^id(PTYSession *session) {
        return session.guid;
    }];

    SessionView* temp = [activeSession_ view];
    savedSize_ = [temp frame].size;

    idMap_ = [[NSMutableDictionary alloc] init];
    savedArrangement_ = [self arrangementConstructingIdMap:YES contents:NO];
    isMaximized_ = YES;

    NSRect oldRootFrame = [root_ frame];
    [root_ removeFromSuperview];

    NSSplitView *newRoot = [[PTYSplitView alloc] init];
    [newRoot setFrame:oldRootFrame];
    [self setRoot:newRoot];

    [temp removeFromSuperview];
    [root_ addSubview:temp];

    [[root_ window] makeFirstResponder:[activeSession_ mainResponder]];
    [realParentWindow_ invalidateRestorableState];

    if ([self isTmuxTab]) {
        DLog(@"Is a tmux tab");
        // Resize the session (VT100Screen, etc.) to the size of the tmux window.
        VT100GridSize gridSize;
        if (visibleParseTree_) {
            gridSize = VT100GridSizeMake([visibleParseTree_[kLayoutDictWidthKey] intValue],
                                         [visibleParseTree_[kLayoutDictHeightKey] intValue]);
        } else {
            gridSize = VT100GridSizeMake([parseTree_[kLayoutDictWidthKey] intValue],
                                         [parseTree_[kLayoutDictHeightKey] intValue]);
        }
        [self resizeSession:self.activeSession toSize:gridSize];

        // Resize the scroll view
        [self fitSubviewsToRoot];

        // Resize the SessionView
        [self resizeMaximizedTmuxSessionView:self.activeSession.view toGridSize:gridSize];
    }
}

- (void)resizeMaximizedTmuxSessionView:(SessionView *)sessionView toGridSize:(VT100GridSize)gridSize {
    DLog(@"resize view %@ to grid size %@", sessionView, VT100GridSizeDescription(gridSize));
    const BOOL perPanelTitleBarsEnabled = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
    const BOOL showTitles = perPanelTitleBarsEnabled;
    NSSize size = [PTYTab _sessionSizeWithCellSize:[PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]]
                                        dimensions:NSMakeSize(gridSize.width, gridSize.height)
                                        showTitles:showTitles
                               showBottomStatusBar:NO
                                        rightExtra:sessionView.desiredRightExtra
                                        inTerminal:self.realParentWindow];
    NSRect frame = {
        .origin = sessionView.frame.origin,
        .size = size
    };
    sessionView.frame = frame;
}

- (void)unmaximize {
    assert(savedArrangement_);
    assert(idMap_);
    assert(isMaximized_);

    // Pull the formerly maximized sessionview out of the old root.
    assert([[root_ subviews] count] == 1);
    SessionView* formerlyMaximizedSessionView = [[root_ subviews] objectAtIndex:0];

    // I'm not convinced this is necessary but I'm afraid to remove it. idMap_ should hold refs to all SessionViews that matter.
    [formerlyMaximizedSessionView removeFromSuperview];
    [formerlyMaximizedSessionView setFrameSize:savedSize_];

    // Build a tree with splitters and SessionViews/PTYSessions from idMap.
    NSSplitView *newRoot = [PTYTab _recursiveRestoreSplitters:[savedArrangement_ objectForKey:TAB_ARRANGEMENT_ROOT]
                                                    fromIdMap:idMap_
                                                   sessionMap:nil
                                              revivedSessions:nil];
    [PTYTab _recursiveSetDelegateIn:newRoot to:self];

    // Create a tab.
    [self setRoot:newRoot];

    idMap_ = nil;
    savedArrangement_ = nil;
    isMaximized_ = NO;

    [[root_ window] makeFirstResponder:[activeSession_ mainResponder]];
    [realParentWindow_ invalidateRestorableState];

    for (SessionView *sessionView in self.sessionViews) {
        // I don't know why, but this doesn't get called automatically and so focus follows mouse
        // breaks. Issue 4810.
        [sessionView updateTrackingAreas];
    }
}

- (iTermPromptOnCloseReason *)promptOnCloseReason {
    iTermPromptOnCloseReason *reason = [iTermPromptOnCloseReason noReason];
    for (PTYSession *aSession in [self sessions]) {
        [reason addReason:[aSession promptOnCloseReason]];
    }
    return reason;
}

- (BOOL)canMoveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally {
    SessionView *view = [[self activeSession] view];
    PTYSplitView *split = (PTYSplitView *)[view superview];
    if (horizontally) {
        if ([split isVertical]) {
            return [self canMoveView:view inSplit:split horizontally:YES by:direction];
        } else {
            return [self canMoveView:split inSplit:[split superview] horizontally:YES by:direction];
        }
    } else {
        if ([split isVertical]) {
            return [self canMoveView:split inSplit:[split superview] horizontally:NO by:direction];
        } else {
            return [self canMoveView:view inSplit:split horizontally:NO by:direction];
        }
    }
}

- (void)moveCurrentSessionDividerBy:(int)direction horizontally:(BOOL)horizontally {
    SessionView *view = [[self activeSession] view];
    PTYSplitView *split = (PTYSplitView *)[view superview];
    // Either adjust the superview of the active session's view or the
    // superview of the superview of the current session's view. If you're
    // trying to resize horizontally and the active view is inside a split view
    // with horizontal dividers, for example, the split view that needs to
    // change is actually the view's grandparent.
    if (horizontally) {
        if ([split isVertical]) {
            [self moveView:view inSplit:split horizontally:YES by:direction];
        } else {
            [self moveView:split inSplit:[split superview] horizontally:YES by:direction];
        }
    } else {
        if ([split isVertical]) {
            [self moveView:split inSplit:[split superview] horizontally:NO by:direction];
        } else {
            [self moveView:view inSplit:split horizontally:NO by:direction];
        }
    }
}

// This computes what to do and returns a block that actually does it. But if
// it's not allowed, then it returns null. This combines the "can move" with
// the "move" into a single function.
- (void (^)(void))blockToMoveView:(NSView *)view
                          inSplit:(NSView *)possibleSplit
                     horizontally:(BOOL)horizontally
                               by:(int)direction {
    if (![possibleSplit isKindOfClass:[PTYSplitView class]] ||
        possibleSplit.subviews.count == 1) {
        return NULL;
    }

    // Compute the index of the passed-in view and divider that are affected.
    PTYSplitView *split = (PTYSplitView *)possibleSplit;
    assert(([split isVertical] && horizontally) ||
           (![split isVertical] && !horizontally));
    NSUInteger subviewIndex = [[split subviews] indexOfObject:view];
    if (subviewIndex == NSNotFound) {
        return NULL;
    }
    NSArray *subviews = [split subviews];
    const NSInteger numSubviews = [subviews count];
    NSInteger splitterIndex;
    if (subviewIndex + 1 == numSubviews) {
        splitterIndex = numSubviews - 2;
    } else {
        splitterIndex = subviewIndex;
    }

    const CGFloat step = [self stepForMovementOfDividerIndex:splitterIndex ofSplitView:split];

    // Compute the new frames for the subview before and after the divider.
    // No other subviews are affected.
    NSSize movement = NSMakeSize(horizontally ? direction * step : 0,
                                 horizontally ? 0 : direction * step);

    NSView *before = subviews[splitterIndex];
    NSRect beforeFrame = before.frame;
    beforeFrame.size.width += movement.width;
    beforeFrame.size.height += movement.height;

    // See if any constraint would be violated.
    const CGFloat proposed = horizontally ? NSMaxX(beforeFrame) : NSMaxY(beforeFrame);

    if (direction > 0) {
        const CGFloat proposedMinusDivider = proposed - split.dividerThickness;
        const CGFloat constraint = [self splitView:split
                            constrainMaxCoordinate:proposedMinusDivider
                                       ofSubviewAt:splitterIndex];
        if (constraint < proposed) {
            return NULL;
        }

    } else {
        const CGFloat constraint = [self splitView:split
                            constrainMinCoordinate:proposed
                                       ofSubviewAt:splitterIndex];
        if (constraint > proposed) {
            return NULL;
        }
    }

    // It would be ok to move the divider. Return a block that updates views' frames.
    void (^block)(void) = ^void() {
        [self splitView:split draggingWillBeginOfSplit:splitterIndex];
        [split setPosition:proposed ofDividerAtIndex:splitterIndex];
        [self splitView:split draggingDidEndOfSplit:splitterIndex pixels:movement];
        [split adjustSubviews];
        [split setNeedsDisplay:YES];
    };
    return [block copy];
}

- (void)moveView:(NSView *)view
         inSplit:(NSView *)possibleSplit
    horizontally:(BOOL)horizontally
              by:(int)direction {
    void (^block)(void) = [self blockToMoveView:view
                                        inSplit:possibleSplit
                                   horizontally:horizontally
                                             by:direction];
    if (block) {
        block();
    }
}

- (BOOL)canMoveView:(NSView *)view
            inSplit:(NSView *)possibleSplit
       horizontally:(BOOL)horizontally
                 by:(int)direction {
    void (^block)(void) = [self blockToMoveView:view
                                        inSplit:possibleSplit
                                   horizontally:horizontally
                                             by:direction];
    return block != nil;
}

- (void)swapSession:(PTYSession *)existing withBuriedSession:(PTYSession *)buried {
    DLog(@"swapSession:%@ withBuriedSession:%@", existing, buried);
    if (((PTYTab *)existing.delegate)->lockedSession_) {
        DLog(@"Existing or both is locked");
        return;
    }
    if (existing.isTmuxClient || buried.isTmuxClient) {
        DLog(@"tmux");
        return;
    }
    PTYSplitView *splitView = (PTYSplitView *)existing.view.superview;
    const NSUInteger index = [splitView.subviews indexOfObject:existing.view];
    buried.view.frame = existing.view.frame;
    [existing.view removeFromSuperview];
    [splitView insertSubview:buried.view atIndex:index];
    buried.delegate = self;
    [self setActiveSession:buried];
    [splitView adjustSubviews];
    [self updatePaneTitles];
    for (PTYSession *session in self.sessions) {
        [self fitSessionToCurrentViewSize:session];
    }
    [self.viewToSessionMap setObject:buried forKey:buried.view];
    [buried didMoveSession];
    [self updateSessionOrdinals];

    [[iTermBuriedSessions sharedInstance] swapSession:existing withBuriedSession:buried];
}

- (void)swapSession:(PTYSession *)session1 withSession:(PTYSession *)session2 {
    DLog(@"swapSession:%@ withSession:%@", session1, session2);
    assert(session1.delegate == self);
    if (isMaximized_) {
        [self unmaximize];
    }
    if (session2.delegate.hasMaximizedPane) {
        [session2.delegate unmaximize];
    }

    if (((PTYTab *)session1.delegate)->lockedSession_ || ((PTYTab *)session2.delegate)->lockedSession_) {
        DLog(@"One or both is locked");
        return;
    }
    if (session1.isTmuxClient &&
        session2.isTmuxClient &&
        session1.tmuxController == session2.tmuxController) {
        DLog(@"Use tmux to swap");
        [session1.tmuxController swapPane:session1.tmuxPane withPane:session2.tmuxPane];
        return;
    }
    if ([session1 isTmuxClient] ||
        [session2 isTmuxClient] ||
        [session1 isTmuxGateway] ||
        [session2 isTmuxGateway]) {
        return;
    }

    DLog(@"Before swap, %@ has superview %@ and %@ has superview %@",
         session1.view, session1.view.superview,
         session2.view, session2.view.superview);

    PTYTab *session1Tab = (PTYTab *)session1.delegate;
    PTYTab *session2Tab = (PTYTab *)session2.delegate;

    PTYSplitView *session1Superview = (PTYSplitView *)session1.view.superview;
    NSUInteger session1Index = [[session1Superview subviews] indexOfObject:session1.view];
    PTYSplitView *session2Superview = (PTYSplitView *)session2.view.superview;
    NSUInteger session2Index = [[session2Superview subviews] indexOfObject:session2.view];

    session1Superview.delegate = nil;
    session2Superview.delegate = nil;
    if (session1Superview == session2Superview) {
        [session1Superview swapSubview:session1.view withSubview:session2.view];
    } else {
        [session1.view removeFromSuperview];
        [session2.view removeFromSuperview];
        NSRect temp = session1.view.frame;
        session1.view.frame = session2.view.frame;
        session2.view.frame = temp;
        [session1Superview insertSubview:session2.view atIndex:session1Index];
        [session2Superview insertSubview:session1.view atIndex:session2Index];
    }
    session1Superview.delegate = session1Tab;
    session2Superview.delegate = session2Tab;

    session1.delegate = session2Tab;
    session2.delegate = session1Tab;

    [session1Tab setActiveSession:session2];
    [session2Tab setActiveSession:session1];

    [session1Superview adjustSubviews];
    [session2Superview adjustSubviews];

    [session1Tab updatePaneTitles];
    [session2Tab updatePaneTitles];

    for (PTYTab *aTab in @[ session1Tab, session2Tab ]) {
          for (PTYSession *aSession in aTab.sessions) {
              [aTab fitSessionToCurrentViewSize:aSession];
          }
    }

    [session1Tab fitSessionToCurrentViewSize:session1];
    [session2Tab fitSessionToCurrentViewSize:session2];

    DLog(@"After swap, %@ has superview %@ and %@ has superview %@",
         session1.view, session1.view.superview,
         session2.view, session2.view.superview);

    // Update the sessions maps.
    [session1Tab.viewToSessionMap removeObjectForKey:session1.view];
    [session2Tab.viewToSessionMap removeObjectForKey:session2.view];

    [session1Tab.viewToSessionMap setObject:session2 forKey:session2.view];
    [session2Tab.viewToSessionMap setObject:session1 forKey:session1.view];

    [session1 didMoveSession];
    [session2 didMoveSession];

    [session1Tab updateSessionOrdinals];
    [session2Tab updateSessionOrdinals];
}

- (void)_recursivePopulateSplitTreeNode:(ITMSplitTreeNode *)node
                                   from:(NSSplitView *)splitview {
    node.vertical = splitview.isVertical;

    for (__kindof NSView *view in splitview.subviews) {
        if ([view isKindOfClass:[NSSplitView class]]) {
            ITMSplitTreeNode *child = [[ITMSplitTreeNode alloc] init];
            ITMSplitTreeNode_SplitTreeLink *link = [[ITMSplitTreeNode_SplitTreeLink alloc] init];
            link.node = child;
            [node.linksArray addObject:link];
            [self _recursivePopulateSplitTreeNode:child from:view];
        } else if ([view isKindOfClass:[SessionView class]]) {
            ITMSplitTreeNode_SplitTreeLink *link = [[ITMSplitTreeNode_SplitTreeLink alloc] init];
            PTYSession *session = [self sessionForSessionView:view];
            link.session.uniqueIdentifier = session.guid;
            link.session.frame.origin.x = view.frame.origin.x;
            link.session.frame.origin.y = view.frame.origin.y;
            link.session.frame.size.width = view.frame.size.width;
            link.session.frame.size.height = view.frame.size.height;

            link.session.gridSize.width = session.screen.width;
            link.session.gridSize.height = session.screen.height;

            link.session.title = session.name;
            
            [node.linksArray addObject:link];
        }
    }
}

- (ITMSplitTreeNode *)rootSplitTreeNode {
    ITMSplitTreeNode *root = [[ITMSplitTreeNode alloc] init];
    [self _recursivePopulateSplitTreeNode:root from:root_];
    return root;
}

- (void)updateTabTitle {
    NSString *sessionName = [self.activeSession.variablesScope valueForVariableName:iTermVariableKeySessionPresentationName];
    [self updateTabTitleForCurrentSessionName:sessionName];
}

- (iTermVariableScope<iTermTabScope> *)variablesScope {
    if (!_variablesScope) {
        _variablesScope = [iTermVariableScope newTabScopeWithVariables:_variables];
    }
    return _variablesScope;
}

- (id)valueForVariable:(NSString *)name {
    return [self.variablesScope valueForVariableName:name];
}

- (NSString *)tmuxPerTabSetting {
    NSString *format = self.variablesScope.tabTitleOverrideFormat;
    if (format == nil) {
        return nil;
    }
    // key=value&key=value&...
    // Semicolon is reserved. Don't use it.
    return [NSString stringWithFormat:@"%@=%@", @"t", [format base64EncodedWithEncoding:NSUTF8StringEncoding]];
}

- (void)setPerTabSettings:(NSString *)setting {
    DLog(@"SET per-tab settings %@ for %@", setting, self);
    NSArray<NSString *> *parts = [setting componentsSeparatedByString:@"&"];
    for (NSString *part in parts) {
        iTermTuple<NSString *, NSString *> *kvp = [part it_stringBySplittingOnFirstSubstring:@"="];
        if (!kvp) {
            continue;
        }
        if ([kvp.firstObject isEqualToString:@"t"]) {
            // t=[base64-encoded title override format]
            NSString *titleOverride = [kvp.secondObject stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
            if (titleOverride.length > 0) {
                if (![NSObject object:titleOverride isEqualToObject:self.variablesScope.tabTitleOverrideFormat]) {
                    self.variablesScope.tabTitleOverrideFormat = titleOverride;
                }
            }
        }
    }
}

- (void)setTitleOverride:(NSString *)titleOverride {
    NSString *const sanitized = titleOverride.length ? titleOverride : nil;
    self.variablesScope.tabTitleOverrideFormat = sanitized;
    if (self.tmuxTab) {
        if (titleOverride) {
            [self.tmuxController setWindowTitleOverride:titleOverride
                                                 window:self.tmuxWindow];
        }
    }
}

- (void)updateTitleOverrideFromFormatVariable {
    [self updateTabTitle];
    for (PTYSession *session in self.sessions) {
        if ([session checkForCyclesInSwiftyStrings]) {
            _tabTitleOverrideSwiftyString.swiftyString = @"[Cycle detected]";
        }
    }
}

- (NSString *)titleOverride {
    return _tabTitleOverrideSwiftyString.swiftyString;
}

#pragma mark NSSplitView delegate methods

- (void)splitViewDidChangeSubviews:(PTYSplitView *)splitView {
    for (PTYSession *session in self.sessions) {
        // Pane number may have changed for all sessions by adding or removing a split pane anywhere.
        [session didMoveSession];
    }
}

- (void)splitView:(PTYSplitView *)splitView draggingWillBeginOfSplit:(int)splitterIndex {
    DLog(@"%@: draggingWillBeginOfSplit:%@", self, @(splitterIndex));
    _numberOfSplitViewDragsInProgress++;
    DLog(@"%@ split drags in progress", @(_numberOfSplitViewDragsInProgress));
    if (![self isTmuxTab]) {
        // Don't care for non-tmux tabs.
        return;
    }
    // Dragging looks a lot better if we turn on resizing subviews temporarily.
    _isDraggingSplitInTmuxTab = YES;
    [self updateUseMetal];
}

- (NSArray<PTYSession *> *)sessionsUnderView:(NSView *)parent {
    if ([parent isKindOfClass:[SessionView class]]) {
        SessionView *sessionView = (SessionView *)parent;
        return @[ [self sessionForSessionView:sessionView] ];
    }
    if ([parent isKindOfClass:[PTYSplitView class]]) {
        PTYSplitView *splitView = (PTYSplitView *)parent;
        return [splitView.subviews flatMapWithBlock:^NSArray *(__kindof NSView *child) {
            return [self sessionsUnderView:child];
        }];
    }
    // You shouldn't get here.
    return @[];
}

- (NSArray<PTYSession *> *)sessionsAdjacentToSplitter:(int)splitterIndex
                                                   of:(PTYSplitView *)splitView {
    if (splitterIndex < 0 || splitterIndex >= splitView.subviews.count) {
        return @[];
    }
    NSArray<PTYSession *> *before = [self sessionsUnderView:splitView.subviews[splitterIndex]];
    if (splitterIndex + 1 >= splitView.subviews.count) {
        return before;
    }
    NSArray<PTYSession *> *after = [self sessionsUnderView:splitView.subviews[splitterIndex + 1]];
    return [before arrayByAddingObjectsFromArray:after];
}

- (void)splitView:(PTYSplitView *)splitView
  draggingDidEndOfSplit:(int)splitterIndex
           pixels:(NSSize)pxMoved {
    DLog(@"%@: draggingDidEndOfSplit:%@", self, @(splitterIndex));
    _numberOfSplitViewDragsInProgress--;
    DLog(@"%@ split drags in progress", @(_numberOfSplitViewDragsInProgress));
    for (PTYSession *session in [self sessionsAdjacentToSplitter:splitterIndex of:splitView]) {
        DLog(@"session did resize: %@", session);
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionDidResizeNotification object:session];
    }
    if (![self isTmuxTab]) {
        // Don't care for non-tmux tabs.
        return;
    }
    _isDraggingSplitInTmuxTab = NO;
    [self updateUseMetal];
    // Find a session view adjacent to the moved splitter.
    NSArray *subviews = [splitView subviews];
    NSView *theView = [subviews uncheckedObjectAtIndex:splitterIndex];  // the view right of or below the dragged splitter.
    if (theView) {
        while ([theView isKindOfClass:[NSSplitView class]]) {
            NSSplitView *subSplitView = (NSSplitView *)theView;
            theView = [[subSplitView subviews] objectAtIndex:0];
        }
        SessionView *sessionView = (SessionView *)theView;
        PTYSession *session = [self sessionForSessionView:sessionView];
        
        // Determine the number of characters moved
        NSSize cellSize = [PTYTab cellSizeForBookmark:[self.tmuxController profileForWindow:self.tmuxWindow]];
        int amount;
        if (pxMoved.width) {
            amount = pxMoved.width / cellSize.width;
        } else {
            amount = pxMoved.height / cellSize.height;
        }
        
        // Ask the tmux server to perform the move and we'll update our layout when
        // it finishes.
        if (amount != 0) {
            [tmuxController_ windowPane:[session tmuxPane]
                              resizedBy:amount
                           horizontally:[splitView isVertical]];
        }
    }
    [self updateUseMetal];
}

// Prevent any session from becoming smaller than its minimum size because of
// a divider's movement.
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex {
    if (tmuxOriginatedResizeInProgress_) {
        // Whoever's doing the resizing is responsible for making everything
        // perfect.
        return proposedMin;
    }
    PtyLog(@"PTYTab constrainMin:%f divider:%d", (float)proposedMin, (int)dividerIndex);
    CGFloat dim;
    NSSize minSize = [self _minSizeOfView:[[splitView subviews] objectAtIndex:dividerIndex]
                           respectPinning:YES];
    if ([splitView isVertical]) {
        dim = minSize.width;
    } else {
        dim = minSize.height;
    }
    return [self _positionOfDivider:dividerIndex-1 inSplitView:splitView] + dim;
}

// Prevent any session from becoming smaller than its minimum size because of
// a divider's movement.
- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposedMax
               ofSubviewAt:(NSInteger)dividerIndex {
    if (tmuxOriginatedResizeInProgress_) {
        // Whoever's doing the resizing is responsible for making everything
        // perfect.
        return proposedMax;
    }
    PtyLog(@"PTYTab constrainMax:%f divider:%d", (float)proposedMax, (int)dividerIndex);
    CGFloat dim;
    NSSize minSize = [self _minSizeOfView:[[splitView subviews] objectAtIndex:dividerIndex+1]
                           respectPinning:YES];
    if ([splitView isVertical]) {
        dim = minSize.width;
    } else {
        dim = minSize.height;
    }
    return [self _positionOfDivider:dividerIndex+1 inSplitView:splitView] - dim - [splitView dividerThickness];
}

- (NSSet*)_ancestorsOfLockedSession {
    NSMutableSet* result = [NSMutableSet setWithCapacity:1];
    id current = [[lockedSession_ view  ]superview];
    while (current != nil) {
        [result addObject:current];
        if (current == root_) {
            break;
        }
        current = [current superview];
    }
    return result;
}

// min of unlocked session x = minSize(x)
// max of unlocked session x = inf
//
// min of locked session x = sessionSize of x
// max of locked session x = sessionSize of x
//
// min of splitter with locked session s[x] = wtg: sum(minSize(i) for i != x) + sessionSize(x)
//                                            atg: sessionSize(x)
// max of splitter with locked session s[x] = wtg: sum(maxSize(i))
//                                            atg: sessionSize(x)
//
// +--------+
// |   |    |
// |   +----+
// |   |xxxx|
// +---+----+
//
// ** this is a generalizable version of all the above: **
// min of splitter with locked grandchild s[x1][x2] = wtg: sum(minSize(i) for all i)
//                                                    atg: max(minSize(i) for all i)
// max of splitter with locked grandchild s[x1][x2] = wtg: sum(maxSize(i))
//                                                    atg: min(maxSize(i) for all i)


- (void)_recursiveLockedSize:(NSView *)theSubview
                   ancestors:(NSSet<NSView *> *)ancestors
                     minSize:(NSSize *)minSize
                     maxSize:(NSSize *)maxSizeOut
              respectPinning:(BOOL)respectPinning {
    if ([theSubview isKindOfClass:[SessionView class]]) {
        // This must be the locked session. Its min and max size are exactly its ideal size.
        assert(theSubview == [lockedSession_ view]);
        NSSize size = [self _sessionSize:(SessionView*)theSubview];
        *minSize = *maxSizeOut = size;
    } else {
        // This is some ancestor of the locked session.
        NSSplitView* splitView = (NSSplitView*)theSubview;
        *minSize = NSZeroSize;
        BOOL isVertical = [splitView isVertical];
        SetAgainstGrainDim(isVertical, maxSizeOut, INFINITY);
        SetWithGrainDim(isVertical, maxSizeOut, 0);
        BOOL first = YES;
        for (NSView* aView in [splitView subviews]) {
            NSSize viewMin;
            NSSize viewMax;
            if (aView == [lockedSession_ view] || [ancestors containsObject:aView]) {
                [self _recursiveLockedSize:aView
                                 ancestors:ancestors
                                   minSize:&viewMin
                                   maxSize:&viewMax
                            respectPinning:respectPinning];
            } else {
                viewMin = [self _minSizeOfView:aView respectPinning:respectPinning];
                viewMax.width = INFINITY;
                viewMax.height = INFINITY;
            }
            double thickness;
            if (first) {
                first = NO;
                thickness = 0;
            } else {
                thickness = [splitView dividerThickness];
            }
            // minSize.wtg := sum(viewMin)
            SetWithGrainDim(isVertical,
                            minSize,
                            WithGrainDim(isVertical, *minSize) + WithGrainDim(isVertical, viewMin) + thickness);
            // minSize.atg := MAX(viewMin)
            SetAgainstGrainDim(isVertical,
                               minSize,
                               MAX(AgainstGrainDim(isVertical, *minSize), AgainstGrainDim(isVertical, viewMin)));
            // maxSizeOut.wtg := sum(viewMax)
            SetWithGrainDim(isVertical,
                            maxSizeOut,
                            WithGrainDim(isVertical, *maxSizeOut) + WithGrainDim(isVertical, viewMax) + thickness);
            // maxSizeOut.atg := MIN(viewMax)
            SetAgainstGrainDim(isVertical,
                               maxSizeOut,
                               MIN(AgainstGrainDim(isVertical, *maxSizeOut), AgainstGrainDim(isVertical, viewMax)));
        }
    }
}

- (void)_redistributeQuantizationError:(const double)targetSize
                     currentSumOfSizes:(double)currentSumOfSizes
                                 sizes:(NSMutableArray *)sizes
                              minSizes:(NSArray *)minSizes
                              maxSizes:(NSArray *)maxSizes {
    ITCriticalError(sizes.count == minSizes.count && sizes.count == maxSizes.count,
                    @"Mismatch in sizes array. sizes=%@ minSizes=%@ maxSizes=%@ self=%@ root=%@",
                    sizes, minSizes, maxSizes, self, [root_ iterm_recursiveDescription]);
    ITCriticalError(sizes.count > 0,
                    @"Empty sizes array passed to redistributeQuantizationError");
    assert(sizes.count > 0);
    assert(minSizes.count > 0);
    assert(maxSizes.count > 0);

    // In case quantization caused some rounding error, randomly adjust subviews by plus or minus
    // one pixel.
    int error = currentSumOfSizes - targetSize;
    int change;
    if (error > 0) {
        change = -1;
    } else {
        change = 1;
    }
    // First redistribute error while respecting min and max constraints until that is no longer
    // possible.
    while (error != 0) {
        BOOL anyChange = NO;
        for (int i = 0; i < [sizes count] && error != 0; ++i) {
            ITCriticalError(sizes.count > 0, @"Size of sizes array changed, is now %@", @(sizes.count));
            ITCriticalError(sizes.count == minSizes.count && sizes.count == maxSizes.count,
                            @"Mismatch in sizes array materialized from thin air. i=%@ sizes=%@ minSizes=%@ maxSizes=%@ self=%@",
                            @(i), sizes, minSizes, maxSizes, self);
            const double size = [[sizes objectAtIndex:i] doubleValue];
            const double theMin = [[minSizes objectAtIndex:i] doubleValue];
            const double theMax = [[maxSizes objectAtIndex:i] doubleValue];
            const double proposedSize = size + change;
            if (proposedSize >= theMin && proposedSize <= theMax) {
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:proposedSize]];
                error += change;
                anyChange = YES;
            }
        }
        if (!anyChange) {
            break;
        }
    }

    // As long as there is still some error left, use 1 for min and disregard max.
    while (error != 0) {
        BOOL anyChange = NO;
        for (int i = 0; i < [sizes count] && error != 0; ++i) {
            const double size = [[sizes objectAtIndex:i] doubleValue];
            if (size + change > 0) {
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size + change]];
                error += change;
                anyChange = YES;
            }
        }
        if (!anyChange) {
            XLog(@"Failed to redistribute quantization error. Change=%d, sizes=%@.", change, sizes);
            return;
        }
    }
}

// Called after a splitter has been resized. This adjusts session sizes appropriately,
// with special attention paid to the "locked" session, which never resizes.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    if (![self resizeSubviewsOfSplitView:splitView oldSize:oldSize respectPinning:YES]) {
        [self resizeSubviewsOfSplitView:splitView oldSize:oldSize respectPinning:NO];
    }
}

- (BOOL)resizeSubviewsOfSplitView:(NSSplitView *)splitView
                          oldSize:(NSSize)oldSize
                   respectPinning:(BOOL)respectPinning {
    // While we'd prefer not to do this if tmuxOriginatedResizeInProgress_>0,
    // it's necessary to avoid a warning. It should be harmless because after
    // setting a splitter's size we go back and set each child's size in
    // -[_recursiveSetSizesInTmuxParseTree:showTitles:bookmark:inTerminal:].
    if ([[splitView subviews] count] == 0) {
        // nothing to do!
        return YES;
    }
    if ([splitView frame].size.width == 0) {
        XLog(@"Warning: splitView:resizeSubviewsWithOldSize: resized to 0 width");
        return YES;
    }
    PtyLog(@"splitView:resizeSubviewsWithOldSize for %p", splitView);
    BOOL isVertical = [splitView isVertical];
    NSSet* ancestors = [self _ancestorsOfLockedSession];
    NSSize minLockedSize = NSZeroSize;
    NSSize maxLockedSize = NSZeroSize;
    const double n = [[splitView subviews] count];

    // Find the min, max, and ideal proportionate size for each subview.
    NSMutableArray* sizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];
    NSMutableArray* minSizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];
    NSMutableArray* maxSizes = [NSMutableArray arrayWithCapacity:[[splitView subviews] count]];

    // This is the sum of the with-the-grain sizes excluding dividers that we need to attain.
    const double targetSize = WithGrainDim(isVertical, [splitView frame].size) - ([splitView dividerThickness] * (n - 1));
    PtyLog(@"splitView:resizeSubviewsWithOldSize - target size is %lf", targetSize);

    // Add up the existing subview sizes to come up with the previous total size excluding dividers.
    double oldTotalSize = 0;
    for (NSView* aSubview in [splitView subviews]) {
        oldTotalSize += WithGrainDim(isVertical, [aSubview frame].size);
    }
    double sizeChangeCoeff = 0;
    BOOL ignoreConstraints = NO;
    if (oldTotalSize == 0) {
        // Nothing to go by. Just set all subviews to the same size.
        PtyLog(@"splitView:resizeSubviewsWithOldSize: old size was 0");
        ignoreConstraints = YES;
    } else {
        sizeChangeCoeff = targetSize / oldTotalSize;
        PtyLog(@"splitView:resizeSubviewsWithOldSize. initial coeff=%lf", sizeChangeCoeff);
    }
    if (!ignoreConstraints) {
        // Set the min and max size for each subview. Assign an initial guess to sizes.
        double currentSumOfSizes = 0;
        double currentSumOfMinClamped = 0;
        double currentSumOfMaxClamped = 0;
        for (NSView* aSubview in [splitView subviews]) {
            double theMinSize;
            double theMaxSize;
            if (aSubview == [lockedSession_ view] || [ancestors containsObject:aSubview]) {
                [self _recursiveLockedSize:aSubview
                                 ancestors:ancestors
                                   minSize:&minLockedSize
                                   maxSize:&maxLockedSize
                            respectPinning:respectPinning];
                theMinSize = WithGrainDim(isVertical, minLockedSize);
                theMaxSize = WithGrainDim(isVertical, maxLockedSize);
                PtyLog(@"splitView:resizeSubviewsWithOldSize - this subview is LOCKED");
            } else {
                theMaxSize = targetSize;
                if ([aSubview isKindOfClass:[NSSplitView class]]) {
                    theMinSize = WithGrainDim(isVertical, [self _recursiveMinSize:(NSSplitView*)aSubview
                                                                   respectPinning:respectPinning]);
                } else {
                    SessionView *sessionView = (SessionView *)aSubview;
                    theMinSize = WithGrainDim(isVertical, [self _minSessionSize:sessionView
                                                                 respectPinning:respectPinning]);
                    if (respectPinning && splitView.vertical && sessionView.preferredWidth != nil) {
                        theMaxSize = sessionView.preferredWidth.doubleValue;
                    }
                }
                PtyLog(@"splitView:resizeSubviewsWithOldSize - this subview is unlocked");
            }
            PtyLog(@"splitView:resizeSubviewsWithOldSize - range of %p is [%lf,%lf]", aSubview, theMinSize, theMaxSize);
            [minSizes addObject:[NSNumber numberWithDouble:theMinSize]];
            [maxSizes addObject:[NSNumber numberWithDouble:theMaxSize]];
            const double initialGuess = sizeChangeCoeff * WithGrainDim(isVertical, [aSubview frame].size);
            const double size = lround(MIN(MAX(initialGuess, theMinSize), theMaxSize));
            PtyLog(@"splitView:resizeSubviewsWithOldSize - initial guess of %p is %lf (based on size of %lf), clamped is %lf", aSubview, initialGuess, (double)WithGrainDim(isVertical, [aSubview frame].size), size);
            [sizes addObject:[NSNumber numberWithDouble:size]];
            currentSumOfSizes += size;
            if (size == theMinSize) {
                currentSumOfMinClamped += size;
            }
            if (size == theMaxSize) {
                currentSumOfMaxClamped += size;
            }
        }

        // Refine sizes while we're more than half a pixel away from the target size.
        const double kEpsilon = 0.5;
        while (fabs(currentSumOfSizes - targetSize) > kEpsilon) {
            PtyLog(@"splitView:resizeSubviewsWithOldSize - refining. currentSumOfSizes=%lf vs target %lf", currentSumOfSizes, targetSize);
            double currentSumOfUnclamped;
            double desiredNewSizeForUnclamped;
            if (currentSumOfSizes < targetSize) {
                currentSumOfUnclamped = currentSumOfSizes - currentSumOfMaxClamped;
                desiredNewSizeForUnclamped = targetSize - currentSumOfMaxClamped;
            } else {
                currentSumOfUnclamped = currentSumOfSizes - currentSumOfMinClamped;
                desiredNewSizeForUnclamped = targetSize - currentSumOfMinClamped;
            }
            if (currentSumOfUnclamped < kEpsilon) {
                // Not enough unclamped space to make any change.
                if (respectPinning) {
                    return NO;
                }
                ignoreConstraints = YES;
                break;
            }
            // Set a coefficient that will be applied only to subviews that aren't clamped. If we're
            // able to resize all currently unclamped subviews by this coefficient then we should
            // hit exactly the target size.
            const double coeff = desiredNewSizeForUnclamped / currentSumOfUnclamped;
            PtyLog(@"splitView:resizeSubviewsWithOldSize - coeff %lf to bring current %lf unclamped size to %lf", coeff, currentSumOfUnclamped, desiredNewSizeForUnclamped);

            // Try to resize every subview by the coefficient. Clamped subviews won't be able to
            // change.
            currentSumOfSizes = 0;
            currentSumOfMinClamped = 0;
            currentSumOfMaxClamped = 0;
            BOOL anyChanges = NO;
            for (int i = 0; i < [sizes count]; ++i) {
                const double preferredSize = [[sizes objectAtIndex:i] doubleValue] * coeff;
                const double theMinSize = [[minSizes objectAtIndex:i] doubleValue];
                const double theMaxSize = [[maxSizes objectAtIndex:i] doubleValue];
                const double size = lround(MIN(MAX(preferredSize, theMinSize), theMaxSize));
                if (!anyChanges && size != [[sizes objectAtIndex:i] doubleValue]) {
                    anyChanges = YES;
                }
                PtyLog(@"splitView:resizeSubviewsWithOldSize - change %lf to %lf (would be %lf unclamped)", [[sizes objectAtIndex:i] doubleValue], size, preferredSize);
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size]];

                currentSumOfSizes += size;
                if (size == theMinSize) {
                    currentSumOfMinClamped += size;
                }
                if (size == theMaxSize) {
                    currentSumOfMaxClamped += size;
                }
            }
            if (!anyChanges) {
                PtyLog(@"splitView:resizeSubviewsWithOldSize - nothing changed in this round");
                if (fabs(currentSumOfSizes - targetSize) > [[splitView subviews] count]) {
                    XLog(@"No changes! Ignoring constraints!");
                    if (respectPinning) {
                        return NO;
                    }
                    // I'm not sure this will ever happen, but just in case quantization prevents us
                    // from converging give up and ignore constraints.
                    ignoreConstraints = YES;
                } else {
                    PtyLog(@"splitView:resizeSubviewsWithOldSize - redistribute quantization error");
                    SetPinnedDebugLogMessage(@"Current split view for redistribution", @"oldTotalSize=%@ ignoreConstraints=%@ splitView.recursiveDescription=%@", @(oldTotalSize), @(ignoreConstraints), [splitView iterm_recursiveDescription]);
                    [self _redistributeQuantizationError:targetSize
                                       currentSumOfSizes:currentSumOfSizes
                                                   sizes:sizes
                                                minSizes:minSizes
                                                maxSizes:maxSizes];
                    SetPinnedDebugLogMessage(@"Current split view for redistribution", nil);
                }
                break;
            }
        }
    }

    if (ignoreConstraints) {
        PtyLog(@"splitView:resizeSubviewsWithOldSize - ignoring constraints");
        // Not all the constraints could be satisfied. Set every subview to its ideal size and hope
        // for the best.
        double currentSumOfSizes = 0;
        if (sizeChangeCoeff == 0) {
            // Original size was 0 so make all subviews equal.
            const int numSubviews = [[splitView subviews] count];
            for (int subviewNumber = 0; subviewNumber < numSubviews; subviewNumber++) {
                const double size = lround(targetSize / n);
                currentSumOfSizes += size;
                [sizes addObject:[NSNumber numberWithDouble:size]];
                [minSizes addObject:@(MAX(0, size - 1))];
                [maxSizes addObject:@(MIN(targetSize, size + 1))];
            }
        } else {
            // Resize everything proportionately.
            for (int i = 0; i < [sizes count]; ++i) {
                NSView* aSubview = [[splitView subviews] objectAtIndex:i];
                const double size = lround(sizeChangeCoeff * WithGrainDim(isVertical, [aSubview frame].size));
                currentSumOfSizes += size;
                [sizes replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:size]];
            }
        }

        SetPinnedDebugLogMessage(@"Current split view for redistribution", @"oldTotalSize=%@ ignoreConstraints=%@ splitView.recursiveDescription=%@", @(oldTotalSize), @(ignoreConstraints), [splitView iterm_recursiveDescription]);
        [self _redistributeQuantizationError:targetSize
                           currentSumOfSizes:currentSumOfSizes
                                       sizes:sizes
                                    minSizes:minSizes
                                    maxSizes:maxSizes];
        SetPinnedDebugLogMessage(@"Current split view for redistribution", nil);
    }

    // If all subviews are leaf nodes, redistribute extra pixels among the subviews
    // so that as few as possible of them has extra space "with the grain".
    BOOL allSubviewsAreLeafNodes = YES;
    for (id aSubview in [splitView subviews]) {
        if (![aSubview isKindOfClass:[SessionView class]]) {
            allSubviewsAreLeafNodes = NO;
            break;
        }
    }
    if (allSubviewsAreLeafNodes) {
        // index -> overage
        NSMutableDictionary *over = [NSMutableDictionary dictionary];
        // index -> underage
        NSMutableDictionary *under = [NSMutableDictionary dictionary];
        for (int i = 0; i < sizes.count; i++) {
            NSSize size;
            SetWithGrainDim(isVertical, &size, [[sizes objectAtIndex:i] doubleValue]);
            SessionView *sessionView = (SessionView *) [[splitView subviews] objectAtIndex:i];
            PTYSession *aSession = [self sessionForSessionView:sessionView];
            int ou = [aSession overUnder:WithGrainDim(isVertical, size) inVerticalDimension:!isVertical];
            if (ou > 0) {
                [over setObject:[NSNumber numberWithInt:ou] forKey:[NSNumber numberWithInt:i]];
            } else if (ou < 0) {
                [under setObject:[NSNumber numberWithInt:-ou] forKey:[NSNumber numberWithInt:i]];
            }
        }

        // Get indices of subviews with extra/lacking pixels
        NSMutableArray *overKeys = [NSMutableArray arrayWithArray:[[over allKeys] sortedArrayUsingSelector:@selector(compare:)]];
        NSMutableArray *underKeys = [NSMutableArray arrayWithArray:[[under allKeys] sortedArrayUsingSelector:@selector(compare:)]];
        while (overKeys.count && underKeys.count) {
            // Pick the last over and under values and cancel the out as much as possible.
            int mostOverIndex = [[overKeys lastObject] intValue];
            int mostOverValue = [[over objectForKey:[overKeys lastObject]] intValue];
            int mostUnderIndex = [[underKeys lastObject] intValue];
            int mostUnderValue = [[under objectForKey:[underKeys lastObject]] intValue];

            int currentValue = MIN(mostOverValue, mostUnderValue);
            mostOverValue -= currentValue;
            mostUnderValue -= currentValue;
            double overSize = [[sizes objectAtIndex:mostOverIndex] doubleValue];
            double underSize = [[sizes objectAtIndex:mostUnderIndex] doubleValue];
            [sizes replaceObjectAtIndex:mostOverIndex withObject:[NSNumber numberWithDouble:overSize - currentValue]];
            [sizes replaceObjectAtIndex:mostUnderIndex withObject:[NSNumber numberWithDouble:underSize + currentValue]];
            if (!mostOverValue) {
                [overKeys removeObject:[NSNumber numberWithInt:mostOverIndex]];
            }
            if (!mostUnderValue) {
                [underKeys removeObject:[NSNumber numberWithInt:mostUnderIndex]];
            }
            [over setObject:[NSNumber numberWithInt:mostOverValue] forKey:[NSNumber numberWithInt:mostOverIndex]];
            [under setObject:[NSNumber numberWithInt:mostUnderValue] forKey:[NSNumber numberWithInt:mostUnderIndex]];
        }
    }

    NSRect frame = NSZeroRect;
    SetAgainstGrainDim(isVertical, &frame.size, AgainstGrainDim(isVertical, [splitView frame].size));
    DLog(@"Target: %@\nBefore:\n%@\nSizes:\n%@", NSStringFromSize(splitView.frame.size), splitView.subviews, sizes);
    for (int i = 0; i < [sizes count]; ++i) {
        SetWithGrainDim(isVertical, &frame.size, [[sizes objectAtIndex:i] doubleValue]);
        [[[splitView subviews] objectAtIndex:i] setFrame:frame];
        if (isVertical) {
            frame.origin.x += frame.size.width + [splitView dividerThickness];
        } else {
            frame.origin.y += frame.size.height + [splitView dividerThickness];
        }
    }
    DLog(@"After:\n%@", splitView.subviews);
    return YES;
}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification {
    _resizingSplit = YES;
    [self updateUseMetal];
}

// Inform sessions about their new sizes. This is called after views have finished
// being resized.
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification {
    if (tmuxOriginatedResizeInProgress_) {
        // Whoever's doing the resizing is responsible for making everything
        // perfect.
        return;
    }
    if ([root_ frame].size.width == 0) {
        XLog(@"Warning: splitViewDidResizeSubviews: resized to 0 width");
        return;
    }
    PtyLog(@"splitViewDidResizeSubviews notification received. new height is %lf", [root_ frame].size.height);
    NSSplitView* splitView = [aNotification object];
    [self _splitViewDidResizeSubviews:splitView];
    _resizingSplit = NO;
    [self updateUseMetal];
}

// This is the implementation of splitViewDidResizeSubviews. The delegate method isn't called when
// views are added or adjusted, so we often have to call this ourselves.
- (void)_splitViewDidResizeSubviews:(NSSplitView*)splitView {
    PtyLog(@"_splitViewDidResizeSubviews running");
    for (NSView* subview in [splitView subviews]) {
        if ([subview isKindOfClass:[SessionView class]]) {
            PTYSession* session = [self sessionForSessionView:(SessionView*)subview];
            if (session) {
                PtyLog(@"splitViewDidResizeSubviews - view is %fx%f, ignore=%d", [subview frame].size.width, [subview frame].size.height, (int)[session ignoreResizeNotifications]);
                if (![session ignoreResizeNotifications]) {
                    PtyLog(@"splitViewDidResizeSubviews - adjust session %p", session);
                    [self fitSessionToCurrentViewSize:session];
                }
            }
        } else {
            [self _splitViewDidResizeSubviews:(NSSplitView*)subview];
        }
    }
}

- (void)adjustSplitSubviewSizesForPinnedSizes:(NSSplitView *)splitView {
    if (!splitView.vertical) {
        return;
    }
    NSArray<SessionView *> *sessionViews = [splitView.subviews mapWithBlock:^id _Nullable(__kindof NSView * _Nonnull anObject) {
        return [SessionView castFrom:anObject];
    }];
    if ([sessionViews allWithBlock:^BOOL(SessionView *sessionView) {
        return sessionView.preferredWidth != nil;
    }]) {
        return;
    }
    [self resizeSubviewsOfSplitView:splitView oldSize:splitView.frame.size respectPinning:YES];
}

- (CGFloat)_recursiveStepSize:(__kindof NSView *)theView wantWidth:(BOOL)wantWidth {
    if ([theView isKindOfClass:[SessionView class]]) {
        SessionView *sessionView = theView;
        if (wantWidth) {
            return [[[self sessionForSessionView:sessionView] textview] charWidth];
        } else {
            return [[[self sessionForSessionView:sessionView] textview] lineHeight];
        }
    } else {
        CGFloat maxStep = 0;
        for (NSView *subview in [theView subviews]) {
            CGFloat step = [self _recursiveStepSize:subview wantWidth:wantWidth];
            maxStep = MAX(maxStep, step);
        }
        return maxStep;
    }
}

- (CGFloat)stepForMovementOfDividerIndex:(NSInteger)dividerIndex
                             ofSplitView:(NSSplitView *)splitView {
    NSArray<NSView *> *subviews = [splitView subviews];
    NSView *childBefore = subviews[dividerIndex];
    NSView *childAfter = subviews[dividerIndex + 1];
    CGFloat beforeStep = [self _recursiveStepSize:childBefore wantWidth:[splitView isVertical]];
    CGFloat afterStep = [self _recursiveStepSize:childAfter wantWidth:[splitView isVertical]];
    CGFloat step = MAX(beforeStep, afterStep);
    return step;
}

// Make splitters jump by char widths/line heights. If there is a difference,
// pick the largest on either side of the divider.
- (CGFloat)splitView:(NSSplitView *)splitView
        constrainSplitPosition:(CGFloat)proposedPosition
                   ofSubviewAt:(NSInteger)dividerIndex {
    if (tmuxOriginatedResizeInProgress_) {
        return proposedPosition;
    }
    PtyLog(@"PTYTab splitView:constraintSplitPosition%f divider:%d case ", (float)proposedPosition, (int)dividerIndex);
    NSArray<NSView *> *subviews = [splitView subviews];
    if (dividerIndex < 0 ||
        subviews.count < dividerIndex + 2) {
        DLog(@"Have %@ subviews. Aborting.", @(subviews.count));
        return proposedPosition;
    }

    const CGFloat step = [self stepForMovementOfDividerIndex:dividerIndex ofSplitView:splitView];
    NSView *const childBefore = splitView.subviews[dividerIndex];
    NSRect beforeRect = [childBefore frame];
    CGFloat originalPosition;
    if ([splitView isVertical]) {
        originalPosition = beforeRect.origin.x + beforeRect.size.width;
    } else {
        originalPosition = beforeRect.origin.y + beforeRect.size.height;
    }
    CGFloat diff = fabs(proposedPosition - originalPosition);
    int chars = diff / step;
    CGFloat allowedDiff = chars * step;
    if (proposedPosition < originalPosition) {
        allowedDiff *= -1;
    }
    return originalPosition + allowedDiff;
}

- (BOOL)sessionIsActiveInTab:(PTYSession *)session {
    return [self activeSession] == session;
}

- (BOOL)tabIsSelected {
    return [[tabViewItem_ tabView] selectedTabViewItem] == [self tabViewItem];
}

- (BOOL)sessionIsActiveInSelectedTab:(PTYSession *)session {
    if (![self tabIsSelected]) {
        return NO;
    }
    return [self activeSession] == session;
}

- (BOOL)sessionIsInSelectedTab:(PTYSession *)session {
    return [[tabViewItem_ tabView] selectedTabViewItem] == [self tabViewItem];
}

#pragma mark - Private

- (void)setLabelAttributesForDeadSession {
    DLog(@"Session is dead");
    [self setState:kPTYTabDeadState reset:0];

    if (isProcessing_) {
        [self setIsProcessing:NO];
    }
}

- (BOOL)_windowResizedRecently {
    NSDate *lastResize = [realParentWindow_ lastResizeTime];
    double elapsed = [[NSDate date] timeIntervalSinceDate:lastResize];
    return elapsed < 2;
}

- (void)setLabelAttributesForIdleTab {
    BOOL isBackgroundTab = [[tabViewItem_ tabView] selectedTabViewItem] != [self tabViewItem];
    if ([self isProcessing]) {
        [self setIsProcessing:NO];  // This triggers KVO in PSMTabBarCell
    }

    BOOL allSessionsWithNewOutputAreIdle = YES;
    BOOL anySessionHasNewOutput = NO;
    for (PTYSession *session in [self sessions]) {
        if ([session newOutput]) {
            DLog(@"%@ has new output", self);
            // Got new output
            anySessionHasNewOutput = YES;

            if (session.isIdle &&
                [[NSDate date] timeIntervalSinceDate:[SessionView lastResizeDate]] > POST_WINDOW_RESIZE_SILENCE_SEC) {
                // Idle after new output

                // See if a notification should be posted.
                if (!session.havePostedIdleNotification && [session shouldPostUserNotification]) {
                    NSString *theDescription =
                        [NSString stringWithFormat:@"Session %@ in tab #%d became idle.",
                            [[session name] removingHTMLFromTabTitleIfNeeded],
                            [self tabNumber]];
                    if ([iTermProfilePreferences boolForKey:KEY_SEND_IDLE_ALERT inProfile:session.profile]) {
                        [[iTermNotificationController sharedInstance] notify:@"Idle"
                                                         withDescription:theDescription
                                                             windowIndex:[session screenWindowIndex]
                                                                tabIndex:[session screenTabIndex]
                                                               viewIndex:[session screenViewIndex]];
                    }
                    session.havePostedIdleNotification = YES;
                    session.havePostedNewOutputNotification = NO;
                }
            } else {
                allSessionsWithNewOutputAreIdle = NO;
            }
        }
    }

    // Update state
    if (isBackgroundTab) {
        if (anySessionHasNewOutput) {
            if (allSessionsWithNewOutputAreIdle) {
                DLog(@"Tab is idle");
                [self setState:kPTYTabIdleState reset:kPTYTabNewOutputState];
            }
        } else {
            // No new output (either we got foregrounded or nothing has happened to a background tab)
            DLog(@"Clear idle & new output state");
            [self setState:0 reset:(kPTYTabIdleState | kPTYTabNewOutputState)];
        }
    }
}

- (void)setLabelAttributesForActiveTab:(BOOL)notify {
    BOOL isBackgroundTab = [[tabViewItem_ tabView] selectedTabViewItem] != [self tabViewItem];
    [self setIsProcessing:[self anySessionIsProcessing] && ![self isForegroundTab]];

    if (![[self activeSession] havePostedNewOutputNotification] &&
        [[self realParentWindow] broadcastMode] == BROADCAST_OFF &&
        notify &&
        [[NSDate date] timeIntervalSinceDate:[SessionView lastResizeDate]] > POST_WINDOW_RESIZE_SILENCE_SEC) {
        if ([iTermProfilePreferences boolForKey:KEY_SEND_NEW_OUTPUT_ALERT inProfile:self.activeSession.profile]) {
            [[iTermNotificationController sharedInstance] notify:NSLocalizedStringFromTableInBundle(@"New Output",
                                                                                                @"iTerm",
                                                                                                [NSBundle bundleForClass:[self class]],
                                                                                                @"User Alerts")
                                             withDescription:[NSString stringWithFormat:@"New output was received in %@, tab #%d.",
                                                              [[[self activeSession] name] removingHTMLFromTabTitleIfNeeded],
                                                              [self tabNumber]]
                                                 windowIndex:[[self activeSession] screenWindowIndex]
                                                    tabIndex:[[self activeSession] screenTabIndex]
                                                   viewIndex:[[self activeSession] screenViewIndex]];
        }
        [[self activeSession] setHavePostedNewOutputNotification:YES];
        [[self activeSession] setHavePostedIdleNotification:NO];
    }

    if ([self _windowResizedRecently]) {
        // Reset new output flag for all sessions because it may have been caused by an app
        // redrawing itself in response to the window resizing.
        for (PTYSession* session in [self sessions]) {
            [session setNewOutput:NO];
        }
    } else if (isBackgroundTab) {
        DLog(@"Background tab has new output");
        [self setState:kPTYTabNewOutputState reset:kPTYTabIdleState];
    }
}

- (void)resetLabelAttributesIfAppropriate {
    DLog(@"resetLabelAttributesIfAppropriate");
    BOOL amProcessing = [self isProcessing];
    BOOL shouldResetLabel = NO;
    for (PTYSession *aSession in [self sessions]) {
        if (!amProcessing &&
            !aSession.havePostedNewOutputNotification &&
            !aSession.newOutput) {
            // Avoid calling the potentially expensive -shouldPostUserNotification if there's
            // nothing to do here, which is normal.
            continue;
        }
        if (![aSession shouldPostUserNotification]) {
            [aSession setHavePostedNewOutputNotification:NO];
            shouldResetLabel = YES;
        }
    }
    if (shouldResetLabel && [self isForegroundTab]) {
        DLog(@"Reset label");
        [self setIsProcessing:NO];
        [self setState:0 reset:(kPTYTabIdleState |
                                kPTYTabNewOutputState |
                                kPTYTabDeadState)];
    }
}

// Note this is a notification handler
- (void)updateUseMetal NS_AVAILABLE_MAC(10_11) {
    DLog(@"begin");
    const BOOL resizing = self.realParentWindow.windowIsResizing;
    const BOOL powerOK = [[iTermPowerManager sharedInstance] metalAllowed];
    __block iTermMetalUnavailableReason sessionReason = iTermMetalUnavailableReasonNone;
    NSArray<PTYSession *> *nonHiddenSessions = [self.sessions filteredArrayUsingBlock:^BOOL(PTYSession *session) {
        if (!self->isMaximized_) {
            // Invisible sessions in a maximized tab aren't in the view hierarchy and so will always
            // say Metal is disallowed.
            return YES;
        }
        return session == self.activeSession;
    }];
    const BOOL allSessionsAllowMetal = [nonHiddenSessions allWithBlock:^BOOL(PTYSession *anObject) {
        return [anObject metalAllowed:&sessionReason];
    }];
    const BOOL allSessionsIdle = (allSessionsAllowMetal &&
                                  [iTermAdvancedSettingsModel disableMetalWhenIdle] &&
                                  [self.sessions allWithBlock:^BOOL(PTYSession *anObject) {
        return anObject.idleForMetal;
    }]);

    // Limit the number of split panes using metal because each gets its own thread and I've seen
    // some crazy stuff where people have over 50 split panes.
    const NSInteger maxNumberOfSplitPanesForMetal = 6;
    const BOOL numberOfSplitPanesIsReasonable = self.sessions.count < maxNumberOfSplitPanesForMetal;

    iTermMetalUnavailableReason reason = iTermMetalUnavailableReasonNone;
    BOOL allowed = NO;
    // Note: we turn off metal when dragging a split in a tmux tab because it's hard to keep the
    // frame of the iTermMTKView correct without resizing it.
    if ([self.delegate tabAnyDragInProgress:self] || _isDraggingSplitInTmuxTab) {
        _metalUnavailableReason = iTermMetalUnavailableReasonTabDragInProgress;
    } else if (resizing) {
        _metalUnavailableReason = iTermMetalUnavailableReasonWindowResizing;
    } else if (!powerOK) {
        _metalUnavailableReason = iTermMetalUnavailableReasonDisconnectedFromPower;
    } else if (!allSessionsAllowMetal) {
        _metalUnavailableReason = sessionReason;
    } else if (allSessionsIdle) {
        _metalUnavailableReason = iTermMetalUnavailableReasonIdle;
    } else if (!numberOfSplitPanesIsReasonable) {
        _metalUnavailableReason = iTermMetalUnavailableReasonTooManyPanesReason;
    } else if (![_delegate tabCanUseMetal:self reason:&reason]) {
        _metalUnavailableReason = reason;
    } else if (_bounceMetal) {
        _metalUnavailableReason = iTermMetalUnavailableReasonScreensChanging;
    } else if ([self.delegate tabIsSwiping]) {
        _metalUnavailableReason = iTermMetalUnavailableReasonSwipingBetweenTabs;
    } else if (_isDraggingSplitInTmuxTab) {
        _metalUnavailableReason = iTermMetalUnavailableReasonSplitPaneBeingDragged;
    } else {
        _metalUnavailableReason = iTermMetalUnavailableReasonNone;
        allowed = YES;
    }
    const BOOL ONLY_KEY_WINDOWS_USE_METAL = NO;
    const BOOL isKey = [[[self realParentWindow] window] isKeyWindow];
    const BOOL satisfiesKeyRequirement = (isKey || !ONLY_KEY_WINDOWS_USE_METAL);
    if (!satisfiesKeyRequirement) {
        _metalUnavailableReason = iTermMetalUnavailableReasonNoFocus;
    }
    const BOOL foregroundTab = [self isForegroundTab];
    if (!foregroundTab) {
        _metalUnavailableReason = iTermMetalUnavailableReasonTabInactive;
    }
    BOOL useMetal = NO;
    if (allowed && satisfiesKeyRequirement && foregroundTab) {
        useMetal = [nonHiddenSessions allWithBlock:^BOOL(PTYSession *session) {
            return [session willEnableMetal];
        }];
        if (!useMetal) {
            DLog(@"Not enabling metal. A session failed in willEnableMetal.");
            _metalUnavailableReason = iTermMetalUnavailableReasonContextAllocationFailure;
        }
    }
    DLog(@"_metalUnavailableReason = %@", iTermMetalUnavailableReasonDescription(_metalUnavailableReason));
    [self.sessions enumerateObjectsUsingBlock:^(PTYSession * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (self->isMaximized_) {
            obj.useMetal = useMetal && (obj == self.activeSession);
            return;
        }
        obj.useMetal = useMetal;
    }];
    [_delegate tab:self didSetMetalEnabled:useMetal];
}

- (void)metalSettingsDidChange:(NSNotification *)notification {
    [self bounceMetal];
}

- (void)tmuxDidFetchSetTitlesStringOption:(NSNotification *)notification {
    if (notification.object != tmuxController_) {
        return;
    }

    [self updateTmuxTitleMonitor];
}

// Metal is disabled when any note anywhere is visible because compositing NSViews over Metal
// is a horror and besides these are subviews of PTYTextView and I really don't
// want to invest any more in this little-used feature.
- (void)annotationVisibilityDidChange:(NSNotification *)notification {
    if ([iTermPreferences boolForKey:kPreferenceKeyUseMetal]) {
        [self updateUseMetal];
    }
}

- (void)preferenceDidChange:(iTermPreferenceDidChangeNotification *)notification {
    static NSSet<NSString *> *keysAffectingMetal;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keysAffectingMetal = [[NSSet alloc] initWithArray:@[ kPreferenceKeyUseMetal ]];
    });
    if ([keysAffectingMetal containsObject:notification.key]) {
        [self updateUseMetal];
    }
}

- (void)updateTmuxTitleMonitor {
    if (!self.isTmuxTab) {
        return;
    }
    if (tmuxController_.shouldSetTitles) {
        if (_tmuxTitleMonitor) {
            return;
        }
        [self installTmuxTitleMonitor];
    } else {
        if (!_tmuxTitleMonitor) {
            return;
        }
        [self uninstallTmuxTitleMonitor];
    }
}

- (void)bounceMetal {
    _bounceMetal = YES;
    [self updateUseMetal];
    _bounceMetal = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateUseMetal];
    });
}

#pragma mark - PTYSessionDelegate
// TODO: Move the rest of the delegate methods here.

- (BOOL)session:(PTYSession *)session shouldAllowDrag:(id<NSDraggingInfo>)sender {
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {
        // Dragging a tab handle. Source is a PSMTabBarControl.
        PTYTab *theTab = (PTYTab *)[[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        if ([[theTab sessions] containsObject:session] || [[theTab sessions] count] > 1) {
            return NO;
        }
        if (![[theTab activeSession] isCompatibleWith:session]) {
            // Can't have heterogeneous tmux controllers in one tab.
            return NO;
        }
    }
    return YES;
}

- (BOOL)session:(PTYSession *)session performDragOperation:(id<NSDraggingInfo>)sender {
    DLog(@"session:%@ performDragOperation:%@", session, sender);

    // self is the destination tab. session is the session that's moving.
    if ([[[sender draggingPasteboard] types] indexOfObject:iTermMovePaneDragType] != NSNotFound) {
        if ([[MovePaneController sharedInstance] isMovingSession:session]) {
            if (self.sessions.count == 1 && !self.realParentWindow.anyFullScreen && self.realParentWindow.movesWhenDraggedOntoSelf) {
                // If you dragged a session from a tab with split panes onto itself then do nothing.
                // But if you drag a session onto itself in a tab WITHOUT split panes, then move the
                // whole window.
                [[MovePaneController sharedInstance] moveWindowBy:[sender draggedImageLocation]];
            }
            // Regardless, we must say the drag failed because otherwise
            // draggedImage:endedAt:operation: will try to move the session to its own window.
            [[MovePaneController sharedInstance] setDragFailed:YES];
            return NO;
        }
        return [[MovePaneController sharedInstance] dropInSession:session
                                                             half:[session.view removeSplitSelectionView]
                                                          atPoint:[sender draggingLocation]];
    } else {
        // Drag a tab into a split
        PTYTab *theTab = (PTYTab *)[[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject] identifier];
        const BOOL moved = [[MovePaneController sharedInstance] dropTab:theTab
                                                              inSession:session
                                                                   half:[session.view removeSplitSelectionView]
                                                                atPoint:[sender draggingLocation]];
        if (moved) {
            [[MovePaneController sharedInstance] clearSession];
        }
        return moved;
    }
}

- (BOOL)sessionBelongsToTmuxTabWhoseSplitsAreBeingDragged {
    return _isDraggingSplitInTmuxTab;
}

- (BOOL)sessionBelongsToTabWhoseSplitsAreBeingDragged {
    return _numberOfSplitViewDragsInProgress > 0;
}

- (void)sessionDoubleClickOnTitleBar:(PTYSession *)session {
    [self toggleMaximizeSession:session];
}

- (void)toggleMaximizeSession:(PTYSession *)session {
    if (session.isTmuxClient) {
        [session toggleTmuxZoom];
    } else if ([self hasMaximizedPane]) {
        [self unmaximize];
    } else {
        if (self.activeSession != session) {
            [self setActiveSession:session];
        }
        [self maximize];
    }
}

- (NSArray<PTYSession *> *)minimizedSessions {
    return [[self sessions] arrayByRemovingObject:self.activeSession];
}

- (NSUInteger)sessionPaneNumber:(PTYSession *)session {
    NSUInteger index = [self.sessions indexOfObject:session];
    if (index == NSNotFound) {
        return self.sessions.count;
    } else {
        // It must have just been added.
        return self.sessions.count - 1;
    }
}

- (void)sessionBackgroundColorDidChange:(PTYSession *)session {
    if (session.isTmuxClient) {
        [self updateFlexibleViewColors];
    }
    [self.delegate tabSessionDidChangeBackgroundColor:self];
    for (PTYSession *session in self.sessions) {
        [session.view updateColors];
    }
    [root_ setNeedsDisplay:YES];
}

- (void)sessionKeyLabelsDidChange:(PTYSession *)session {
    [_delegate tabKeyLabelsDidChangeForSession:session];
}

- (void)sessionCurrentDirectoryDidChange:(PTYSession *)session {
    if (session == self.activeSession) {
        [_delegate tabInvalidateProxyIcon:self];
    }
}

- (void)sessionCurrentHostDidChange:(PTYSession *)session {
    if (session == self.activeSession) {
        [_delegate tabInvalidateProxyIcon:self];
    }
}

- (void)sessionDidRestart:(PTYSession *)session {
    [self.delegate tab:self sessionDidRestart:session];
}

- (void)sessionProxyIconDidChange:(PTYSession *)session {
    if (session == self.activeSession) {
        [_delegate tabInvalidateProxyIcon:self];
    }
}

- (void)sessionRemoveSession:(PTYSession *)session {
    BOOL removeTab = (self.sessions.count == 1);
    [self removeSession:session];
    if (removeTab) {
        [_delegate tabRemoveTab:self];
    }
}

- (VT100GridSize)sessionTmuxSizeWithProfile:(Profile *)profile {
    // See discussion in issue 11810.
    const iTermOpenTmuxWindowsMode openWindowsMode = [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn];
    const BOOL useExistingWindowSize = (openWindowsMode == kOpenTmuxWindowsAsNativeTabsInExistingWindow);
    DLog(@"useExistingWindowSize=%@ useTmuxProfile=%@", @(useExistingWindowSize), @([iTermPreferences useTmuxProfile]));
    if ([iTermPreferences useTmuxProfile] && !useExistingWindowSize) {
        DLog(@"Return size from profile %@", profile);
        return VT100GridSizeMake([[profile objectForKey:KEY_COLUMNS] intValue],
                                 [[profile objectForKey:KEY_ROWS] intValue]);
    } else {
        NSSize frameSize = tabView_.frame.size;
        DLog(@"Compute size from frame %@", NSStringFromSize(frameSize));
        PTYSession *anySession = self.sessions.firstObject;

        NSSize contentSize = [PTYScrollView contentSizeForFrameSize:frameSize
                                            horizontalScrollerClass:nil
                                              verticalScrollerClass:[realParentWindow_ scrollbarShouldBeVisible] ? [[anySession.view.scrollview verticalScroller] class] : nil
                                                         borderType:anySession.view.scrollview.borderType
                                                        controlSize:NSControlSizeRegular
                                                      scrollerStyle:anySession.view.scrollview.scrollerStyle
                                                         rightExtra:[PTYSession desiredRightExtraForProfile:profile]];
        NSSize cellSize = [PTYTab cellSizeForBookmark:profile];
        return VT100GridSizeMake((contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2) / cellSize.width,
                                 (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / cellSize.height);
    }
}

- (void)sessionUpdateMetalAllowed {
    [self updateUseMetal];
}

- (void)sessionDidChangeMetalViewAlphaValue:(PTYSession *)session to:(CGFloat)newValue {
    [self.delegate tabDidChangeMetalViewVisibility:self];
}

- (void)sessionTransparencyDidChange {
    [self sessionUpdateMetalAllowed];
    [realParentWindow_ tabSessionDidChangeTransparency:self];
}

- (void)sessionDidClearScrollbackBuffer:(PTYSession *)session {
    [realParentWindow_ tabDidClearScrollbackBufferInSession:session];
}

- (iTermVariables *)sessionTabVariables {
    return _variables;
}

- (void)sessionDuplicateTab {
    if ([self isTmuxTab]) {
        DLog(@"Declining to dup tmux tab");
        return;
    }
    [parentWindow_ createDuplicateOfTab:self];
}

- (BOOL)sessionShouldAutoClose:(PTYSession *)session {
    return _numberOfSplitViewDragsInProgress == 0;
}

- (void)sessionDidChangeGraphic:(PTYSession *)session shouldShow:(BOOL)shouldShow image:(NSImage *)image {
    if (session == self.activeSession) {
        [self.delegate tabDidChangeGraphic:self
                                shouldShow:shouldShow
                                     image:image];
    }
}

- (PTYSession *)sessionWithGUID:(NSString *)guid {
    return [self.sessions objectPassingTest:^BOOL(PTYSession *session, NSUInteger index, BOOL *stop) {
        return [session.guid isEqualToString:guid];
    }];
}

- (NSView *)sessionContainerView:(PTYSession *)session {
    return root_;
}

- (void)sessionDraggingExited:(PTYSession *)session {
    if (_temporarilyUnmaximizedSessionGUID) {
        PTYSession *session = [self sessionWithGUID:_temporarilyUnmaximizedSessionGUID];
        if (session && !self.hasMaximizedPane) {
            [self setActiveSession:session];
            [self maximize];
        }
    }
    _temporarilyUnmaximizedSessionGUID = nil;
}

- (void)sessionDraggingEntered:(PTYSession *)session {
    if (self.hasMaximizedPane) {
        _temporarilyUnmaximizedSessionGUID = [[session guid] copy];
        [self unmaximize];
    }
}

- (BOOL)sessionShouldSendWindowSizeIOCTL:(PTYSession *)session {
    if ([[MovePaneController sharedInstance] dropping]) {
        return YES;
    }
    if ([[PSMTabDragAssistant sharedDragAssistant] dropping]) {
        return YES;
    }
    if ([[MovePaneController sharedInstance] isDragInProgress]) {
        return NO;
    }
    if ([[PSMTabDragAssistant sharedDragAssistant] isDragging]) {
        return NO;
    }
    return _temporarilyUnmaximizedSessionGUID == nil;
}

- (void)sessionDidInvalidateStatusBar:(PTYSession *)session {
    if (session == self.activeSession) {
        [_delegate tabDidInvalidateStatusBar:self];
    }
}

- (void)sessionAddSwiftyStringsToGraph:(iTermSwiftyStringGraph *)graph {
    [graph addSwiftyString:_tabTitleOverrideSwiftyString
            withFormatPath:iTermVariableKeyTabTitleOverrideFormat
            evaluationPath:iTermVariableKeyTabTitleOverride
                     scope:self.variablesScope];

    [self.realParentWindow tabAddSwiftyStringsToGraph:graph];
}

- (iTermVariableScope *)sessionTabScope {
    return self.variablesScope;
}

- (void)sessionDidReportSelectedTmuxPane:(PTYSession *)session {
    [_tmuxTitleMonitor updateOnce];
}

- (void)sessionDidUpdatePaneTitle:(PTYSession *)session {
    [_tmuxTitleMonitor updateOnce];
}

- (void)sessionDidSetWindowTitle:(NSString *)title {
    [self.delegate tabDidSetWindowTitle:self to:title];
}

- (void)sessionJobDidChange:(PTYSession *)session {
    [self.delegate tabHasNontrivialJobDidChange:self];
}

- (void)sessionEditActions {
    [self.delegate tabEditActions:self];
}

- (void)sessionEditSnippets {
    [self.delegate tabEditSnippets:self];
}

- (iTermImageWrapper *)sessionBackgroundImage {
    return [self.delegate tabBackgroundImage];
}

- (iTermBackgroundImageMode)sessionBackgroundImageMode {
    return [self.delegate tabBackgroundImageMode];
}

- (CGFloat)sessionBlend {
    return [self.delegate tabBlend];
}

- (void)sessionDidUpdatePreferencesFromProfile:(PTYSession *)session {
    if (session == self.activeSession) {
        [self.delegate tabActiveSessionDidUpdatePreferencesFromProfile:self];
        [self updatePaneTitles];
    }
}

- (void)session:(PTYSession *)session
setBackgroundImage:(iTermImageWrapper *)image
           mode:(iTermBackgroundImageMode)imageMode
backgroundColor:(NSColor *)backgroundColor {
    if (session != self.activeSession) {
        DLog(@"Inactive session tried to set the background image. Ignore it.");
        return;
    }
    [self.delegate tab:self setBackgroundImage:image mode:imageMode backgroundColor:backgroundColor];
}

- (id<iTermSwipeHandler>)sessionSwipeHandler {
    return self.delegate;
}

- (void)sessionDisableFocusFollowsMouseAtCurrentLocation {
    for (PTYSession *session in self.sessions) {
        [session refuseFirstResponderAtCurrentMouseLocation];
    }
}

- (void)sessionDidResize:(PTYSession *)session {
    if (session != self.activeSession) {
        return;
    }
    [self.delegate tabActiveSessionDidResize:self];
}

- (BOOL)sessionPasswordManagerWindowIsOpen {
    return [self.delegate tabPasswordManagerWindowIsOpen];
}

- (BOOL)sessionShouldDragWindowByPaneTitleBar:(PTYSession *)session {
    if ([[self windowPanes] count] != 1) {
        return NO;
    }
    return [realParentWindow_ tabCanDragByPaneTitleBar];
}

- (void)sessionSubtitleDidChange:(PTYSession *)session {
    if (session != self.activeSession) {
        return;
    }
    [self _refreshLabels:nil];
}

- (void)session:(PTYSession *)session setFilter:(NSString *)filter {
    [self setFilter:filter inSession:session];
}

- (PTYSession *)sessionSyntheticSessionFor:(PTYSession *)live {
    for (PTYSession *session in self.sessions) {
        if (session.liveSession == live) {
            return session;
        }
    }
    return nil;
}

- (void)sessionClose:(PTYSession *)session {
    [self.delegate tab:self closeSession:session];
}

- (void)sessionProcessInfoProviderDidChange:(PTYSession *)session {
    if (session != self.activeSession) {
        return;
    }
    [self.delegate tabProcessInfoProviderDidChange:self];
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    if (!_methods) {
        _methods = [[iTermBuiltInFunctions alloc] init];
        iTermBuiltInMethod *method;
        method = [[iTermBuiltInMethod alloc] initWithName:@"set_title"
                                            defaultValues:@{}
                                                    types:@{ @"title": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(setTitleWithCompletion:title:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"select_pane_in_direction"
                                            defaultValues:@{}
                                                    types:@{ @"direction": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(selectPaneInDirectionWithCompletion:direction:)];
        [_methods registerFunction:method namespace:@"iterm2"];
    }
    return _methods;
}

- (void)setTitleWithCompletion:(void (^)(id, NSError *))completion
                         title:(NSString *)title {
    [self setTitleOverride:title];
    completion(nil, nil);
}

- (void)selectPaneInDirectionWithCompletion:(void (^)(id, NSError *))completion
                                  direction:(NSString *)direction {
    PTYSession *activeSession = [self activeSession];
    PTYSession *session;
    if ([direction isEqualToString:@"left"]) {
        session = [self sessionLeftOf:activeSession];
    } else if ([direction isEqualToString:@"right"]) {
        session = [self sessionRightOf:activeSession];
    } else if ([direction isEqualToString:@"above"]) {
        session = [self sessionAbove:activeSession];
    } else if ([direction isEqualToString:@"below"]) {
        session = [self sessionBelow:activeSession];
    } else {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.select-pane-in-direction"
                                             code:0
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Invalid direction. Should be left, right, above or below." }];
        completion(nil, error);
        return;
    }
    if (!session) {
        completion(nil, nil);
        return;
    }
    [self setActiveSession:session];
    completion(session.guid, nil);
}

- (iTermVariableScope *)objectScope {
    return self.variablesScope;
}

#pragma mark - iTermUniquelyIdentifiable

- (NSString *)stringUniqueIdentifier {
    return _guid;
}

@end
