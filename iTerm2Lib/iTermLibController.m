#import "iTermLibController.h"

#import "iTermApplicationDelegate.h"

static iTermLibController* _gSharedController;

@implementation iTermLibController {
    NSMutableArray<iTermLibSessionController*>* _sessions;
    iTermLibSessionController* _activeSession;
    BOOL _broadcasting;
}

+ (instancetype)sharedController
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _gSharedController = [[iTermLibController alloc] init];
    });
    
    return _gSharedController;
}

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        _sessions = [[NSMutableArray array] retain];
        
        [self ensureRunJobsInServerIsInactive];
    }
    
    return self;
}

- (void)dealloc
{
    [_sessions release]; _sessions = nil;
    
    [super dealloc];
}

- (NSArray<iTermLibSessionController *> *)sessions
{
    return [[_sessions copy] autorelease];
}

- (iTermLibSessionController *)activeSession
{
    return _activeSession;
}

- (void)ensureRunJobsInServerIsInactive
{
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    [userDefaults setBool:NO forKey:@"RunJobsInServers"];
    [userDefaults synchronize];
}

- (iTermLibSessionController*)createSessionWithProfile:(Profile*)profile command:(NSString*)command initialSize:(NSSize)initialSize
{
    iTermLibSessionController *session = [[[iTermLibSessionController alloc] initWithProfile:profile command:command initialSize:initialSize] autorelease];
    
    session.delegate = self;
    
    [_sessions addObject:session];
    
    return session;
}

- (iTermLibSessionController*)sessionControllerForPTYSession:(PTYSession*)session
{
    for (iTermLibSessionController *sessionController in self.sessions) {
        if (sessionController.session == session) {
            return sessionController;
        }
    }
    
    return nil;
}

- (BOOL)broadcasting
{
    return _broadcasting;
}

- (void)setBroadcasting:(BOOL)value
{
    _broadcasting = value;
    
    for (iTermLibSessionController* session in self.sessions) {
        session.view.needsDisplay = YES;
    }
}



#pragma mark iTermLibSessionDelegate

- (NSArray<PTYSession *> *)allPTYSessions
{
    NSMutableArray* arr = [NSMutableArray array];
    
    for (iTermLibSessionController *sessionController in self.sessions) {
        [arr addObject:sessionController.session];
    }
    
    return [[arr copy] autorelease];
}

- (PTYSession*)activePTYSession
{
    return self.activeSession.session;
}

- (void)setActivePTYSession:(PTYSession*)session
{
    iTermLibSessionController* sessionController = [self sessionControllerForPTYSession:session];
    
    if (sessionController) {
        _activeSession = sessionController;
    }
}

- (void)ptySessionDidTerminate:(PTYSession*)session
{
    iTermLibSessionController* sessionController = [self sessionControllerForPTYSession:session];
    
    if (sessionController) {
        sessionController.delegate = nil;
        
        if (self.delegate &&
            [self.delegate respondsToSelector:@selector(controller:sessionDidClose:)]) {
            [self.delegate controller:self sessionDidClose:sessionController];
        }
        
        if ([_sessions containsObject:sessionController]) {
            [_sessions removeObject:sessionController];
        }
        
        if (self.activeSession) {
            _activeSession = nil;
        }
    }
}

- (void)shouldRemovePTYSession:(PTYSession *)session
{
    iTermLibSessionController* sessionController = [self sessionControllerForPTYSession:session];
    
    if (sessionController) {
        if (self.delegate) {
            [self.delegate controller:self shouldRemoveSessionView:sessionController];
        }
    }
}

- (void)nameOfSession:(PTYSession *)session didChangeTo:(NSString *)newName
{
    iTermLibSessionController* sessionController = [self sessionControllerForPTYSession:session];
    
    if (sessionController) {
        if (self.delegate &&
            [self.delegate respondsToSelector:@selector(controller:nameOfSession:didChangeTo:)]) {
            [self.delegate controller:self nameOfSession:sessionController didChangeTo:newName];
        }
    }
}










#pragma mark iTermApplicationDelegate

- (PseudoTerminal*)currentTerminal
{
    return (PseudoTerminal*)iTermLibController.sharedController.activeSession;
}

- (NSArray*)terminals
{
    return iTermLibController.sharedController.sessions;
}

#pragma mark iTermApplicationDelegate Stubs

- (BOOL)workspaceSessionActive { return NO; }
- (BOOL)isApplescriptTestApp { return NO; }
- (BOOL)isRunningOnTravis { return NO; }
- (NSString*)markAlertAction { return kMarkAlertActionModalAlert; }
- (BOOL)sparkleRestarting { return NO; }
- (BOOL)useBackgroundPatternIndicator { return NO; }
- (BOOL)warnBeforeMultiLinePaste { return YES; }
- (NSMenu*)bookmarksMenu { return nil; }
- (IBAction)undo:(id)sender { }
- (IBAction)toggleToolbeltTool:(NSMenuItem *)menuItem { }
- (IBAction)toggleFullScreenTabBar:(id)sender { }
- (IBAction)maximizePane:(id)sender { }
- (IBAction)toggleUseTransparency:(id)sender { }
- (IBAction)toggleSecureInput:(id)sender { }
- (IBAction)newWindow:(id)sender { }
- (IBAction)newSessionWithSameProfile:(id)sender { }
- (IBAction)newSession:(id)sender { }
- (IBAction)buildScriptMenu:(id)sender { }
- (IBAction)debugLogging:(id)sender { }
- (IBAction)openQuickly:(id)sender { }
- (void)updateMaximizePaneMenuItem { }
- (void)updateUseTransparencyMenuItem { }
- (IBAction)showAbout:(id)sender { }
- (IBAction)makeDefaultTerminal:(id)sender { }
- (IBAction)unmakeDefaultTerminal:(id)sender { }
- (IBAction)saveWindowArrangement:(id)sender { }
- (IBAction)showPrefWindow:(id)sender { }
- (IBAction)showBookmarkWindow:(id)sender { }
- (IBAction)arrangeHorizontally:(id)sender { }
- (void)reloadMenus: (NSNotification *) aNotification { }
- (void)buildSessionSubmenu: (NSNotification *) aNotification { }
- (void)reloadSessionMenus: (NSNotification *) aNotification { }
- (void)nonTerminalWindowBecameKey: (NSNotification *) aNotification { }
- (IBAction) biggerFont: (id) sender { }
- (IBAction) smallerFont: (id) sender { }
- (IBAction)pasteFaster:(id)sender { }
- (IBAction)pasteSlower:(id)sender { }
- (IBAction)pasteSlowlyFaster:(id)sender { }
- (IBAction)pasteSlowlySlower:(id)sender { }
- (IBAction)toggleMultiLinePasteWarning:(id)sender { }
- (IBAction)returnToDefaultSize:(id)sender { }
- (IBAction)exposeForTabs:(id)sender { }
- (IBAction)editCurrentSession:(id)sender { }
- (IBAction)toggleUseBackgroundPatternIndicator:(id)sender { }
- (void)makeHotKeyWindowKeyIfOpen { }
- (void)updateBroadcastMenuState { }
- (void)userDidInteractWithASession { }
- (NSMenu *)downloadsMenu { return nil; }
- (NSMenu *)uploadsMenu { return nil; }
- (void)openPasswordManagerToAccountName:(NSString *)name inSession:(PTYSession *)session { }

@end
