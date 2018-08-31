#import "iTermLibSessionController.h"
#import "SessionView+iTermLib.h"

#import "PTYSession.h"
#import "PTYScrollView.h"
#import "PTYWindow.h"
#import "iTermToolbeltView.h"
#import "iTermPreferences.h"
#import "SessionView.h"
#import "PseudoTerminal.h"

// iTermLib TODO: These were removed from iTermTextDrawingHelper.h. Why???

// Number of pixels margin on left and right edge.
#define MARGIN 5

// Number of pixels margin on the top.
#define VMARGIN 2

@implementation iTermLibSessionController {
    __strong PTYSession* _session;
    NSSize _initialSize;
    BOOL _wasActive;
    BOOL _terminateInProgress;
    BOOL _isTerminated;
    NSWindow* _observedWindow;
    AutocompleteView* _autocompleteView;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    
    if (_autocompleteView) {
        [_autocompleteView shutdown];
        [_autocompleteView release]; _autocompleteView = nil;
    }
    
    /* if (_observedWindow) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidBecomeKeyNotification object:_observedWindow];
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:_observedWindow];
    } */
    
    if (_session) {
        if (_session.view) {
            _session.view.postsFrameChangedNotifications = NO;
        }
        /* if (_session.view) {
            [NSNotificationCenter.defaultCenter removeObserver:self name:NSViewBoundsDidChangeNotification object:_session.view];
            [NSNotificationCenter.defaultCenter removeObserver:self name:LMSessionViewDidMoveToWindowNotification object:_session.view];
        } */
        
        _session.delegate = nil;
        [_session release]; _session = nil;
    }
    
    [super dealloc];
}

- (instancetype)initWithProfile:(Profile*)profile command:(NSString*)command initialSize:(NSSize)initialSize
{
    self = [super init];
    
    if (self) {
        _initialSize = initialSize;
        
        NSDictionary* aDict = profile;
        
        if (!aDict) {
            aDict = [iTermLibSessionController defaultProfile];
        }
        
        PTYSession* session = [self createTabWithProfile:aDict withCommand:command];
        
        session.delegate = self;
        
        if (session.view) {
            session.view.postsFrameChangedNotifications = YES;
            
            [NSNotificationCenter.defaultCenter addObserver:self
                                                   selector:@selector(sessionViewFrameDidChange:)
                                                       name:NSViewFrameDidChangeNotification
                                                     object:session.view];
            
            [NSNotificationCenter.defaultCenter addObserver:self
                                                   selector:@selector(sessionViewDidMoveToWindow:)
                                                       name:iTermLibSessionViewDidMoveToWindowNotification
                                                     object:session.view];
        }
        
        _session = [session retain];
    }
    
    return self;
}

- (PTYSession*)session
{
    return _session;
}

- (NSView*)view
{
    return self.session.view;
}

- (BOOL)wasActive
{
    return _wasActive;
}

- (void)focus
{
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    [self setActiveSession:self.session];
}

- (void)terminate
{
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    if (self.session &&
        self.session.view) {
        self.session.view.postsFrameChangedNotifications = NO;
    }
    
    [self.session terminate];
}

- (void)showFindPanel
{
    [self.session showFindPanel];
}

- (void)findCursor
{
    [self.session.textview beginFindCursor:YES];
    [self.session.textview placeFindCursorOnAutoHide];
}

- (BOOL)highlightCursorLine
{
    return self.session.highlightCursorLine;
}

- (void)setHighlightCursorLine:(BOOL)value
{
    self.session.highlightCursorLine = value;
}

- (BOOL)showTimestamps
{
    return self.session.textview.showTimestamps;
}

- (void)setShowTimestamps:(BOOL)value
{
    self.session.textview.showTimestamps = value;
}

- (void)paste
{
    [self.session pasteString:NSString.stringFromPasteboard];
}

- (void)pasteSlowly
{
    [self.session pasteString:NSString.stringFromPasteboard flags:kPTYSessionPasteSlowly];
}

- (void)pasteEscapingSpecialCharacters
{
    [self.session pasteString:NSString.stringFromPasteboard flags:kPTYSessionPasteEscapingSpecialCharacters];
}

- (void)pasteAdvanced
{
    [self.session pasteOptions:nil];
}

- (void)clearBuffer
{
    [self.session clearBuffer];
}

- (void)clearScrollbackBuffer
{
    [self.session clearScrollbackBuffer];
}

- (void)openAutocomplete
{
    if (!_autocompleteView) {
        _autocompleteView = [[AutocompleteView alloc] init];
    }
    
    if ([[_autocompleteView window] isVisible]) {
        [_autocompleteView more];
    } else {
        [_autocompleteView popWithDelegate:self.session];
        
        NSString *currentCommand = self.session.currentCommand;
        [_autocompleteView addCommandEntries:[self.session autocompleteSuggestionsForCurrentCommand] context:currentCommand];
    }
}

- (void)setMark
{
    [self.session screenSaveScrollPosition];
}

- (void)jumpToMark
{
    [self.session jumpToSavedScrollPosition];
}

- (void)jumpToNextMark
{
    [self.session nextMarkOrNote];
}

- (void)jumpToPreviousMark
{
    [self.session previousMarkOrNote];
}

- (void)jumpToSelection
{
    PTYTextView *textView = self.session.textview;
    
    if (textView) {
        [textView scrollToSelection];
    } else {
        NSBeep();
    }
}

- (BOOL)logging
{
    return self.session.logging;
}

- (void)setLogging:(BOOL)value
{
    if (value) {
        [self.session logStart];
    } else {
        [self.session logStop];
    }
}

- (void)selectAll
{
    [self.session.textview selectAll:nil];
}

- (void)selectOutputOfLastCommand
{
    [self.session.textview selectOutputOfLastCommand:nil];
}

- (void)selectCurrentCommand
{
    [self.session.textview selectCurrentCommand:nil];
}

- (void)increaseFontSize
{
    [self.session changeFontSizeDirection:1];
    [self fitSessionToCurrentViewSize:self.session];
}

- (void)decreaseFontSize
{
    [self.session changeFontSizeDirection:-1];
    [self fitSessionToCurrentViewSize:self.session];
}

- (void)restoreFontSize
{
    [self.session changeFontSizeDirection:0];
    [self fitSessionToCurrentViewSize:self.session];
}

- (void)addAnnotationAtCursor
{
    [self.session addNoteAtCursor];
}

- (BOOL)showAnnotations
{
    return [self.session.textview anyAnnotationsAreVisible];
}

- (void)toggleShowAnnotations
{
    [self.session textViewToggleAnnotations];
}

- (NSImage*)screenshot
{
    if (_terminateInProgress ||
        _isTerminated ||
        !self.session ||
        self.session.exited ||
        !self.view) {
        return nil;
    }
    
    NSImage *image = nil;
    
    @autoreleasepool {
        NSBitmapImageRep *imageRep = [self.view bitmapImageRepForCachingDisplayInRect:self.view.frame];
        [self.view cacheDisplayInRect:self.view.frame toBitmapImageRep:imageRep];
        
        image = [[NSImage alloc] initWithSize:self.view.frame.size];
        [image addRepresentation:imageRep];
    }
    
    return [image autorelease];
}

- (void)tryToRunShellIntegrationInstallerWithPromptCheck:(BOOL)promptCheck
{
    if (_terminateInProgress ||
        _isTerminated ||
        !self.session) {
        return;
    }
    
    [self.session tryToRunShellIntegrationInstallerWithPromptCheck:promptCheck];
}

- (BOOL)shellIntegrationIsInstalled
{
    if (_terminateInProgress ||
        _isTerminated ||
        !self.session) {
        return NO;
    }
    
    return self.session.screen.shellIntegrationInstalled;
}






- (void)sessionViewFrameDidChange:(NSNotification*)aNotification
{
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    [self performSelector:@selector(sessionViewFrameDidChange) withObject:nil afterDelay:0];
}

- (void)sessionViewFrameDidChange
{
    if (_isTerminated ||
        _terminateInProgress ||
        self.session.view.inLiveResize) {
        return;
    }
    
    [self performSelectorOnMainThread:@selector(fitSessionToCurrentViewSize:) withObject:self.session waitUntilDone:NO];
}

- (void)sessionViewDidMoveToWindow:(NSNotification*)aNotification
{
    if (_observedWindow) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidBecomeKeyNotification object:_observedWindow];
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:_observedWindow];
    }
    
    _observedWindow = self.window;
    
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    if (_observedWindow) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(windowDidBecomeKey:)
                                                   name:NSWindowDidBecomeKeyNotification
                                                 object:_observedWindow];
        
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(windowDidResignKey:)
                                                   name:NSWindowDidResignKeyNotification
                                                 object:_observedWindow];
    }
}

- (void)windowDidBecomeKey:(NSNotification*)aNotification
{
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    NSWindow* theWindow = aNotification.object;
    
    BOOL found = NO;
    
    for (iTermLibSessionController* session in self.delegate.sessions) {
        if (theWindow == session.view.window &&
            session.wasActive) {
            found = YES;
            [self setActiveSession:session.session];
            break;
        }
    }
    
    /* if (!found) {
        for (iTermLibSessionController* session in self.delegate.sessions) {
            if (aNotification.object == session.view.window) {
                [self setActiveSession:session.session];
                break;
            }
        }
    } */
}

- (void)windowDidResignKey:(NSNotification*)aNotification
{
    _wasActive = self.delegate.activePTYSession == self.session && self.session.view.window.firstResponder == self.session.textview;
    [self setActiveSession:nil];
}

- (void)makeCurrentSessionFirstResponder
{
    if (self.currentSession) {
        [self.window performSelectorOnMainThread:@selector(makeFirstResponder:) withObject:self.currentSession.textview waitUntilDone:YES];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                            object:self.currentSession
                                                          userInfo:nil];
    }
}

# pragma mark Copied Code
+ (Profile*)defaultProfile
{
    Profile *aDict = [[ProfileModel sharedInstance] defaultBookmark];
    
    if (!aDict) {
        NSMutableDictionary *temp = [[[NSMutableDictionary alloc] init] autorelease];
        
        [ITAddressBookMgr setDefaultsInBookmark:temp];
        
        [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        
        aDict = temp;
    }
    
    return aDict;
}

- (NSDictionary *)substitutionsForCommand:(NSString *)command
                              sessionName:(NSString *)name
                        baseSubstitutions:(NSDictionary *)substitutions {
    NSSet *cmdVars = [command doubleDollarVariables];
    NSSet *nameVars = [name doubleDollarVariables];
    
    NSMutableSet *allVars = [[cmdVars mutableCopy] autorelease];
    
    [allVars unionSet:nameVars];
    
    NSMutableDictionary *allSubstitutions = [[substitutions mutableCopy] autorelease];
    
    for (NSString *var in allVars) {
        if (!substitutions[var]) {
            // TODO
            //NSString *value = [self promptForParameter:var];
            NSString *value = nil;
            if (!value) {
                return nil;
            }
            allSubstitutions[var] = value;
        }
    }
    return allSubstitutions;
}

- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
    if (_isTerminated ||
        _terminateInProgress) {
        return;
    }
    
    if (aSession.exited) {
        return;
    }
    
    BOOL hasScrollbar = self.scrollbarShouldBeVisible;
    
    int width = columns;
    int height = rows;
    
    if (width < 20) {
        width = 20;
    }
    if (height < 2) {
        height = 2;
    }
    
    // With split panes it is very difficult to directly compute the maximum size of any
    // given pane. However, any growth in a pane can be taken up by the window as a whole.
    // We compute the maximum amount the window can grow and ensure that the rows and columns
    // won't cause the window to exceed the max size.
    
    // iTermLib: We don't need this (hopefully)
    // 1. Figure out how big the tabview can get assuming window decoration remains unchanged.
    /* NSSize maxFrame = self.maxFrame.size;
    NSSize decoration = self.windowDecorationSize;
    NSSize maxTabSize;
    maxTabSize.width = maxFrame.width - decoration.width;
    maxTabSize.height = maxFrame.height - decoration.height;
    
    // 2. Figure out how much the window could grow by in rows and columns.
    NSSize currentSize = NSZeroSize;
    
    NSSize maxGrowth;
    maxGrowth.width = maxTabSize.width - currentSize.width;
    maxGrowth.height = maxTabSize.height - currentSize.height;
    int maxNewRows = maxGrowth.height / aSession.textview.lineHeight;
    
    // 3. Compute the number of rows and columns we're trying to grow by.
    int newRows = rows - aSession.rows;
    // 4. Cap growth if it exceeds the maximum. Do nothing if it's shrinking.
    if (newRows > maxNewRows) {
        int error = newRows - maxNewRows;
        height -= error;
    } */
    //PtyLog(@"safelySetSessionSize - set to %dx%d", width, height);
    [aSession setSize:VT100GridSizeMake(width, height)];
    [aSession.view.scrollview setHasVerticalScroller:hasScrollbar];
    [aSession.view.scrollview setLineScroll:aSession.textview.lineHeight];
    [aSession.view.scrollview setPageScroll:2 * aSession.textview.lineHeight];
    
    if (aSession.backgroundImagePath) {
        aSession.backgroundImagePath = aSession.backgroundImagePath;
    }
}

- (BOOL)fitSessionToCurrentViewSize:(PTYSession *)aSession
{
    if (aSession.exited) {
        return NO;
    }
    
    if (aSession.isTmuxClient) {
        return NO;
    }
    
    NSSize temp = [self sessionSizeForViewSize:aSession];
    
    return [self resizeSession:aSession toSize:VT100GridSizeMake(temp.width, temp.height)];
}

- (BOOL)resizeSession:(PTYSession *)aSession toSize:(VT100GridSize)newSize
{
    if (aSession.exited) {
        return NO;
    }
    
    if (aSession.rows == newSize.height &&
        aSession.columns == newSize.width) {
        return NO;
    }
    
    if (newSize.width == aSession.columns && newSize.height == aSession.rows) {
        return NO;
    }
    
    [aSession setSize:newSize];
    aSession.view.scrollview.lineScroll = aSession.textview.lineHeight;
    aSession.view.scrollview.pageScroll = 2 * aSession.textview.lineHeight;
    
    if (aSession.backgroundImagePath) {
        aSession.backgroundImagePath = aSession.backgroundImagePath;
    }
    
    return YES;
}

- (NSSize)sessionSizeForViewSize:(PTYSession *)aSession {
    [aSession setScrollBarVisible:self.scrollbarShouldBeVisible
                            style:self.scrollerStyle];
    
    NSSize size = aSession.view.maximumPossibleScrollViewContentSize;
    
    int width = (size.width - MARGIN * 2) / aSession.textview.charWidth;
    int height = (size.height - VMARGIN * 2) / aSession.textview.lineHeight;
    
    if (width <= 0) {
        width = 1;
    }
    if (height <= 0) {
        height = 1;
    }
    
    return NSMakeSize(width, height);
}

- (NSRect)maxFrame
{
    // TODO
    NSRect visibleFrame = NSZeroRect;
    
    for (NSScreen* screen in NSScreen.screens) {
        visibleFrame = NSUnionRect(visibleFrame, screen.visibleFrame);
    }
    
    return visibleFrame;
}

- (NSSize)windowDecorationSize
{
    return NSZeroSize;
}

#pragma mark PseudoTerminal

- (NSArray *)broadcastSessions
{
    return self.delegate.broadcasting ? self.delegate.allPTYSessions : [NSArray array];
}

- (void)setBroadcastMode:(BroadcastMode)mode
{
    // TODO
}

- (PTYSession *)createSessionWithProfile:(NSDictionary *)addressbookEntry
                                 withURL:(NSString *)url
                           forObjectType:(iTermObjectType)objectType
                        serverConnection:(iTermFileDescriptorServerConnection *)serverConnection
{
    // TODO
    return nil;
}

- (PTYSession *)createTabWithProfile:(Profile *)profile
                         withCommand:(NSString *)command {
    assert(profile);
    
    // Initialize a new session
    // iTermLib TODO: Synthetic or not?!
    PTYSession *aSession = [[[PTYSession alloc] initSynthetic:NO] autorelease];
    [[aSession screen] setUnlimitedScrollback:[[profile objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[profile objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    
    NSString *commandForSubs = command;
    
    if (!command) {
        commandForSubs = [ITAddressBookMgr bookmarkCommand:profile
                                             forObjectType:iTermWindowObject];
    }
    
    NSDictionary *substitutions = [self substitutionsForCommand:commandForSubs ?: @""
                                                    sessionName:profile[KEY_NAME] ?: @""
                                              baseSubstitutions:@{}];
    if (!substitutions) {
        return nil;
    }
    
    if (command) {
        // Create a modified profile to run "command".
        NSMutableDictionary *temp = [[profile mutableCopy] autorelease];
        temp[KEY_CUSTOM_COMMAND] = @"Yes";
        temp[KEY_COMMAND_LINE] = command;
        profile = temp;
    }
    
    NSString* sessionName = profile[KEY_NAME];
    
    // set our preferences
    [aSession setProfile:profile];
    // Add this session to our term and make it current
    
    [self setupSession:aSession title:sessionName withSize:nil];
    
    if (aSession.screen) {
        // TODO:
        /* [aSession runCommandWithOldCwd:nil
                         forObjectType:iTermWindowObject
                        forceUseOldCWD:NO
                         substitutions:substitutions]; */
        [aSession startProgram:command environment:nil isUTF8:YES substitutions:substitutions completion:nil];
    }
    
    return aSession;
}

- (void)setupSession:(PTYSession*)aSession
               title:(NSString*)title
            withSize:(NSSize*)size {
    NSDictionary *tempPrefs;
    NSParameterAssert(aSession != nil);
    
    // set some default parameters
    if (aSession.profile == nil) {
        tempPrefs = ProfileModel.sharedInstance.defaultBookmark;
        
        if (tempPrefs != nil) {
            // Use the default bookmark. This path is taken with applescript's "make new session at the end of sessions" command.
            aSession.profile = tempPrefs;
        } else {
            // get the hardcoded defaults
            NSMutableDictionary* dict = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:dict];
            [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
            [aSession setProfile:dict];
            tempPrefs = dict;
        }
    } else {
        tempPrefs = [aSession profile];
    }
    
    int rows = [[tempPrefs objectForKey:KEY_ROWS] intValue];
    int columns = [[tempPrefs objectForKey:KEY_COLUMNS] intValue];
    
    int desiredRows_ = -1;
    int desiredColumns_ = -1;
    
    int nextSessionRows_ = 0;
    int nextSessionColumns_ = 0;
    
    if (desiredRows_ < 0) {
        desiredRows_ = rows;
        desiredColumns_ = columns;
    }
    
    if (nextSessionRows_) {
        rows = nextSessionRows_;
        nextSessionRows_ = 0;
    }
    
    if (nextSessionColumns_) {
        columns = nextSessionColumns_;
        nextSessionColumns_ = 0;
    }
    
    // rows, columns are set to the bookmark defaults. Make sure they'll fit.
    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   verticalSpacing:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    
    if (size == nil) {
        NSSize contentSize = _initialSize;
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }
    
    NSRect sessionRect;
    
    if (size != nil) {
        BOOL hasScrollbar = YES;
        NSSize contentSize =
        [NSScrollView contentSizeForFrameSize:*size
                      horizontalScrollerClass:nil
                        verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                   borderType:NSNoBorder
                                  controlSize:NSControlSizeRegular
                                scrollerStyle:[self scrollerStyle]];
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
        sessionRect.origin = NSZeroPoint;
        sessionRect.size = *size;
    } else {
        sessionRect = NSMakeRect(0, 0, columns * charSize.width + MARGIN * 2, rows * charSize.height + VMARGIN * 2);
    }
    
    if ([aSession setScreenSize:sessionRect parent:self]) {
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        
        [aSession setPreferencesFromAddressBookEntry:tempPrefs];
        [aSession loadInitialColorTable];
        
        // TODO: Still required? API not available anymore
        //[aSession setBookmarkName:[tempPrefs objectForKey:KEY_NAME]];
        
        if (title) {
            // TODO: API not available anymore
            //[aSession setName:title];
            //[aSession setDefaultName:title];
        }
    }
}

- (void)closeSession:(PTYSession *)aSession soft:(BOOL)soft
{
    if (!soft &&
        aSession.isTmuxClient &&
        aSession.tmuxController.isAttached) {
        [aSession.tmuxController killWindowPane:aSession.tmuxPane];
    } else {
        [aSession terminate];
    }
}

#pragma mark PseudoTerminal Stubs

- (BOOL)restoringWindow { return NO; }
- (void)invalidateRestorableState { }
typedef void (^didEnterLionFullscreenBlock)(PseudoTerminal*);
- (didEnterLionFullscreenBlock)didEnterLionFullscreen { return nil; }
- (void)setDidEnterLionFullscreen:(didEnterLionFullscreenBlock)block { }
- (BOOL)togglingLionFullScreen { return NO; }
- (BOOL)windowInitialized { return YES; }
- (BOOL)disablePromptForSubstitutions { return YES; }
+ (void)drawArrangementPreview:(NSDictionary*)terminalArrangement
                  screenFrames:(NSArray *)frames { }
+ (PseudoTerminal*)bareTerminalWithArrangement:(NSDictionary*)arrangement { return nil; }
+ (PseudoTerminal*)terminalWithArrangement:(NSDictionary*)arrangement { return nil; }
+ (instancetype)terminalWithArrangement:(NSDictionary *)arrangement
                               sessions:(NSArray *)sessions { return nil; }
+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement { }
+ (BOOL)willAutoFullScreenNewWindow { return NO; }
+ (BOOL)anyWindowIsEnteringLionFullScreen { return NO; }
+ (BOOL)arrangementIsLionFullScreen:(NSDictionary *)arrangement { return NO; }
- (PTYTab *)tabWithUniqueId:(int)uniqueId { return nil; }
- (void)setFrameValue:(NSValue *)value { }
- (void)canonicalizeWindowFrame { }
- (void)selectSessionAtIndexAction:(id)sender { }
- (void)hideAfterOpening { }
- (void)newSessionInTabAtIndex:(id)sender { }
- (BOOL)hasSavedScrollPosition { return NO; }
- (void)setWindowTitle:(NSString *)title { }
- (void)delayedEnterFullscreen { }
- (void)toggleTraditionalFullScreenMode { }
- (BOOL)tabBarShouldBeVisible { return NO; }
- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)n { return NO; }
- (void)editCurrentSession:(id)sender { }
- (void)irAdvance:(int)dir { }
- (BOOL)promptOnClose { return NO; }
- (iTermToolbeltView *)toolbelt { return nil; }
- (CGFloat)growToolbeltBy:(CGFloat)diff { return 0; }
- (void)refreshTools { }
- (BOOL)isInitialized { return YES; }
- (void)fillPath:(NSBezierPath*)path { }
- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux { }
- (void)showOrHideInstantReplayBar { }
- (void)toggleMaximizeActivePane { }
- (float)minWidth { return 10; }
- (BOOL)loadArrangement:(NSDictionary *)arrangement { return NO; }
- (NSDictionary*)arrangement { return nil; }
- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
                             includingContents:(BOOL)includeContents { return nil; }
- (void)refreshTmuxLayoutsAndWindow { }
- (void)screenParametersDidChange { }
- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session move:(BOOL)move { }
- (void)hideMenuBar { }
- (void)showMenuBar { }
- (void)reloadBookmarks { }
- (IBAction)newTmuxWindow:(id)sender { }
- (IBAction)newTmuxTab:(id)sender { }
- (IBAction)closeCurrentTab:(id)sender { }
- (void)changeTabColorToMenuAction:(id)sender { }
- (void)addRevivedSession:(PTYSession *)session { }
- (void)addTabWithArrangement:(NSDictionary *)arrangement
                     uniqueId:(int)tabUniqueId
                     sessions:(NSArray *)sessions
                 predecessors:(NSArray *)predecessors { }
- (void)recreateTab:(PTYTab *)tab
    withArrangement:(NSDictionary *)arrangement
           sessions:(NSArray *)sessions { }
- (NSColor *)accessoryTextColor { return nil; }

#pragma mark PTYTabDelegate Stubs

- (void)tab:(PTYTab *)tab didChangeProcessingStatus:(BOOL)isProcessing { }
- (void)tab:(PTYTab *)tab didChangeIcon:(NSImage *)icon { }
- (void)tab:(PTYTab *)tab didChangeObjectCount:(NSInteger)objectCount { }
- (void)tab:(PTYTab *)tab didChangeToState:(PTYTabState)newState { }
- (void)tab:(PTYTab *)tab currentLocationDidChange:(NSURL *)location { }
- (void)tabDidChangeTmuxLayout:(PTYTab *)tab { }
- (void)tabKeyLabelsDidChangeForSession:(PTYSession *)session { }
- (void)tabRemoveTab:(PTYTab *)tab { }
- (void)tab:(PTYTab *)tab didSetMetalEnabled:(BOOL)useMetal { }

- (BOOL)tabCanUseMetal:(PTYTab *)tab reason:(out NSString **)reason {
    // iTermLib TODO:
    /* if (_contentView.tabBarControl.flashing) {
        if (reason) {
            *reason = @"the tab bar is temporarily visible.";
            return NO;
        }
    } */
    return YES;
}

- (void)tabSessionDidChangeBackgroundColor:(PTYTab *)tab { }
- (void)sessionBackgroundColorDidChange:(PTYSession *)session { }

- (NSUInteger)sessionPaneNumber:(PTYSession *)session
{
    // Copied
    NSUInteger index = [self.sessions indexOfObject:session];
    if (index == NSNotFound) {
        return self.sessions.count;
    } else {
        // It must have just been added.
        return self.sessions.count - 1;
    }
}

#pragma mark PTYSessionDelegate

- (NSWindowController<iTermWindowController>*)realParentWindow
{
    return (NSWindowController<iTermWindowController>*)self;
}

- (id<WindowControllerInterface>)parentWindow
{
    return self;
}

- (NSArray<PTYSession *> *)sessions
{
    return self.delegate.allPTYSessions;
}

- (void)removeSession:(PTYSession *)aSession
{
    [self.delegate shouldRemovePTYSession:aSession];
}

- (void)closeSession:(PTYSession *)session
{
    // TODO
    [self closeSession:session soft:NO];
}

- (void)setBell:(BOOL)flag
{
    // TODO
}

- (void)sessionDidChangeFontSize:(PTYSession *)session
{
    // TODO
}

- (BOOL)sessionInitiatedResize:(PTYSession *)session width:(int)width height:(int)height
{
    if (session.exited) {
        return NO;
    }
    
    [self safelySetSessionSize:session rows:height columns:width];
    
    return YES;
}

- (void)setActiveSession:(PTYSession*)session
{
    [self performSelectorOnMainThread:@selector(setActiveSessionOnMainThread:) withObject:session waitUntilDone:YES];
}

- (void)setActiveSessionOnMainThread:(PTYSession*)session
{
    self.delegate.activePTYSession = session;
    
    iTermLibSessionController* sessionController = [self.delegate sessionControllerForPTYSession:session];
    
    iTermController.sharedInstance.currentTerminal = (PseudoTerminal*)sessionController;
    
    for (PTYSession* otherSession in self.delegate.allPTYSessions) {
        BOOL shouldFocus = otherSession == session;
        otherSession.focused = shouldFocus;
        
        if (shouldFocus) {
            [otherSession.textview.window makeFirstResponder:otherSession.textview];
        }
        
        [otherSession updateDisplayBecause:@"Set active session"];
        otherSession.textview.needsDisplay = YES;
    }
    
    [NSNotificationCenter.defaultCenter postNotificationName:kCurrentSessionDidChange object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"iTermSessionBecameKey" object:self.currentSession];
}

- (BOOL)sessionIsActiveInTab:(PTYSession *)session
{
    return session == self.delegate.activePTYSession && session.view.window.firstResponder == session.textview;
}

- (void)nameOfSession:(PTYSession *)session didChangeTo:(NSString *)newName
{
    if (!self.delegate ||
        session.exited) {
        return;
    }
    
    [self.delegate nameOfSession:session didChangeTo:newName];
}

#pragma mark PTYSessionDelegate Stubs

- (void)addHiddenLiveView:(SessionView *)hiddenLiveView { }
- (int)tabNumberForItermSessionId { return -1; }
- (BOOL)sessionBelongsToVisibleTab { return YES; }
- (int)tabNumber { return 0; }
- (void)updateLabelAttributes { }
- (void)recheckBlur { }
- (void)nextSession { }
- (void)previousSession { }
- (BOOL)hasMaximizedPane { return NO; }
- (int)number { return 0; }
- (void)sessionSelectContainingTab { }
- (void)addSession:(PTYSession *)self toRestorableSession:(iTermRestorableSession *)restorableSession { }
- (void)unmaximize { }
- (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)horizontalSpacing
           vSpacing:(double)verticalSpacing { }
- (Profile *)tmuxBookmark { return nil; }
- (void)sessionWithTmuxGateway:(PTYSession *)session
       wasNotifiedWindowWithId:(int)windowId
                     renamedTo:(NSString *)newName { }
- (NSScriptObjectSpecifier *)objectSpecifier { return nil; }
- (int)tmuxWindow { return -1; }
- (NSString *)tmuxWindowName { return nil; }
- (BOOL)session:(PTYSession *)session shouldAllowDrag:(id<NSDraggingInfo>)sender { return NO; }
- (BOOL)session:(PTYSession *)session performDragOperation:(id<NSDraggingInfo>)sender { return NO; }
- (BOOL)sessionBelongsToTabWhoseSplitsAreBeingDragged { return NO; }
- (void)sessionDoubleClickOnTitleBar { }

- (void)sessionCurrentDirectoryDidChange:(PTYSession *)session { }
- (void)sessionCurrentHostDidChange:(PTYSession *)session { }
- (void)sessionDidChangeTmuxWindowNameTo:(NSString *)newName { }

- (void)sessionDidClearScrollbackBuffer:(PTYSession *)session { }
- (void)sessionDuplicateTab { }
- (BOOL)sessionShouldAutoClose:(PTYSession *)session { return NO; }
- (iTermVariables *)sessionTabVariables { return nil; }
- (void)sessionUpdateMetalAllowed { }

- (BOOL)sessionIsActiveInSelectedTab:(PTYSession *)session {
    return session == self.delegate.activePTYSession;
}

- (void)sessionKeyLabelsDidChange:(PTYSession *)session { }

- (void)sessionRemoveSession:(PTYSession *)session {
    // iTermLib TODO
    NSLog(@"iTermLib TODO");
}


- (VT100GridSize)sessionTmuxSizeWithProfile:(NSDictionary *)profile {
    // iTermLib TODO
    NSLog(@"iTermLib TODO");
    
    return VT100GridSizeMake(0, 0);
}




























#pragma mark WindowControllerInterface

- (PTYSession *)currentSession
{
    return self.delegate.activePTYSession;
}

- (NSRect)windowFrame
{
    return self.session.view.frame;
}

- (NSScreen*)windowScreen
{
    return self.window.screen;
}

#pragma mark WindowControllerInterface Stubs

- (BOOL)fullScreen { return NO; }
- (BOOL)anyFullScreen { return NO; }
- (void)nextTab:(id)sender { }
- (void)previousTab:(id)sender { }
- (void)updateTabColors { }
- (void)enableBlur:(double)radius { }
- (void)disableBlur { }
- (void)fitWindowToTab:(PTYTab*)tab { }
- (PTYTabView *)tabView { return nil; }
- (void)setWindowTitle { }
- (PTYTab*)currentTab { return nil; }
- (void)closeTab:(PTYTab*)theTab { }
- (void)windowSetFrameTopLeftPoint:(NSPoint)point { }
- (void)windowPerformMiniaturize:(id)sender { }
- (void)windowDeminiaturize:(id)sender { }
- (void)windowOrderFront:(id)sender { }
- (void)windowOrderBack:(id)sender { }
- (BOOL)windowIsMiniaturized { return NO; }
- (NSScrollerStyle)scrollerStyle { return NSScroller.preferredScrollerStyle; }
- (BOOL)scrollbarShouldBeVisible { return ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar]; }
- (void)createDuplicateOfTab:(PTYTab *)theTab { }
- (BOOL)movesWhenDraggedOntoSelf { return NO; }






#pragma mark iTermWindowController

- (NSWindow*)window
{
    return self.session.view.window;
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // TODO
}

- (void)setFrameSize:(NSSize)newSize
{
    // TODO
}

- (NSDate *)lastResizeTime
{
    // TODO
    return nil;
}

- (BroadcastMode)broadcastMode
{
    // TODO
    return BROADCAST_OFF;
}

- (void)sessionDidTerminate:(PTYSession *)session
{
    if (_autocompleteView.delegate == session) {
        _autocompleteView.delegate = nil;
    }
    
    [self.delegate ptySessionDidTerminate:session];
    
    iTermController.sharedInstance.currentTerminal = nil;
    session.delegate = nil;
}

- (NSString *)currentSessionName
{
    return self.delegate.activePTYSession.name;
}

- (void)closeSessionWithConfirmation:(PTYSession *)aSession
{
    // TODO
    [self closeSession:aSession soft:NO];
}

- (void)restartSessionWithConfirmation:(PTYSession *)aSession
{
    // TODO
}

- (void)softCloseSession:(PTYSession *)aSession
{
    // TODO
    [self closeSession:aSession soft:YES];
}

- (NSArray*)allSessions
{
    return self.delegate.allPTYSessions;
}

- (void)sessionWasRemoved
{
    _isTerminated = YES;
}

- (void)makeSessionActive:(PTYSession *)session
{
    if (session.exited) {
        return;
    }
    
    [session takeFocus];
    
    self.delegate.activePTYSession = session;
}

- (BOOL)broadcastInputToSession:(PTYSession *)session
{
    return self.delegate.broadcasting;
}

- (void)toggleBroadcastingInputToSession:(PTYSession *)session
{
    self.delegate.broadcasting = !self.delegate.broadcasting;
}

- (void)sendInputToAllSessions:(NSString *)string
                      encoding:(NSStringEncoding)optionalEncoding
                 forceEncoding:(BOOL)forceEncoding
{
    for (PTYSession *aSession in self.broadcastSessions) {
        if (![aSession isTmuxGateway]) {
            [aSession writeTaskNoBroadcast:string encoding:optionalEncoding forceEncoding:forceEncoding];
        }
    }
}

- (BOOL)sendInputToAllSessions
{
    return self.delegate.broadcasting;
}

- (void)popupWillClose:(iTermPopupWindowController *)popup
{
    if (popup == _autocompleteView) {
        [_autocompleteView autorelease]; _autocompleteView = nil;
    }
}

- (BOOL)useTransparency
{
    NSNumber *transparencey = self.session.profile[KEY_TRANSPARENCY];
    
    return transparencey != nil && transparencey.floatValue > 0.01;
}


#pragma mark iTermWindowController Stubs

- (BOOL)windowIsResizing { return NO; }
- (BOOL)shouldShowToolbelt { return NO; }
- (NSArray*)tabs { return NSArray.array; }
- (id<PTYWindow>)ptyWindow { return nil; }
- (NSString *)terminalGuid { return @""; }
- (void)invalidateRestorableStat { }
- (void)newWindowWithBookmarkGuid:(NSString*)guid { }
- (void)newTabWithBookmarkGuid:(NSString*)guid { }
- (void)incrementBadge { }
- (BOOL)lionFullScreen { return NO; }
- (iTermWindowType)windowType { return WINDOW_TYPE_NORMAL; }
- (NSWindowController<iTermWindowController> *)terminalDraggedFromAnotherWindowAtPoint:(NSPoint)point { return nil; }
- (void)moveSessionToWindow:(id)sender { }
- (IBAction)toggleToolbeltVisibility:(id)sender { }
- (void)toggleFullScreenMode:(id)sender { }
- (void)clearTransientTitle { }
- (BOOL)isShowingTransientTitle { return NO; }
- (void)removeTab:(PTYTab *)aTab { }
- (void)moveTabLeft:(id)sender { }
- (void)moveTabRight:(id)sender { }
- (void)increaseHeight:(id)sender { }
- (void)decreaseHeight:(id)sender { }
- (void)increaseWidth:(id)sender { }
- (void)decreaseWidth:(id)sender { }
- (void)closeTab:(PTYTab *)aTab soft:(BOOL)soft { }
- (PSMTabBarControl*)tabBarControl { return nil; }
- (int)numberOfTabs { return 0; }
- (void)appendTab:(PTYTab*)aTab { }
- (BOOL)fitWindowToTabSize:(NSSize)tabSize { return NO; }
- (NSInteger)indexOfTab:(PTYTab*)aTab { return NSNotFound; }
- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex { }
- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex { }
- (void)fitWindowToTabs { }
- (void)tabActiveSessionDidChange { }
- (PTYTab *)tabForSession:(PTYSession *)session { return nil; }
- (void)setName:(NSString *)theSessionName forSession:(PTYSession*)aSession { }
- (void)editSession:(PTYSession*)session makeKey:(BOOL)makeKey { }
- (void)setDimmingForSessions { }
- (void)selectPaneLeft:(id)sender { }
- (void)selectPaneRight:(id)sender { }
- (void)selectPaneUp:(id)sender { }
- (void)selectPaneDown:(id)sender { }
- (void)toggleUseTransparency:(id)sender { }
- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session { }
- (void)replaySession:(PTYSession *)oldSession { }
- (void)showLiveSession:(PTYSession*)liveSession
              inPlaceOf:(PTYSession*)replaySession { }
- (BOOL)inInstantReplay { return NO; }
- (BOOL)closeInstantReplay:(id)sender orTerminateSession:(BOOL)orTerminateSession { return NO; }
- (void)irPrev:(id)sender { }
- (void)irNext:(id)sender { }
- (void)showHideInstantReplay { }
- (void)replaceSyntheticActiveSessionWithLiveSessionIfNeeded { }
- (NSSize)tmuxCompatibleSize { return NSZeroSize; }
- (void)beginTmuxOriginatedResize { }
- (void)endTmuxOriginatedResize { }
- (void)tmuxTabLayoutDidChange:(BOOL)nontrivialChange { }
- (NSArray *)uniqueTmuxControllers { return nil; }
- (void)loadTmuxLayout:(NSMutableDictionary *)parseTree
                window:(int)window
        tmuxController:(TmuxController *)tmuxController
                  name:(NSString *)name { }
- (PTYSession *)splitVertically:(BOOL)isVertical withBookmarkGuid:(NSString*)guid { return nil; }
- (PTYSession *)splitVertically:(BOOL)isVertical withProfile:(Profile *)profile { return nil; }
- (PTYSession *)splitVertically:(BOOL)isVertical
                   withBookmark:(Profile*)theBookmark
                  targetSession:(PTYSession*)targetSession { return nil; }
- (void)splitVertically:(BOOL)isVertical
                 before:(BOOL)before
          addingSession:(PTYSession*)newSession
          targetSession:(PTYSession*)targetSession
           performSetup:(BOOL)performSetup { }
- (BOOL)canSplitPaneVertically:(BOOL)isVertical withBookmark:(Profile*)theBookmark { return NO; }
- (BOOL)isHotKeyWindow { return NO; }
- (void)sessionHostDidChange:(PTYSession *)session to:(VT100RemoteHost *)host { }
- (void)hideAutoCommandHistoryForSession:(PTYSession *)session { }
- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session { }
- (void)showAutoCommandHistoryForSession:(PTYSession *)session { }
- (BOOL)autoCommandHistoryIsOpenForSession:(PTYSession *)session { return NO; }

- (void)addTabAtAutomaticallyDeterminedLocation:(PTYTab *)tab { }
- (void)currentSessionWordAtCursorDidBecome:(NSString *)word { }
- (BOOL)isFloatingHotKeyWindow { return NO; }
- (iTermRestorableSession *)restorableSessionForSession:(PTYSession *)session { return nil; }
- (void)tabTitleDidChange:(PTYTab *)tab { }
- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session popIfNeeded:(BOOL)popIfNeeded { }
- (void)storeWindowStateInRestorableSession:(iTermRestorableSession *)restorableSession { }
- (void)tabDidClearScrollbackBufferInSession:(PTYSession *)session { }
- (NSString *)undecoratedWindowTitle { return @""; }
- (BOOL)wantsCommandHistoryUpdatesFromSession:(PTYSession *)session { return NO; }

@end
