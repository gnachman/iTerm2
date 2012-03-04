//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "TmuxGateway.h"
#import "TSVParser.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "TmuxWindowOpener.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "RegexKitLite.h"
#import "NSStringITerm.h"
#import "TmuxControllerRegistry.h"
#import "EquivalenceClassSet.h"
#import "TmuxDashboardController.h"
#import "PreferencePanel.h"

NSString *kTmuxControllerSessionsDidChange = @"kTmuxControllerSessionsDidChange";
NSString *kTmuxControllerDetachedNotification = @"kTmuxControllerDetachedNotification";
NSString *kTmuxControllerWindowsChangeNotification = @"kTmuxControllerWindowsChangeNotification";
NSString *kTmuxControllerWindowWasRenamed = @"kTmuxControllerWindowWasRenamed";
NSString *kTmuxControllerWindowDidOpen = @"kTmuxControllerWindowDidOpen";
NSString *kTmuxControllerAttachedSessionDidChange = @"kTmuxControllerAttachedSessionDidChange";
NSString *kTmuxControllerWindowDidClose = @"kTmuxControllerWindowDidClose";

static NSString *kListWindowsFormat = @"\"#{session_name}\t#{window_id}\t"
    "#{window_name}\t"
    "#{window_width}\t#{window_height}\t"
    "#{window_layout}\t"
    "#{?window_active,1,0}\"";

@interface TmuxController (Private)

- (int)windowIdFromString:(NSString *)s;
- (void)retainWindow:(int)window withTab:(PTYTab *)tab;
- (void)releaseWindow:(int)window;
- (void)closeAllPanes;
- (void)windowDidOpen:(NSNumber *)windowIndex;
- (void)listSessions;

@end

@implementation TmuxController

@synthesize gateway = gateway_;
@synthesize windowPositions = windowPositions_;
@synthesize sessionName = sessionName_;
@synthesize sessions = sessions_;

- (id)initWithGateway:(TmuxGateway *)gateway
{
    self = [super init];
    if (self) {
        gateway_ = [gateway retain];
        windowPanes_ = [[NSMutableDictionary alloc] init];
        windows_ = [[NSMutableDictionary alloc] init];
        windowPositions_ = [[NSMutableDictionary alloc] init];
        origins_ = [[NSMutableDictionary alloc] init];
        pendingWindowOpens_ = [[NSMutableSet alloc] init];
		hiddenWindows_ = [[NSMutableSet alloc] init];
        [[TmuxControllerRegistry sharedInstance] setController:self
                                                     forClient:@""];  // Set a proper client name
    }
    return self;
}

- (void)dealloc
{
    [[TmuxControllerRegistry sharedInstance] setController:nil
                                                 forClient:@""];  // Set a proper client name
    [gateway_ release];
    [windowPanes_ release];
    [windows_ release];
    [windowPositions_ release];
    [origins_ release];
    [pendingWindowOpens_ release];
    [affinities_ release];
    [lastSaveAffinityCommand_ release];
	[hiddenWindows_ release];
	[lastOrigins_ release];
    [super dealloc];
}

- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
                 affinities:(NSArray *)affinities
{
    NSNumber *n = [NSNumber numberWithInt:windowIndex];
    if ([pendingWindowOpens_ containsObject:n]) {
        return;
    }
    for (NSString *a in affinities) {
        [affinities_ setValue:a
				 equalToValue:[NSString stringWithInt:windowIndex]];
    }
    [pendingWindowOpens_ addObject:n];
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.windowIndex = windowIndex;
    windowOpener.name = name;
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.maxHistory =
		MAX([[gateway_ delegate] tmuxBookmarkSize].height,
			[[gateway_ delegate] tmuxNumHistoryLinesInBookmark]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    [windowOpener openWindows:YES];
}

- (void)addAffinityBetweenPane:(int)windowPane
                   andTerminal:(PseudoTerminal *)term {
    [affinities_ setValue:[[NSNumber numberWithInt:windowPane] stringValue]
             equalToValue:[term terminalGuid]];
}

- (void)setLayoutInTab:(PTYTab *)tab
                toLayout:(NSString *)layout
{
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.layout = layout;
    windowOpener.maxHistory =
		MAX([[gateway_ delegate] tmuxBookmarkSize].height,
			[[gateway_ delegate] tmuxNumHistoryLinesInBookmark]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.windowIndex = [tab tmuxWindow];
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    [windowOpener updateLayoutInTab:tab];
}

- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid {
    self.sessionName = newSessionName;
    sessionId_ = sessionid;
    [self closeAllPanes];
    [self openWindowsInitial];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerAttachedSessionDidChange
                                                        object:nil];
}

- (void)sessionsChanged
{
    [self listSessions];
}

- (void)sessionRenamedTo:(NSString *)newName
{
    self.sessionName = newName;
}

- (void)windowWasRenamedWithId:(int)wid to:(NSString *)newName
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowWasRenamed
                                                        object:[NSArray arrayWithObjects:
                                                                [NSNumber numberWithInt:wid],
                                                                newName,
                                                                nil]];
}

- (void)windowsChanged
{
    [[NSNotificationCenter defaultCenter]  postNotificationName:kTmuxControllerWindowsChangeNotification
                                                         object:self];
}

- (NSArray *)listWindowFields
{
    return [NSArray arrayWithObjects:@"session_name", @"window_id",
            @"window_name", @"window_width", @"window_height",
            @"window_layout", @"window_active", nil];

}

- (NSArray *)savedAffinitiesForWindow:(int)wid
{
    return [affinities_ valuesEqualTo:[NSString stringWithInt:wid]];
}

- (void)initialListWindowsResponse:(NSString *)response
{
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
	NSMutableArray *windowsToOpen = [NSMutableArray array];
	BOOL haveHidden = NO;
	NSNumber *newWindowAffinity = nil;
	BOOL newWindowsInTabs =
		[[PreferencePanel sharedInstance] openTmuxWindowsIn] == OPEN_TMUX_WINDOWS_IN_TABS;
    for (NSArray *record in doc.records) {
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
		if (hiddenWindows_ && [hiddenWindows_ containsObject:[NSNumber numberWithInt:wid]]) {
			NSLog(@"Don't open window %d because it was saved hidden.", wid);
			haveHidden = YES;
			// Let the user know something is up.
			continue;
		}
		NSNumber *n = [NSNumber numberWithInt:wid];
		if (![affinities_ valuesEqualTo:[n stringValue]] && newWindowsInTabs) {
			// Create an equivalence class of all unrecognied windows to each other.
			if (!newWindowAffinity) {
				newWindowAffinity = n;
			} else {
			  [affinities_ setValue:[n stringValue]
					   equalToValue:[newWindowAffinity stringValue]];
			}
		}
		[windowsToOpen addObject:record];
	}
	if (windowsToOpen.count > [[PreferencePanel sharedInstance] tmuxDashboardLimit]) {
		haveHidden = YES;
		[windowsToOpen removeAllObjects];
	}
	if (haveHidden) {
		[[TmuxDashboardController sharedInstance] showWindow:nil];
		[[[TmuxDashboardController sharedInstance] window] makeKeyAndOrderFront:nil];
	}
	for (NSArray *record in windowsToOpen) {
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        [self openWindowWithIndex:wid
                             name:[doc valueInRecord:record forField:@"window_name"]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]
                       affinities:[self savedAffinitiesForWindow:wid]];
    }
}

- (void)openWindowsInitial
{
	NSSize size = [[gateway_ delegate] tmuxBookmarkSize];
    NSString *setSizeCommand = [NSString stringWithFormat:@"control set-client-size %d,%d",
								   (int)size.width, (int)size.height];
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@", kListWindowsFormat];
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    NSString *getAffinitiesCommand = [NSString stringWithFormat:@"control get-value affinities%d", sessionId_];
    NSString *getOriginsCommand = [NSString stringWithFormat:@"control get-value origins%d", sessionId_];
    NSString *getHiddenWindowsCommand =
		[NSString stringWithFormat:@"control get-value hidden%d", sessionId_];
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:setSizeCommand
                                         responseTarget:nil
									   responseSelector:nil
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:getHiddenWindowsCommand
                                         responseTarget:self
									   responseSelector:@selector(getHiddenWindowsResponse:)
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:getAffinitiesCommand
                                         responseTarget:self
                                       responseSelector:@selector(getAffinitiesResponse:)
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:getOriginsCommand
                                         responseTarget:self
                                       responseSelector:@selector(getOriginsResponse:)
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:listSessionsCommand
                                         responseTarget:self
                                       responseSelector:@selector(listSessionsResponse:)
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:listWindowsCommand
                                         responseTarget:self
                                       responseSelector:@selector(initialListWindowsResponse:)
                                         responseObject:nil],
                         nil];
    [gateway_ sendCommandList:commands];
}

- (NSNumber *)_keyForWindowPane:(int)windowPane
{
    return [NSNumber numberWithInt:windowPane];
}

- (PTYSession *)sessionForWindowPane:(int)windowPane
{
    return [windowPanes_ objectForKey:[self _keyForWindowPane:windowPane]];
}

- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window
{
    [self retainWindow:window withTab:[aSession tab]];
    [windowPanes_ setObject:aSession forKey:[self _keyForWindowPane:windowPane]];
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane
{
    [self releaseWindow:window];
    [windowPanes_ removeObjectForKey:[self _keyForWindowPane:windowPane]];
}

- (PTYTab *)window:(int)window
{
    return [[windows_ objectForKey:[NSNumber numberWithInt:window]] objectAtIndex:0];
}

- (BOOL)isAttached
{
    return !detached_;
}

- (void)requestDetach
{
    [self.gateway detach];
}

- (void)detach
{
    detached_ = YES;
    [self closeAllPanes];
    [gateway_ release];
    gateway_ = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDetachedNotification
                                                        object:self];
}

- (BOOL)windowDidResize:(PseudoTerminal *)term
{
    NSSize size = [term tmuxCompatibleSize];
    if (size.width == 0 || size.height == 0) {
        // After the last session closes a size of 0 is reported.
        return YES;
    }
    if (NSEqualSizes(size, lastSize_)) {
        return NO;
    }
    [self setClientSize:size];
    return YES;
}

- (void)fitLayoutToWindows
{
    if (!windows_.count) {
        return;
    }
    NSSize minSize = NSMakeSize(INFINITY, INFINITY);
    for (id windowKey in windows_) {
        PTYTab *tab = [[windows_ objectForKey:windowKey] objectAtIndex:0];
        NSSize size = [tab maxTmuxSize];
        minSize.width = MIN(minSize.width, size.width);
        minSize.height = MIN(minSize.height, size.height);
    }
    if (minSize.width == 0 || minSize.height == 0) {
        // After the last session closes a size of 0 is reported.
        return;
    }
    if (NSEqualSizes(minSize, lastSize_)) {
        return;
    }
    [self setClientSize:minSize];
}

- (void)setClientSize:(NSSize)size
{
    assert(size.width > 0 && size.height > 0);
    lastSize_ = size;
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommand:[NSString stringWithFormat:@"control set-client-size %d,%d",
						   (int)size.width, (int)size.height]
           responseTarget:self
         responseSelector:@selector(clientSizeChangeResponse:)
           responseObject:nil];
}

- (BOOL)hasOutstandingWindowResize
{
    return numOutstandingWindowResizes_ > 0;
}

- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal
{
    NSString *dir;
    if (wasHorizontal) {
        if (amount > 0) {
            dir = @"R";
        } else {
            dir = @"L";
        }
    } else {
        if (amount > 0) {
            dir = @"D";
        } else {
            dir = @"U";
        }
    }
    NSString *cmdStr = [NSString stringWithFormat:@"resize-pane -%@ -t %%%d %d",
                        dir, wp, abs(amount)];
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommand:cmdStr
           responseTarget:self
         responseSelector:@selector(clientSizeChangeResponse:)
           responseObject:nil];
}

// The splitVertically parameter uses the iTerm2 conventions.
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically
{
    // No need for a callback. We should get a layout-changed message and act on it.
    [gateway_ sendCommand:[NSString stringWithFormat:@"split-window -%@ -t %%%d", splitVertically ? @"h": @"v", wp]
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowInSession:(NSString *)targetSession
       afterWindowWithName:(NSString *)predecessorWindow
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"new-window -a -t \"%@:+\" -PF '#{window_id}'",
                           [targetSession stringByEscapingQuotes]]
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowWithAffinity:(int)windowId
{
    if (windowId >= 0) {
        [gateway_ sendCommand:@"new-window -PF '#{window_id}'"
               responseTarget:self
             responseSelector:@selector(newWindowWithAffinityCreated:affinityWindow:)
               responseObject:[NSString stringWithInt:windowId]];
    } else {
        [gateway_ sendCommand:@"new-window -PF '#{window_id}'"
               responseTarget:self
             responseSelector:@selector(newWindowWithoutAffinityCreated:)
               responseObject:nil];
    }
}

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"move-pane -s %%%d -t %%%d %@%@",
                           srcPane, destPane, splitVertical ? @"-h" : @"-v",
                           addBefore ? @" -b" : @""]
           responseTarget:nil
         responseSelector:nil];
}

- (void)killWindowPane:(int)windowPane
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-pane -t %%%d", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)unlinkWindowWithId:(int)windowId inSession:(NSString *)sessionName
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"unlink-window -k -t \"%@:@%d\"",
                           [sessionName stringByEscapingQuotes],
                           windowId]
           responseTarget:nil
         responseSelector:nil];
}

- (void)renameWindowWithId:(int)windowId inSession:(NSString *)sessionName toName:(NSString *)newName
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"rename-window -t \"%@:@%d\" \"%@\"", sessionName, windowId, newName]
           responseTarget:nil
         responseSelector:nil];
}

- (void)killWindow:(int)window
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-window -t @%d", window]
           responseTarget:nil
         responseSelector:nil];
}

- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint
{
    [windowPositions_ setObject:[NSValue valueWithPoint:screenPoint]
                         forKey:[NSNumber numberWithInt:windowPane]];
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -t %%%d", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -t %%%d", windowPane]
           responseTarget:self
         responseSelector:@selector(windowPaneBrokeOutWithWindowId:setAffinityTo:)
           responseObject:sibling];
}

- (void)windowPaneBrokeOutWithWindowId:(NSString *)windowId
                         setAffinityTo:(NSString *)windowGuid
{
    [affinities_ setValue:windowGuid equalToValue:windowId];
}

- (void)hideWindow:(int)windowId
{
	NSLog(@"hideWindow: Add these window IDS to hidden: %d", windowId);
	[hiddenWindows_ addObject:[NSNumber numberWithInt:windowId]];
	[self saveHiddenWindows];
    PTYTab *theTab = [self window:windowId];
    if (theTab) {
        [[theTab realParentWindow] closeTab:theTab soft:YES];
    }
}

- (void)openWindowWithId:(int)windowId
			  affinities:(NSArray *)affinities
			 intentional:(BOOL)intentional
{
	if (intentional) {
		NSLog(@"open intentional: Remove these window IDS to hidden: %d", windowId);
		[hiddenWindows_ removeObject:[NSNumber numberWithInt:windowId]];
		[self saveHiddenWindows];
	}
    // Get the window's basic info to prep the creation of a TmuxWindowOpener.
    [gateway_ sendCommand:[NSString stringWithFormat:@"display -p -F %@ -t @%d",
                           kListWindowsFormat, windowId]
           responseTarget:self
         responseSelector:@selector(listedWindowsToOpenOne:forWindowIdAndAffinities:)
           responseObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:windowId],
                           affinities,
                           nil]];
}

- (void)openWindowWithId:(int)windowId
			 intentional:(BOOL)intentional
{
	[self openWindowWithId:windowId affinities:[NSArray array] intentional:intentional];
}

- (void)linkWindowId:(int)windowId
           inSession:(NSString *)sessionName
           toSession:(NSString *)targetSession
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"link-window -s \"%@:@%d\" -t \"%@:+\"",
                           sessionName, windowId, targetSession, windowId]
           responseTarget:nil
         responseSelector:nil];
}

// Find a position for any key in panes and remove all entries with keys in panes.
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes
{
    NSValue *pos = nil;
    for (NSNumber *n in panes) {
        pos = [windowPositions_ objectForKey:n];
        if (pos) {
            [[pos retain] autorelease];
            break;
        }
    }
    [windowPositions_ removeObjectsForKeys:panes];
    return pos;
}

- (void)renameSession:(NSString *)oldName to:(NSString *)newName
{
    NSString *renameCommand = [NSString stringWithFormat:@"rename-session -t \"%@\" \"%@\"",
                               [oldName stringByEscapingQuotes],
                               [newName stringByEscapingQuotes]];
    [gateway_ sendCommand:renameCommand responseTarget:nil responseSelector:nil];
}

- (void)killSession:(NSString *)sessionName
{
    NSString *killCommand = [NSString stringWithFormat:@"kill-session -t \"%@\"",
                                [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:killCommand responseTarget:nil responseSelector:nil];
}

- (void)addSessionWithName:(NSString *)sessionName
{
    NSString *attachCommand = [NSString stringWithFormat:@"new-session -s \"%@\"",
                               [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:attachCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)attachToSession:(NSString *)sessionName
{
    NSString *attachCommand = [NSString stringWithFormat:@"attach-session -t \"%@\"",
                             [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:attachCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)listWindowsInSession:(NSString *)sessionName
                      target:(id)target
                    selector:(SEL)selector
                      object:(id)object
{
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@ -t \"%@\"",
                                    kListWindowsFormat, sessionName];
    [gateway_ sendCommand:listWindowsCommand
           responseTarget:self
         responseSelector:@selector(didListWindows:userData:)
           responseObject:[NSArray arrayWithObjects:object,
                           NSStringFromSelector(selector),
                           target,
                           nil]];
}

- (void)saveHiddenWindows
{
	NSString *hidden = [[hiddenWindows_ allObjects] componentsJoinedByString:@","];
	NSString *command = [NSString stringWithFormat:
		@"control set-value hidden%d=%@",
		sessionId_, hidden];
	[gateway_ sendCommand:command
		   responseTarget:nil
		 responseSelector:nil
		   responseObject:nil];
}

- (void)saveWindowOrigins
{
	if (haveOutstandingSaveWindowOrigins_) {
		windowOriginsDirty_ = YES;
		return;
	}
	windowOriginsDirty_ = NO;
    if (pendingWindowOpens_.count) {
        return;
    }
	[self saveAffinities];  // Make sure the equivalence classes are up to date.
	NSMutableArray *maps = [NSMutableArray array];
	for (NSSet *c in [affinities_ classes]) {
		// temp will hold an array of tmux window IDs as strings, excluding
		// placeholders and pty guids.
		NSMutableArray *temp = [NSMutableArray array];
		PTYTab *tab = nil;
		for (NSString *wid in c) {
			if (![wid hasPrefix:@"pty-"] && ![wid hasSuffix:@"_ph"]) {
				if (!tab) {
					tab = [self window:[wid intValue]];
				}
				[temp addObject:wid];
			}
		}
		NSString *windowIds = [temp componentsJoinedByString:@","];
		if (tab) {
			PseudoTerminal *term = [tab realParentWindow];
			NSPoint origin = [[term window] frame].origin;
			[maps addObject:[NSString stringWithFormat:@"%@:%d,%d", windowIds,
				(int)origin.x, (int)origin.y]];
		}
	}
	NSString *enc = [maps componentsJoinedByString:@" "];
	NSString *command = [NSString stringWithFormat:@"control set-value \"origins%d=%@\"",
			 sessionId_, [enc stringByEscapingQuotes]];
	if (!lastOrigins_ || ![command isEqualToString:lastOrigins_]) {
		[lastOrigins_ release];
		lastOrigins_ = [command copy];
		haveOutstandingSaveWindowOrigins_ = YES;
		[gateway_ sendCommand:command
			   responseTarget:self
			 responseSelector:@selector(saveWindowOriginsResponse:)];
	}

}

- (void)saveWindowOriginsResponse:(NSString *)response
{
	haveOutstandingSaveWindowOrigins_ = NO;
	if (windowOriginsDirty_) {
		[self saveWindowOrigins];
	}
}

- (void)saveAffinities
{
    if (pendingWindowOpens_.count) {
        return;
    }
    iTermController *cont = [iTermController sharedInstance];
    NSArray *terminals = [cont terminals];
    NSMutableArray *affinities = [NSMutableArray array];
    for (PseudoTerminal *term in terminals) {
        NSMutableArray *siblings = [NSMutableArray array];
        for (PTYTab *aTab in [term tabs]) {
            if ([aTab isTmuxTab] && [aTab tmuxController] == self) {
                NSString *n = [NSString stringWithFormat:@"%d", (int) [aTab tmuxWindow]];
                [siblings addObject:n];
            }
        }
		if ([term terminalGuid]) {
			[siblings addObject:[term terminalGuid]];
		}
        if (siblings.count > 0) {
            [affinities addObject:[siblings componentsJoinedByString:@","]];
		}
    }
    NSString *arg = [affinities componentsJoinedByString:@" "];
    NSString *command = [NSString stringWithFormat:@"control set-value \"affinities%d=%@\"",
                         sessionId_, [arg stringByEscapingQuotes]];
    if ([command isEqualToString:lastSaveAffinityCommand_]) {
        return;
    }
    [lastSaveAffinityCommand_ release];
    lastSaveAffinityCommand_ = [command retain];
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (PseudoTerminal *)terminalWithGuid:(NSString *)guid
{
	for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
		if ([[term terminalGuid] isEqualToString:guid]) {
			return term;
		}
	}
	return nil;
}

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid
{
    for (NSString *n in [self savedAffinitiesForWindow:wid]) {
		if ([n hasPrefix:@"pty-"]) {
			PseudoTerminal *term = [self terminalWithGuid:n];
			if (term) {
				return term;
			}
		} else if (![n hasSuffix:@"_ph"]) {
			PTYTab *tab = [self window:[n intValue]];
			if (tab) {
				return [tab realParentWindow];
			}
		}
    }
    return nil;
}

- (void)changeWindow:(int)window tabTo:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    if (entry) {
        [entry replaceObjectAtIndex:0
						 withObject:tab];
	}
}

@end

@implementation TmuxController (Private)

- (int)windowIdFromString:(NSString *)s
{
    if (s.length < 2 || [s characterAtIndex:0] != '@') {
        return -1;
    }
    return [[s substringFromIndex:1] intValue];
}

- (void)didListWindows:(NSString *)response userData:(NSArray *)userData
{
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    id object = [userData objectAtIndex:0];
    SEL selector = NSSelectorFromString([userData objectAtIndex:1]);
    id target = [userData objectAtIndex:2];
    [target performSelector:selector withObject:doc withObject:object];
}

- (void)getHiddenWindowsResponse:(NSString *)response
{
	if (response.length == 0) {
		return;
	}
	NSArray *windowIds = [response componentsSeparatedByString:@","];
	[hiddenWindows_ removeAllObjects];
	NSLog(@"getHiddneWindowsResponse: Add these window IDS to hidden: %@", windowIds);
	for (NSString *wid in windowIds) {
		[hiddenWindows_ addObject:[NSNumber numberWithInt:[wid intValue]]];
	}
}

- (void)getAffinitiesResponse:(NSString *)result
{
	// Replace the existing equivalence classes with those defined by the
	// affinity response.
	// For example "1,2,3 4,5,6" has two equivalence classes.
	// 1=2=3 and 4=5=6.
    NSArray *affinities = [result componentsSeparatedByString:@" "];
    [affinities_ release];
    affinities_ = [[EquivalenceClassSet alloc] init];

    for (NSString *affset in affinities) {
        NSArray *siblings = [affset componentsSeparatedByString:@","];
        NSString *exemplar = [siblings lastObject];
		if (siblings.count == 1) {
			// This is a wee hack. If a tmux Window is in a native window with one tab
			// then create an equivalence class containing only (wid, wid+"_ph"). ph=placeholder
			// We'll never see a window id that's negative, but the equivalence
			// class's existance signals not to apply the default mode for
			// unrecognized windows.
			exemplar = [exemplar stringByAppendingString:@"_ph"];
		}
        for (NSString *widString in siblings) {
            if (![widString isEqualToString:exemplar]) {
                [affinities_ setValue:widString
                         equalToValue:exemplar];
            }
        }
    }
}

- (void)getOriginsResponse:(NSString *)result
{
	NSArray *windows = [result componentsSeparatedByString:@" "];
	[origins_ removeAllObjects];
	for (NSString *wstr in windows) {
		NSArray *tuple = [wstr componentsSeparatedByString:@":"];
		if (tuple.count != 2) {
			continue;
		}
		NSString *windowsStr = [tuple objectAtIndex:0];
		NSString *coords = [tuple objectAtIndex:1];
		NSArray *windowIds = [windowsStr componentsSeparatedByString:@","];
		NSArray *xy = [coords componentsSeparatedByString:@","];
		if (xy.count != 2) {
			continue;
		}
		NSPoint origin = NSMakePoint([[xy objectAtIndex:0] intValue],
									 [[xy objectAtIndex:1] intValue]);
		for (NSString *wid in windowIds) {
			[origins_ setObject:[NSValue valueWithPoint:origin]
						 forKey:[NSNumber numberWithInt:[wid intValue]]];
		}
	}
}

- (void)listSessionsResponse:(NSString *)result
{
    self.sessions = [result componentsSeparatedByRegex:@"\n"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsDidChange
                                                        object:self.sessions];
}

- (void)listedWindowsToOpenOne:(NSString *)response forWindowIdAndAffinities:(NSArray *)values
{
    NSNumber *windowId = [values objectAtIndex:0];
    NSArray *affinities = [values objectAtIndex:1];
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for list windows request: %@",
                                         response]];
        return;
    }
    for (NSArray *record in doc.records) {
        NSString *recordWindowId = [doc valueInRecord:record forField:@"window_id"];
        if ([self windowIdFromString:recordWindowId] == [windowId intValue]) {
            [self openWindowWithIndex:[self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]]
                                 name:[doc valueInRecord:record forField:@"window_name"]
                                 size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                                 [[doc valueInRecord:record forField:@"window_height"] intValue])
                               layout:[doc valueInRecord:record forField:@"window_layout"]
                           affinities:affinities];
        }
    }
}

// When an iTerm2 window is resized, a control -s client-size w,h
// command is sent. It responds with new layouts for all the windows in the
// client's session. Update the layouts for the affected tabs.
- (void)clientSizeChangeResponse:(NSString *)response
{
    --numOutstandingWindowResizes_;
    if (numOutstandingWindowResizes_ > 0) {
        return;
    }
    NSArray *layoutStrings = [response componentsSeparatedByString:@"\n"];
    for (NSString *layoutString in layoutStrings) {
        NSArray *components = [layoutString captureComponentsMatchedByRegex:@"^@([0-9]+) (.*)"];
        if ([components count] != 3) {
            NSLog(@"Bogus layout string: \"%@\"", layoutString);
        } else {
            int window = [[components objectAtIndex:1] intValue];
            NSString *layout = [components objectAtIndex:2];
            PTYTab *tab = [self window:window];
            if (tab) {
                [[gateway_ delegate] tmuxUpdateLayoutForWindow:window
                                                        layout:layout];
            }
        }
    }
}

- (void)retainWindow:(int)window withTab:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
	BOOL notify = NO;
    if (entry) {
        NSNumber *refcount = [entry objectAtIndex:1];
        [entry replaceObjectAtIndex:1 withObject:[NSNumber numberWithInt:[refcount intValue] + 1]];
    } else {
        entry = [NSMutableArray arrayWithObjects:tab, [NSNumber numberWithInt:1], nil];
		notify = YES;
    }
    [windows_ setObject:entry forKey:k];
	if (notify) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
															object:nil];
	}
}

- (void)releaseWindow:(int)window
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    NSNumber *refcount = [entry objectAtIndex:1];
    refcount = [NSNumber numberWithInt:[refcount intValue] - 1];
    if ([refcount intValue]) {
        [entry replaceObjectAtIndex:1 withObject:refcount];
        [windows_ setObject:entry forKey:k];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidClose
                                                            object:nil];
        [windows_ removeObjectForKey:k];
    }
}

- (void)newWindowWithoutAffinityCreated:(NSString *)responseStr
{
    [affinities_ removeValue:[NSString stringWithInt:[responseStr intValue]]];
}

- (void)newWindowWithAffinityCreated:(NSString *)responseStr
					  affinityWindow:(NSString  *)affinityWindow
{
    if ([responseStr hasPrefix:@"@"]) {
        [affinities_ setValue:[NSString stringWithInt:[[responseStr substringFromIndex:1] intValue]]
                 equalToValue:affinityWindow];
    } else {
        NSLog(@"Response to new-window doesn't look like a window id: \"%@\"", responseStr);
    }
}

- (void)closeAllPanes
{
    // Close all sessions. Iterate over a copy of windowPanes_ because the loop
    // body modifies it by closing sessions.
    for (NSString *key in [[windowPanes_ copy] autorelease]) {
        PTYSession *session = [windowPanes_ objectForKey:key];
        [[[session tab] realParentWindow] softCloseSession:session];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
}

- (void)listSessions
{
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    [gateway_ sendCommand:listSessionsCommand
           responseTarget:self
         responseSelector:@selector(listSessionsResponse:)];
}

- (void)windowDidOpen:(NSNumber *)windowIndex
{
    [pendingWindowOpens_ removeObject:windowIndex];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                        object:nil];
	PTYTab *tab = [self window:[windowIndex intValue]];
	PseudoTerminal *term = [tab realParentWindow];
	NSValue *p = [origins_ objectForKey:windowIndex];
	if (term && p) {
		[[term window] setFrameOrigin:[p pointValue]];
	}
    [self saveAffinities];
}

@end
