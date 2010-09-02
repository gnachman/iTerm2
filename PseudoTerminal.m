// -*- mode:objc -*-
// $Id: PseudoTerminal.m,v 1.437 2009-02-06 15:07:23 delx Exp $
//
/*
 **  PseudoTerminal.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **         Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Session and window controller for iTerm.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

// Debug option
#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0

#define WINDOW_NAME @"iTerm Window %d"

#import <iTerm/iTerm.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYScrollView.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/PTYTabView.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/iTermController.h>
#import <iTerm/PTYTask.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/VT100Terminal.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PTToolbarController.h>
#import <iTerm/FindCommandHandler.h>
#import <iTerm/ITAddressBookMgr.h>
#import <PSMTabBarControl.h>
#import <PSMTabStyle.h>
#import <iTerm/iTermGrowlDelegate.h>
#include <unistd.h>

#define CACHED_WINDOW_POSITIONS 100
static BOOL windowPositions[CACHED_WINDOW_POSITIONS];

@interface PSMTabBarControl (Private)
- (void)update;
@end

@interface NSWindow (private)
- (void)setBottomCornerRounded:(BOOL)rounded;
@end

// keys for attributes:
NSString *columnsKey = @"columns";
NSString *rowsKey = @"rows";
// keys for to-many relationships:
NSString *sessionsKey = @"sessions";

#define TABVIEW_TOP_OFFSET                29
#define TABVIEW_BOTTOM_OFFSET            27
#define TABVIEW_LEFT_RIGHT_OFFSET        29
#define TOOLBAR_OFFSET                    0

@implementation FindBarView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor controlColor] setFill];
    NSRectFill(dirtyRect);
}

@end

@implementation PseudoTerminal

// Utility
+ (void) breakDown:(NSString *)cmdl cmdPath: (NSString **) cmd cmdArgs: (NSArray **) path
{
    int i,j,k,qf,slen;
    char tmp[100];
    const char *s;
    NSMutableArray *p;
    
    p=[[NSMutableArray alloc] init];
    
    s=[cmdl UTF8String];
    slen = strlen(s);
    
    i=j=qf=0;
    k=-1;
    while (i<=slen) {
        if (qf) {
            if (s[i]=='\"') {
                qf=0;
            }
            else {
                tmp[j++]=s[i];
            }
        }
        else {
            if (s[i]=='\"') {
                qf=1;
            }
            else if (s[i]==' ' || s[i]=='\t' || s[i]=='\n'||s[i]==0) {
                tmp[j]=0;
                if (k==-1) {
                    *cmd=[NSString stringWithCString:tmp];
                }
                else
                    [p addObject:[NSString stringWithCString:tmp]];
                j=0;
                k++;
                while (i<slen && (s[i+1]==' '||s[i+1]=='\t'||s[i+1]=='\n'||s[i+1]==0)) i++;
            }
            else {
                tmp[j++]=s[i];
            }
        }
        i++;
    }
    
    *path = [NSArray arrayWithArray:p];
    [p release];
}

- (id)initWithWindowNibName: (NSString *) windowNibName
{
    NSSize aSize;
    NSRect aRect;
    unsigned int styleMask;
    PTYWindow *myWindow;
    
    
    if ((self = [super initWithWindowNibName: windowNibName]) == nil)
        return nil;
    
    //enforce the nib to load
    [self window];
    [commandField retain];
    [commandField setDelegate:self];
    [findBar retain];
    
    // create the window programmatically with appropriate style mask
    styleMask = NSTitledWindowMask | 
        NSClosableWindowMask | 
        NSMiniaturizableWindowMask | 
        NSResizableWindowMask;
    
    // set the window style according to preference
    if([[PreferencePanel sharedInstance] windowStyle] == 0)
        styleMask |= NSTexturedBackgroundWindowMask;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    else if([[PreferencePanel sharedInstance] windowStyle] == 2)
        styleMask |= NSUnifiedTitleAndToolbarWindowMask;
#endif
    
    myWindow = [[PTYWindow alloc] initWithContentRect: [[NSScreen mainScreen] frame]
                                            styleMask: styleMask 
                                              backing: NSBackingStoreBuffered 
                                                defer: NO];
    [self setWindow: myWindow];
    [myWindow release];

    _fullScreen = NO;
    previousFindString = [[NSMutableString alloc] init];
    
    // create and set up drawer
    myDrawer = [[NSDrawer alloc] initWithContentSize: NSMakeSize(20, 100) preferredEdge: NSMinXEdge];
    [myDrawer setParentWindow: myWindow];
    [myDrawer setDelegate:self];
    [myWindow setDrawer: myDrawer];
    float aWidth = [[NSUserDefaults standardUserDefaults] floatForKey: @"BookmarksDrawerWidth"];
    if (aWidth<=0) aWidth = 150.0;
    [myDrawer setContentSize: NSMakeSize(aWidth, 0)];
    [myDrawer release];
    
    aSize = [myDrawer contentSize];
    aRect = NSZeroRect;
    aRect.size = aSize;
    
    BookmarkTableView* view = [[BookmarkTableView alloc] initWithFrame:aRect];
    [view setAutoresizesSubviews:YES];
    [view setDelegate:self];
    drawerBookmarks_ = view;
    [myDrawer setContentView:view];
    [view setHidden:NO];
    
    [self _commonInit];
    
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    _resizeInProgressFlag = NO;

    return self;
}

- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;
{
}

- (void)bookmarkTableSelectionWillChange:(id)bookmarkTable
{
}

- (void)bookmarkTableRowSelected:(id)bookmarkTable
{
    NSString* guid = [drawerBookmarks_ selectedGuid];
    if (!guid) {
        return;
    }
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    [[iTermController sharedInstance] launchBookmark:bookmark inTerminal: self];
}

- (id)initWithFullScreenWindowNibName: (NSString *) windowNibName
{
    PTYWindow *myWindow;
    NSScreen *currentScreen = [[[[iTermController sharedInstance] currentTerminal] window]screen];
    if ((self = [super initWithWindowNibName: windowNibName]) == nil)
        return nil;
    //enforce the nib to load
    [self window];
    [commandField retain];
    
    myWindow = [[PTYWindow alloc] initWithContentRect: [currentScreen frame]
                                            styleMask: NSBorderlessWindowMask 
                                              backing: NSBackingStoreBuffered 
                                                defer: NO];
    [myWindow setBackgroundColor:[NSColor blackColor]];
    [self setWindow: myWindow];
    [self hideMenuBar];
    [myWindow release];
    _fullScreen = YES;
    previousFindString = [[NSMutableString alloc] init];
    
    [self _commonInit];
    
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    _resizeInProgressFlag = NO;
    
    return self;
}

- (id)init
{
    self = ([self initWithWindowNibName: @"PseudoTerminal"]);

    return self;
}


// Do not use both initViewWithFrame and initWindow
// initViewWithFrame is mainly meant for embedding a terminal view in a non-iTerm window.
- (PTYTabView*) initViewWithFrame: (NSRect) frame
{
    NSFont *aFont1;
    NSSize contentSize;
    
    // sanity check
    if(TABVIEW != nil)
        return (TABVIEW);
    
    // Create the tabview
    TABVIEW = [[PTYTabView alloc] initWithFrame: frame];
    [TABVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAllowsTruncatedLabels: NO];
    [TABVIEW setControlSize: NSSmallControlSize];
    [TABVIEW setAutoresizesSubviews: YES];
    // Tell us whenever something happens with the tab view
    [TABVIEW setDelegate: self];
    
    aFont1 = FONT;
    if (aFont1 == nil) {
        [self setFont:[NSFont userFixedPitchFontOfSize:0] nafont:[NSFont userFixedPitchFontOfSize:0]];
    }
    
    NSParameterAssert(aFont1 != nil);
    // Calculate the size of the terminal
    contentSize = [NSScrollView contentSizeForFrameSize: [TABVIEW contentRect].size
                                  hasHorizontalScroller: NO
                                    hasVerticalScroller: ![[PreferencePanel sharedInstance] hideScrollbar]
                                             borderType: NSNoBorder];
    
    [self setCharSizeUsingFont: aFont1];
    [self setWidth: (int) ((contentSize.width - MARGIN * 2)/charWidth + 0.1)
            height: (int) ((contentSize.height) /charHeight + 0.1)];
    
    return ([TABVIEW autorelease]);
}

// Do not use both initViewWithFrame and initWindow
- (void)initWindowWithAddressbook:(NSDictionary *)entry;
{
    NSRect aRect;
    // sanity check
    if(TABVIEW != nil)
        return;
    
    if (!_fullScreen) {
        _toolbarController = [[PTToolbarController alloc] initWithPseudoTerminal:self];
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)])
            [[self window] setBottomCornerRounded:NO];
    }
    
    // create the tab bar control
    aRect = [[[self window] contentView] bounds];
    aRect.size.height = 22;
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame: aRect];
    [tabBarControl setAutoresizingMask: (NSViewWidthSizable | NSViewMinYMargin)];
    [[[self window] contentView] addSubview: tabBarControl];
    [tabBarControl release];    

    // Set up findbar

    NSRect fbFrame = [findBarSubview frame];
    findBar = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, fbFrame.size.width, fbFrame.size.height)];
    [findBar addSubview: findBarSubview];
    [findBar setHidden: YES];

    [findBarTextField setDelegate: self];
        
    // create the tabview
    aRect = [[[self window] contentView] bounds];
    if (![findBar isHidden]) {
        aRect.size.height -= [findBar frame].size.height;
    }
    TABVIEW = [[PTYTabView alloc] initWithFrame: aRect];
    [TABVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews: YES];
    [TABVIEW setAllowsTruncatedLabels: NO];
    [TABVIEW setControlSize: NSSmallControlSize];
    [TABVIEW setTabViewType: NSNoTabsNoBorder];
    // Add to the window
    [[[self window] contentView] addSubview: TABVIEW];
    [TABVIEW release];

    [[[self window] contentView] addSubview: findBar];

    // assign tabview and delegates
    [tabBarControl setTabView: TABVIEW];
    [TABVIEW setDelegate: tabBarControl];
    [tabBarControl setDelegate: self];
    [tabBarControl setHideForSingleTab: NO];
    [tabBarControl setHidden:_fullScreen];
    
    // set the style of tabs to match window style
    switch ([[PreferencePanel sharedInstance] windowStyle]) {
        case 0:
            [tabBarControl setStyleNamed:@"Metal"];
            break;
        case 1:
            [tabBarControl setStyleNamed:@"Aqua"];
            break;
        case 2:
            [tabBarControl setStyleNamed:@"Unified"];
            break;
        default:
            [tabBarControl setStyleNamed:@"Adium"];
            break;
    }

    [[[self window] contentView] setAutoresizesSubviews: YES];
    [[self window] setDelegate: self];
        
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_reloadAddressBook:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];    
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTerminal:)
                                                 name: @"iTermRefreshTerminal"
                                               object: nil];    
    
    [self setWindowInited: YES];
    
    if (entry) {
        [self setAntiAlias:[[entry objectForKey:KEY_ANTI_ALIASING] boolValue]];
        [self setBlur: [[entry objectForKey:KEY_BLUR] boolValue]];
        [self setFont: [ITAddressBookMgr fontWithDesc:[entry objectForKey:KEY_NORMAL_FONT]]
               nafont: [ITAddressBookMgr fontWithDesc:[entry objectForKey:KEY_NON_ASCII_FONT]]];
        [self setCharacterSpacingHorizontal:[[entry objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   vertical:[[entry objectForKey:KEY_VERTICAL_SPACING] floatValue]];

         if (_fullScreen) {
            aRect = [TABVIEW frame];
            WIDTH = (int)((aRect.size.width - MARGIN * 2)/charWidth);
            HEIGHT = (int)((aRect.size.height)/charHeight);
        }
        else {
            WIDTH = [[entry objectForKey:KEY_COLUMNS] intValue];
            HEIGHT = [[entry objectForKey:KEY_ROWS] intValue];
        }
    }

    // position the tabview and control
    if (_fullScreen) {
        aRect = [[[self window] contentView] bounds];
        aRect = NSMakeRect(floor((aRect.size.width-WIDTH*charWidth-MARGIN*2)/2),floor((aRect.size.height-charHeight*HEIGHT)/2),WIDTH*charWidth+MARGIN*2, charHeight*HEIGHT);
        [TABVIEW setFrame: aRect];
    }
    else {
        aRect = [tabBarControl frame];
        aRect.origin.x = 0;
        aRect.origin.y = [TABVIEW frame].size.height;
        aRect.size.width = [[[self window] contentView] bounds].size.width;
        [tabBarControl setFrame: aRect];    
        [tabBarControl setSizeCellsToFit:NO];
        [tabBarControl setCellMinWidth:75];
        [tabBarControl setCellOptimumWidth:175];
    }
    
}
- (void)initWindowWithSettingsFrom:(PseudoTerminal *)aPseudoTerminal
{
    NSRect aRect;
    // sanity check
    if(TABVIEW != nil)
        return;

    // Don't try to do smart layout this time
    [(PTYWindow*)[self window] setLayoutDone];

    if (!_fullScreen) {
        _toolbarController = [[PTToolbarController alloc] initWithPseudoTerminal:self];
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)])
            [[self window] setBottomCornerRounded:NO];
    }
    
    // create the tab bar control
    aRect = [[[self window] contentView] bounds];
    aRect.size.height = 22;
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame: aRect];
    [tabBarControl setAutoresizingMask: (NSViewWidthSizable | NSViewMinYMargin)];
    [[[self window] contentView] addSubview: tabBarControl];
    [tabBarControl release];    
    
    // create the tabview
    aRect = [[[self window] contentView] bounds];
    //aRect.size.height -= [tabBarControl frame].size.height;
    TABVIEW = [[PTYTabView alloc] initWithFrame: aRect];
    [TABVIEW setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews: YES];
    [TABVIEW setAllowsTruncatedLabels: NO];
    [TABVIEW setControlSize: NSSmallControlSize];
    [TABVIEW setTabViewType: NSNoTabsNoBorder];
    // Add to the window
    [[[self window] contentView] addSubview: TABVIEW];
    [TABVIEW release];
    
    // assign tabview and delegates
    [tabBarControl setTabView: TABVIEW];
    [TABVIEW setDelegate: tabBarControl];
    [tabBarControl setDelegate: self];
    [tabBarControl setHideForSingleTab: NO];
    [tabBarControl setHidden:_fullScreen];
    
    // set the style of tabs to match window style
    switch ([[PreferencePanel sharedInstance] windowStyle]) {
        case 0:
            [tabBarControl setStyleNamed:@"Metal"];
            break;
        case 1:
            [tabBarControl setStyleNamed:@"Aqua"];
            break;
        case 2:
            [tabBarControl setStyleNamed:@"Unified"];
            break;
        default:
            [tabBarControl setStyleNamed:@"Adium"];
            break;
    }

    NSRect frame = [aPseudoTerminal->findBarSubview frame];
    [findBarSubview setFrame: frame];
    NSRect fbFrame = [findBarSubview frame];
    findBar = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, fbFrame.size.width, fbFrame.size.height)];
 
    [findBar addSubview: findBarSubview];
    [findBar setHidden: [aPseudoTerminal->findBar isHidden]];
    [findBarTextField setDelegate: self];
    [[[self window] contentView] addSubview: findBar];    

    
    [[[self window] contentView] setAutoresizesSubviews: YES];
    [[self window] setDelegate: self];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_reloadAddressBook:)
                                                 name: @"iTermReloadAddressBook"
                                               object: nil];    
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTerminal:)
                                                 name: @"iTermRefreshTerminal"
                                               object: nil];    
    
    [self setWindowInited: YES];
    
    if (aPseudoTerminal) {
        
        [self setAntiAlias: [aPseudoTerminal antiAlias]];
        [self setBlur: [aPseudoTerminal blur]];
        [self setFont: [aPseudoTerminal font] 
               nafont: [aPseudoTerminal nafont]];
        oldFont = [FONT retain];
        oldNAFont = [NAFONT retain];
        fontSizeFollowWindowResize = [aPseudoTerminal fontSizeFollowWindowResize];
        useTransparency = [aPseudoTerminal useTransparency];
        [self setCharacterSpacingHorizontal: [aPseudoTerminal charSpacingHorizontal] 
                                   vertical: [aPseudoTerminal charSpacingVertical]];
        
         if (_fullScreen) {
            // we are entering full screen mode. store the original size
            oldFrame = [[aPseudoTerminal window] frame];
            WIDTH = oldWidth = [aPseudoTerminal width];
            HEIGHT = oldHeight = [aPseudoTerminal height];
            charHorizontalSpacingMultiplier = oldCharHorizontalSpacingMultiplier = [aPseudoTerminal charSpacingHorizontal];
            charVerticalSpacingMultiplier= oldCharVerticalSpacingMultiplier = [aPseudoTerminal charSpacingVertical];
            aRect = [TABVIEW frame];
            if (fontSizeFollowWindowResize) {
                float scale = (aRect.size.height) / HEIGHT / charHeight;
                NSFont *font = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([FONT pointSize] * scale))];
                font = [self _getMaxFont:font height:aRect.size.height lines:HEIGHT];
                
                float height = [layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier;
                
                if (height != charHeight) {
                    //NSLog(@"Old size: %f\t proposed New size:%f\tWindow Height: %f",[FONT pointSize], [font pointSize],frame.size.height);
                    NSFont *nafont = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([NAFONT pointSize] * scale))];
                    nafont = [self _getMaxFont:nafont height:aRect.size.height lines:HEIGHT];
                    
                    [self setFont:font nafont:nafont];
                }
            }
            else {
                WIDTH = (int)((aRect.size.width - MARGIN * 2)/charWidth);
                HEIGHT = (int)((aRect.size.height)/charHeight);
            }
        }
        else {
            if ([aPseudoTerminal fullScreen]) {
                // we are exiting full screen mode. restore the original size.
                _resizeInProgressFlag = YES;
                [[self window] setFrame:[aPseudoTerminal oldFrame] display:NO];
                _resizeInProgressFlag = NO;
                WIDTH = [aPseudoTerminal oldWidth];
                HEIGHT = [aPseudoTerminal oldHeight];
                charHorizontalSpacingMultiplier =[aPseudoTerminal oldCharSpacingHorizontal];
                charVerticalSpacingMultiplier= [aPseudoTerminal oldCharSpacingVertical];
                [self setFont:[aPseudoTerminal oldFont] nafont:[aPseudoTerminal oldNAFont]];
                
            }
            else {
                WIDTH = [aPseudoTerminal width];
                HEIGHT = [aPseudoTerminal height];
            }
        }
    }
    
    // position the tabview and control
    if (_fullScreen) {
        aRect = [[[self window] contentView] bounds];
        aRect = NSMakeRect(floor((aRect.size.width-WIDTH*charWidth-MARGIN*2)/2),floor((aRect.size.height-charHeight*HEIGHT)/2),WIDTH*charWidth+MARGIN*2, charHeight*HEIGHT);
        [TABVIEW setFrame: aRect];
    }
    else {
        aRect = [tabBarControl frame];
        aRect.origin.x = 0;
        aRect.origin.y = [TABVIEW frame].size.height;
        aRect.size.width = [[[self window] contentView] bounds].size.width;
        [tabBarControl setFrame: aRect];    
        [tabBarControl setSizeCellsToFit:NO];
        [tabBarControl setCellMinWidth:75];
        [tabBarControl setCellOptimumWidth:175];
    }
    
}

-  (id) commandField
{
    return commandField;
}


- (void)setupSession:(PTYSession *) aSession
               title:(NSString *)title
{
    NSDictionary *tempPrefs;
    ITAddressBookMgr *bookmarkManager;
        
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setupSession]",
          __FILE__, __LINE__);
#endif
    
    NSParameterAssert(aSession != nil);    
    
    // get our shared managers
    bookmarkManager = [ITAddressBookMgr sharedInstance];    
    
    // Init the rest of the session
    [aSession setParent: self];
    
    // set some default parameters
    if ([aSession addressBookEntry] == nil) {
        // get the default entry
        NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
        [ITAddressBookMgr setDefaultsInBookmark:dict];
        [aSession setAddressBookEntry:dict];
        tempPrefs = dict;
    } else {
        tempPrefs = [aSession addressBookEntry];
    }
    
    if (WIDTH == 0 && HEIGHT == 0) {
        WIDTH = [[tempPrefs objectForKey:KEY_COLUMNS] intValue];
        HEIGHT = [[tempPrefs objectForKey:KEY_ROWS] intValue];
        [self setAntiAlias:[[tempPrefs objectForKey:KEY_ANTI_ALIASING] boolValue]];
        [self setBlur:[[tempPrefs objectForKey:KEY_BLUR] boolValue]];
    }
    if ([aSession initScreen: [TABVIEW contentRect] width:WIDTH height:HEIGHT]) {
        if (FONT == nil)  {
            [self setFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]]
                   nafont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NON_ASCII_FONT]]];
            [self setCharacterSpacingHorizontal:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                       vertical:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];
        }

        [aSession setPreferencesFromAddressBookEntry: tempPrefs];
            
        [[aSession SCREEN] setDisplay:[aSession TEXTVIEW]];
        [[aSession TEXTVIEW] setFont:FONT nafont:NAFONT];
        [[aSession TEXTVIEW] setAntiAlias: antiAlias];
        [[aSession TEXTVIEW] setLineHeight: charHeight];
        [[aSession TEXTVIEW] setLineWidth: WIDTH * charWidth];
        [[aSession TEXTVIEW] setCharWidth: charWidth];
        // NSLog(@"%d,%d",WIDTH,HEIGHT);
            
        [[aSession TERMINAL] setTrace:YES];    // debug vt100 escape sequence decode

        // tell the shell about our size
        [[aSession SHELL] setWidth:WIDTH  height:HEIGHT];

        if (title) 
        {
            [aSession setName: title];
            [aSession setDefaultName: title];
            [self setWindowTitle];
        }
    
    }
    else {
        
        
    };
}

- (void)selectSessionAtIndexAction:(id)sender
{
    [TABVIEW selectTabViewItemAtIndex:[sender tag]];
}

- (void) newSessionInTabAtIndex: (id) sender
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self addNewSession:bookmark];
    }
}

- (void) insertSession: (PTYSession *) aSession atIndex: (int)anIndex
{
    NSTabViewItem *aTabViewItem;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal insertSession: 0x%x atIndex: %d]",
          __FILE__, __LINE__, aSession, index);
#endif    
    
    if(aSession == nil)
        return;
    
    if ([TABVIEW indexOfTabViewItemWithIdentifier: aSession] == NSNotFound)
    {
        // create a new tab
        aTabViewItem = [[NSTabViewItem alloc] initWithIdentifier: aSession];
        [aSession setTabViewItem: aTabViewItem];
        NSParameterAssert(aTabViewItem != nil);
        [aTabViewItem setLabel: [aSession name]];
        [aTabViewItem setView: [aSession view]];
        //[[aSession SCROLLVIEW] setLineScroll: charHeight];
        //[[aSession SCROLLVIEW] setPageScroll: HEIGHT*charHeight/2];
        [TABVIEW insertTabViewItem: aTabViewItem atIndex: anIndex];
        
        [aTabViewItem release];
        [TABVIEW selectTabViewItemAtIndex: anIndex];

        if([self windowInited] && !_fullScreen)
            [[self window] makeKeyAndOrderFront: self];
        [[iTermController sharedInstance] setCurrentTerminal: self];
        [self setWindowSize];
    }
}

- (void) closeSession: (PTYSession*) aSession
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, aSession);
#endif    
    
    NSTabViewItem *aTabViewItem;
    int numberOfSessions;
        
    if([TABVIEW indexOfTabViewItemWithIdentifier: aSession] == NSNotFound)
        return;
    
#if 0
    // TODO(salobaas): Elucidate:
    // The original smart placement patch included this code
    // but it doesn't seem necessary for smart placement, and
    // is redundant with the call to [aSession terminate] ahead
    // (or if there's only one session, it's called in -dealloc)
    if (![aSession exited]) {
        [[aSession SHELL] sendSignal: SIGHUP];
        return;
    }
#endif
   
    numberOfSessions = [TABVIEW numberOfTabViewItems]; 
    if(numberOfSessions == 1 && [self windowInited])
    {   
        [[self window] close];
    }
    else {
         // now get rid of this session
        aTabViewItem = [aSession tabViewItem];
        [aSession terminate];
        [TABVIEW removeTabViewItem: aTabViewItem];
    }
}

- (IBAction) closeCurrentSession: (id) sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal closeCurrentSession]",
          __FILE__, __LINE__);
#endif
    PTYSession *aSession = [[TABVIEW selectedTabViewItem] identifier];
    
    if ([aSession exited] ||        
        ![[PreferencePanel sharedInstance] promptOnClose] || [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
        (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d", [aSession name], [aSession realObjectCount]],
                     NSLocalizedStringFromTableInBundle(@"This session will be closed.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close Session"),
                     NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                     NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                     ,nil) == NSAlertDefaultReturn)) 
        [self closeSession:[[TABVIEW selectedTabViewItem] identifier]];
} 

- (IBAction)previousSession:(id)sender
{
    NSTabViewItem *tvi=[TABVIEW selectedTabViewItem];
    [TABVIEW selectPreviousTabViewItem: sender];
    if (tvi==[TABVIEW selectedTabViewItem]) [TABVIEW selectTabViewItemAtIndex: [TABVIEW numberOfTabViewItems]-1];
}

- (IBAction) nextSession:(id)sender
{
    NSTabViewItem *tvi=[TABVIEW selectedTabViewItem];
    [TABVIEW selectNextTabViewItem: sender];
    if (tvi==[TABVIEW selectedTabViewItem]) [TABVIEW selectTabViewItemAtIndex: 0];
}

- (NSString *) currentSessionName
{
    PTYSession* session = [self currentSession];
    return [session windowTitle] ? [session windowTitle] : [session defaultName];
}

- (int)numberOfSessions
{
    return [TABVIEW numberOfTabViewItems];
}

- (PTYSession*)sessionAtIndex:(int)i
{
    NSTabViewItem* tvi = [TABVIEW tabViewItemAtIndex:i];
    return [tvi identifier];
}

- (void) setCurrentSessionName: (NSString *) theSessionName
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setCurrentSessionName]",
          __FILE__, __LINE__);
#endif
    NSMutableString *title = [NSMutableString string];
    PTYSession *aSession = [[TABVIEW selectedTabViewItem] identifier];
    
    if(theSessionName != nil)
    {
        [aSession setName: theSessionName];
        [aSession setDefaultName: theSessionName];
    }
    else {
        NSString *progpath = [NSString stringWithFormat: @"%@ #%d", [[[[aSession SHELL] path] pathComponents] lastObject], [TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]];
        
        if ([aSession exited])
            [title appendString:@"Finish"];
        else
            [title appendString:progpath];
        
        [aSession setName: title];
        [aSession setDefaultName: title];
        
    }
}

- (void) setFramePos 
{
   // Set framePos to the next unused window position.
   for (int i = 0; i < CACHED_WINDOW_POSITIONS; i++) {
      if (!windowPositions[i]) {
         windowPositions[i] = YES;
         framePos = i;
         return;
      }
   }
   framePos = CACHED_WINDOW_POSITIONS - 1;
}


- (PTYSession *) currentSession
{
    return [[TABVIEW selectedTabViewItem] identifier];
}

- (int) currentSessionIndex
{
    return ([TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]);
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Release all our sessions
    NSTabViewItem *aTabViewItem;
    for(;[TABVIEW numberOfTabViewItems];) 
    {
        aTabViewItem = [TABVIEW tabViewItemAtIndex:0];
        [[aTabViewItem identifier] terminate];
        [TABVIEW removeTabViewItem: aTabViewItem];
    }

    // why isn't drawerBookmarks_ freed
    [commandField release];
    [FONT release];
    [NAFONT release];
    [oldFont release];
    [oldNAFont release];
    [layoutManager release];
    [drawerBookmarks_ release];
    [drawerBookmarks_ setDelegate:nil];
    [findBar release];
    [_toolbarController release];
    if (_timer) {
        [_timer invalidate];
        [findProgressIndicator setHidden:YES];
        _timer = nil;
    }
    
    [super dealloc];
}

- (void)startProgram:(NSString *)program
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal startProgram:%@]",
          __FILE__, __LINE__, program );
#endif
    [[self currentSession] startProgram:program
                                     arguments:[NSArray array]
                                   environment:[NSDictionary dictionary]];
        
}

- (void)startProgram:(NSString *)program arguments:(NSArray *)prog_argv
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal startProgram:%@ arguments:%@]",
          __FILE__, __LINE__, program, prog_argv );
#endif
    [[self currentSession] startProgram:program
                                     arguments:prog_argv
                                   environment:[NSDictionary dictionary]];
        
}

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal startProgram:%@ arguments:%@]",
          __FILE__, __LINE__, program, prog_argv );
#endif
    [[self currentSession] startProgram:program
                                     arguments:prog_argv
                                   environment:prog_env];
    
    if ([[[self window] title] compare:@"Window"]==NSOrderedSame) 
        [self setWindowTitle];

}

- (void) setWidth: (int) width height: (int) height
{
    WIDTH = width;
    HEIGHT = height;
}

- (int)width;
{
    return WIDTH;
}

- (int)height;
{
    return HEIGHT;
}

- (NSRect)oldFrame
{
    return oldFrame;
}

- (int)oldWidth
{
    return oldWidth;
}

- (int)oldHeight;
{
    return oldHeight;
}

- (void)setCharSizeUsingFont:(NSFont *)font
{
    int i;
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];
    NSSize sz;
    [dic setObject:font forKey:NSFontAttributeName];
    sz = [@"W" sizeWithAttributes:dic];
    
    charWidth = ceil(sz.width * charHorizontalSpacingMultiplier);
    charHeight = ([layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier);

    for(i=0;i<[TABVIEW numberOfTabViewItems]; i++) 
    {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex:i] identifier];
        [[session TEXTVIEW] setCharWidth: charWidth];
        [[session TEXTVIEW] setLineHeight: charHeight];
    }
    
    
    [[self window] setResizeIncrements: NSMakeSize(charWidth, charHeight)];
    
}    
- (int)charWidth
{
    return charWidth;
}

- (int)charHeight
{
    return charHeight;
}

- (float) charSpacingHorizontal
{
    return (charHorizontalSpacingMultiplier);
}

- (float) charSpacingVertical
{
    return (charVerticalSpacingMultiplier);
}

- (float) oldCharSpacingVertical
{
    return (oldCharVerticalSpacingMultiplier);
}

- (float) oldCharSpacingHorizontal
{
    return (oldCharHorizontalSpacingMultiplier);
}

- (void)setWindowSize
{    
    [self setWindowSizeWithVisibleFrame:[[[self window] screen] visibleFrame]];
}

- (void) _resizeEverySession: (BOOL) hasScrollbar  {
    // Resize every session.
    int i;
    for (i=0;i<[TABVIEW numberOfTabViewItems];i++) 
    {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [aSession setObjectCount:i+1];
        [[aSession SCREEN] resizeWidth:WIDTH height:HEIGHT];
        [[aSession SHELL] setWidth:WIDTH  height:HEIGHT];
        [[aSession SCROLLVIEW] setLineScroll: [[aSession TEXTVIEW] lineHeight]];
        [[aSession SCROLLVIEW] setPageScroll: 2*[[aSession TEXTVIEW] lineHeight]];
        [[aSession SCROLLVIEW] setHasVerticalScroller:hasScrollbar];
        if ([aSession backgroundImagePath]) [aSession setBackgroundImagePath:[aSession backgroundImagePath]]; 
    }
}

- (void)setWindowSizeWithVisibleFrame: (NSRect)visibleFrame
{
    NSSize size, vsize, winSize, tabViewSize;
    NSWindow *thisWindow = [self window];
    NSRect aRect;
    NSPoint topLeft;
    float max_height;
    BOOL vmargin_added = NO;
    BOOL hasScrollbar = !_fullScreen && ![[PreferencePanel sharedInstance] hideScrollbar];
        
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setWindowSize] (%d,%d)", __FILE__, __LINE__, WIDTH, HEIGHT );
#endif
    
    if([self windowInited] == NO) 
        return;
    
    // This code sets up aRect to be the new size of the window.
    if (!_resizeInProgressFlag) {
        _resizeInProgressFlag = YES;
        if (!_fullScreen) {
            // Get size of window
            aRect = [thisWindow contentRectForFrameRect:visibleFrame];
            if ([TABVIEW numberOfTabViewItems] > 1 || ![[PreferencePanel sharedInstance] hideTab]) {
                // reduce window size by hight of tabview
                aRect.size.height -= [tabBarControl frame].size.height;
            }
            // compute the max number of rows that fits in the remaining space
            if (![findBar isHidden]) {
                // reduce window height by size of findbar
                aRect.size.height -= [findBar frame].size.height;
            }
            max_height = aRect.size.height / charHeight;
            if (max_height < 0) {
                return;
            }
            // clamp size to some minimum
            if (WIDTH<20) WIDTH=20;
            if (HEIGHT<2) HEIGHT=2;
            if (HEIGHT>max_height) HEIGHT=max_height;
            
            // set desired size of textview to enough pixels to fit WIDTH*HEIGHT
            vsize.width = charWidth * WIDTH + MARGIN * 2;
            vsize.height = charHeight * HEIGHT;
            
            // NSLog(@"width=%d,height=%d",[[[_sessionMgr currentSession] SCREEN] width],[[[_sessionMgr currentSession] SCREEN] height]);
            
            // figure out how big the scrollview should be to achieve the desired textview size of vsize.
            size = [PTYScrollView frameSizeForContentSize:vsize
                                    hasHorizontalScroller:NO
                                      hasVerticalScroller:hasScrollbar
                                               borderType:NSNoBorder];
            [thisWindow setShowsResizeIndicator: hasScrollbar];
        #if 0
            NSLog(@"%s: scrollview content size %.1f, %.1f", __PRETTY_FUNCTION__,
                  size.width, size.height);
        #endif
            
            
            // figure out how big the tabview should be to fit the scrollview.
            tabViewSize = [PTYTabView frameSizeForContentSize:size 
                                                  tabViewType:[TABVIEW tabViewType] 
                                                  controlSize:[TABVIEW controlSize]];
        #if 0
            NSLog(@"%s: tabview content size %.1f, %.1f", __PRETTY_FUNCTION__,
                  tabViewSize.width, tabViewSize.height);
        #endif
            
            // desired size of window content
            winSize = tabViewSize;
            if (![findBar isHidden]) {
                winSize.height += [findBar frame].size.height;
            }
            if([TABVIEW numberOfTabViewItems] == 1 && [[PreferencePanel sharedInstance] hideTab])
            {
                // The tabs are not visible at the top of the window. Set aRect appropriately.
                [tabBarControl setHidden: YES];
                aRect.origin.x = 0;
                aRect.origin.y = ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) ? VMARGIN : 0;
                if (![findBar isHidden]) {
                    aRect.origin.y += [findBar frame].size.height;
                }
                aRect.size = tabViewSize;
                [TABVIEW setFrame: aRect];        
                if ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) {
                    winSize.height += VMARGIN;
                    vmargin_added = YES;
                }
            }
            else
            {
                // The tabs are visible at the top of the window.
                [tabBarControl setHidden: NO];
                [tabBarControl setTabLocation: [[PreferencePanel sharedInstance] tabViewType]];
                winSize.height += [tabBarControl frame].size.height;
                if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
                    // setup aRect to make room for the tabs at the top.
                    aRect.origin.x = 0;
                    aRect.origin.y = ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) ? VMARGIN : 0;
                    aRect.size = tabViewSize;
                    if (![findBar isHidden]) {
                        aRect.origin.y += [findBar frame].size.height;
                    }
                    [TABVIEW setFrame: aRect];
                    aRect.origin.y += aRect.size.height;
                    aRect.size.height = [tabBarControl frame].size.height;
                    [tabBarControl setFrame: aRect];
                    if ([findBar isHidden] && [[PreferencePanel sharedInstance] useBorder]) {
                        winSize.height += VMARGIN;
                        vmargin_added = YES;
                    }
                }
                else {
                    // setup aRect to make room for the tabs at the bottom.
                    aRect.origin.x = 0;
                    aRect.origin.y = 0;
                    aRect.size.width = tabViewSize.width;
                    aRect.size.height = [tabBarControl frame].size.height;
                    if (![findBar isHidden]) {
                        aRect.origin.y += [findBar frame].size.height;
                    }
                    [tabBarControl setFrame: aRect];
                    aRect.origin.y = [tabBarControl frame].size.height;
                    if (![findBar isHidden]) {
                        aRect.origin.y += [findBar frame].size.height;
                    }
                    aRect.size.height = tabViewSize.height;
                    //[TABVIEW setAutoresizesSubviews: NO];
                    [TABVIEW setFrame: aRect];
                    //[TABVIEW setAutoresizesSubviews: YES];
                }
            }
            
            // set the style of tabs to match window style
            switch ([[PreferencePanel sharedInstance] windowStyle]) {
                case 0:
                    [tabBarControl setStyleNamed:@"Metal"];
                    break;
                case 1:
                    [tabBarControl setStyleNamed:@"Aqua"];
                    break;
                case 2:
                    [tabBarControl setStyleNamed:@"Unified"];
                    break;
                default:
                    [tabBarControl setStyleNamed:@"Adium"];
                    break;
            }
            
            [tabBarControl setDisableTabClose:[[PreferencePanel sharedInstance] useCompactLabel]];
            [tabBarControl setCellMinWidth: [[PreferencePanel sharedInstance] useCompactLabel]?
                                          [[PreferencePanel sharedInstance] minCompactTabWidth]:
                                          [[PreferencePanel sharedInstance] minTabWidth]];
            [tabBarControl setSizeCellsToFit: [[PreferencePanel sharedInstance] useUnevenTabs]];
            [tabBarControl setCellOptimumWidth:  [[PreferencePanel sharedInstance] optimumTabWidth]];
        #if 0
            NSLog(@"%s: window content size %.1f, %.1f", __PRETTY_FUNCTION__,
                  winSize.width, winSize.height);
        #endif

            [self _resizeEverySession: hasScrollbar];

            // Preserve the top-left corner of the frame.
            aRect = [thisWindow frame];
            topLeft.x = aRect.origin.x;
            topLeft.y = aRect.origin.y + aRect.size.height;
            
            aRect.size.width = winSize.width;
            aRect.size.height = winSize.height;
            NSRect frame = [thisWindow frameRectForContentRect: aRect];
            frame.origin.x = topLeft.x;
            frame.origin.y = topLeft.y - frame.size.height;
            
            [[thisWindow contentView] setAutoresizesSubviews: NO];
            [thisWindow setFrame: frame display:YES];
            [[thisWindow contentView] setAutoresizesSubviews: YES]; 
            
            if (vmargin_added) {
                [[thisWindow contentView] lockFocus];
                [[NSColor windowFrameColor] set];
                NSRectFill(NSMakeRect(0,0,vsize.width,VMARGIN));
                [[thisWindow contentView] unlockFocus];
            }
        }
        else {
            // Full-screen mode.
            aRect = [thisWindow frame];
            WIDTH = (int)((aRect.size.width - MARGIN * 2)/charWidth);
            HEIGHT = (int)((aRect.size.height)/charHeight);
            int yoffset=0;
            if (![findBar isHidden]) {
                int dh = [findBar frame].size.height / charHeight + 1;
                HEIGHT -= dh;
                yoffset = [findBar frame].size.height;
            } else {
                yoffset = floor(aRect.size.height-charHeight*HEIGHT)/2; // screen height minus one half character
            }
            aRect = NSMakeRect(floor((aRect.size.width-WIDTH*charWidth-MARGIN*2)/2),  // screen width minus one half character and a margin
                               yoffset,        
                               WIDTH*charWidth+MARGIN*2,                              // enough width for WIDTH col plus two margins
                               charHeight*HEIGHT);                                    // enough height for HEIGHT rows
            [TABVIEW setFrame: aRect];
            [self _resizeEverySession: hasScrollbar];
        }            
        
        _resizeInProgressFlag = NO;
    }

    // Adjust the position of the findbar to fit properly below the tabview.
    NSRect findBarFrame = [findBar frame];
    findBarFrame.size.width = [TABVIEW frame].size.width;
    findBarFrame.origin.x = [TABVIEW frame].origin.x;
    [findBar setFrame: findBarFrame];
    findBarFrame.size.width += findBarFrame.origin.x;
    findBarFrame.origin.x = 0;
    [findBarSubview setFrame: findBarFrame];
    
    [[[self currentSession] TEXTVIEW] setNeedsDisplay:YES];
    [tabBarControl update];
    
}


- (void)setWindowTitle
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setWindowTitle]",
          __FILE__, __LINE__);
#endif
    [self setWindowTitle: [self currentSessionName]];
}

- (void) setWindowTitle: (NSString *)title
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal setWindowTitle:%@]",
          __FILE__, __LINE__, title);
#endif
    NSParameterAssert([title length] > 0);

    if([self sendInputToAllSessions]) {
        title = [NSString stringWithFormat:@"☛%@", title];
    }

    [[self window] setTitle: title];
}

// increases or dcreases font size
- (void)changeFontSize:(BOOL)increase
{
    float newFontSize;
        
    float asciiFontSize = [[self font] pointSize];
    if(increase == YES)
        newFontSize = [self largerSizeForSize: asciiFontSize];
    else
        newFontSize = [self smallerSizeForSize: asciiFontSize];    
    NSFont *newAsciiFont = [NSFont fontWithName: [[self font] fontName] size: newFontSize];
    
    float nonAsciiFontSize = [[self nafont] pointSize];
    if(increase == YES)
        newFontSize = [self largerSizeForSize: nonAsciiFontSize];
    else
        newFontSize = [self smallerSizeForSize: nonAsciiFontSize];        
    NSFont *newNonAsciiFont = [NSFont fontWithName: [[self nafont] fontName] size: newFontSize];
    
    if(newAsciiFont != nil && newNonAsciiFont != nil)
    {
        [self setFont: newAsciiFont nafont: newNonAsciiFont];        
//        [self resizeWindow: [self width] height: [self height]];

        NSRect frm = [[self window] frame];
        float rh = frm.size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
        float rw = frm.size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
        
        HEIGHT=[self height]?[self height]:(([[[self window] screen] frame].size.height - rh)/charHeight + 0.5);
        WIDTH=[self width]?[self width]:(([[[self window] screen] frame].size.width - rw - MARGIN*2)/charWidth + 0.5); 
        
        // resize the TABVIEW and TEXTVIEW
        [self setWindowSize];
    }
    
    
}

- (float) largerSizeForSize: (float) aSize 
    /*" Given a font size of aSize, return the next larger size.   Uses the 
    same list of font sizes as presented in the font panel. "*/ 
{
    
    if (aSize <= 8.0) return 9.0;
    if (aSize <= 9.0) return 10.0;
    if (aSize <= 10.0) return 11.0;
    if (aSize <= 11.0) return 12.0;
    if (aSize <= 12.0) return 13.0;
    if (aSize <= 13.0) return 14.0;
    if (aSize <= 14.0) return 18.0;
    if (aSize <= 18.0) return 24.0;
    if (aSize <= 24.0) return 36.0;
    if (aSize <= 36.0) return 48.0;
    if (aSize <= 48.0) return 64.0;
    if (aSize <= 64.0) return 72.0;
    if (aSize <= 72.0) return 96.0;
    if (aSize <= 96.0) return 144.0;
    
    // looks odd, but everything reasonable should have been covered above
    return 288.0; 
} 

- (float) smallerSizeForSize: (float) aSize 
    /*" Given a font size of aSize, return the next smaller size.   Uses 
    the same list of font sizes as presented in the font panel. "*/
{
    
    if (aSize >= 288.0) return 144.0;
    if (aSize >= 144.0) return 96.0;
    if (aSize >= 96.0) return 72.0;
    if (aSize >= 72.0) return 64.0;
    if (aSize >= 64.0) return 48.0;
    if (aSize >= 48.0) return 36.0;
    if (aSize >= 36.0) return 24.0;
    if (aSize >= 24.0) return 18.0;
    if (aSize >= 18.0) return 14.0;
    if (aSize >= 14.0) return 13.0;
    if (aSize >= 13.0) return 12.0;
    if (aSize >= 12.0) return 11.0;
    if (aSize >= 11.0) return 10.0;
    if (aSize >= 10.0) return 9.0;
    
    // looks odd, but everything reasonable should have been covered above
    return 8.0; 
} 

- (void) setCharacterSpacingHorizontal: (float) horizontal vertical: (float) vertical
{
    charHorizontalSpacingMultiplier = horizontal;
    charVerticalSpacingMultiplier = vertical;
    [self setCharSizeUsingFont:FONT];
}

- (BOOL) antiAlias
{
    return (antiAlias);
}

- (void) setAntiAlias: (BOOL) bAntiAlias
{
    PTYSession *aSession;
    int i, cnt = [TABVIEW numberOfTabViewItems];
    
    antiAlias = bAntiAlias;
    
    for(i=0; i<cnt; i++)
    {
        aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [[aSession TEXTVIEW] setAntiAlias: antiAlias];
    }
    
    [[[self currentSession] TEXTVIEW] setNeedsDisplay: YES];
    
}

- (BOOL) blur
{
    return (blur);
}

- (void) setBlur: (BOOL) flag
{
    blur = flag;
    if (blur)
        [self enableBlur];
    else
        [self disableBlur];
}

- (void) enableBlur
{
    id window = [self window];
    if (!_fullScreen && nil != window && [window respondsToSelector:@selector(enableBlur)])
        [window enableBlur];
}

- (void) disableBlur
{
    id window = [self window];
    if (!_fullScreen && nil != window && [window respondsToSelector:@selector(disableBlur)])
        [window disableBlur];
}

- (BOOL) tempTitle
{
    return tempTitle;
}

- (void) resetTempTitle
{
    tempTitle = NO;
}

- (BOOL) isResizeInProgress
{
    return _resizeInProgressFlag;
}

- (void)setFont:(NSFont *)font nafont:(NSFont *)nafont
{
    int i;
    
    [FONT autorelease];
    [font retain];
    FONT=font;
    [NAFONT autorelease];
    [nafont retain];
    NAFONT=nafont;
    [self setCharSizeUsingFont:FONT];
    for(i=0;i<[TABVIEW numberOfTabViewItems]; i++) 
    {
        PTYSession* session = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [[session TEXTVIEW] setFont:FONT nafont:NAFONT];
    }

    [[self window] setResizeIncrements: NSMakeSize(charWidth, charHeight)];
}

- (NSFont *) font
{
    return FONT;
}

- (NSFont *)nafont
{
    return NAFONT;
}

- (NSFont *)oldFont
{
    return oldFont;
}

- (NSFont *)oldNAFont
{
    return oldNAFont;
}

- (void)reset:(id)sender
{
    [[[self currentSession] TERMINAL] reset];
}

- (BOOL) useTransparency
{
    return useTransparency;
}

- (void) setUseTransparency: (BOOL) flag
{
    if (_fullScreen) return;

    useTransparency = flag;
    [[self window] setAlphaValue:flag?0.9999:1];
    
    int n = [TABVIEW numberOfTabViewItems];
    int i;
    for(i=0;i<n;i++) {
        [[[[TABVIEW tabViewItemAtIndex:i] identifier] TEXTVIEW] setUseTransparency:flag];
    }
}

- (void)clearBuffer:(id)sender
{
    [[self currentSession] clearBuffer];
}

- (void)clearScrollbackBuffer:(id)sender
{
    [[self currentSession] clearScrollbackBuffer];
}

- (IBAction)logStart:(id)sender
{
    if (![[self currentSession] logging]) [[self currentSession] logStart];
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [self currentSession]];
}

- (IBAction)logStop:(id)sender
{
    if ([[self currentSession] logging]) [[self currentSession] logStop];
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [self currentSession]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL logging = [[self currentSession] logging];
    BOOL result = YES;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal validateMenuItem:%@]",
          __FILE__, __LINE__, item );
#endif
    
    if ([item action] == @selector(logStart:)) {
        result = logging == YES ? NO:YES;
    }
    else if ([item action] == @selector(logStop:)) {
        result = logging == NO ? NO:YES;
    }
    return result;
}

- (void) sendInputToAllSessions: (NSData *) data
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal sendDataToAllSessions:]",
          __FILE__, __LINE__);
#endif
    PTYSession *aSession;
    int i;
    
    int n = [TABVIEW numberOfTabViewItems];    
    for (i=0; i<n; i++)
    {
        aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        
        if (![aSession exited]) [[aSession SHELL] writeTask:data];
        //[[aSession TEXTVIEW] deselect];
    }    
}

- (BOOL) sendInputToAllSessions
{
    return (sendInputToAllSessions);
}

- (void) setSendInputToAllSessions: (BOOL) flag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s", __PRETTY_FUNCTION__);
#endif
    
    sendInputToAllSessions = flag;
    if(flag)
        sendInputToAllSessions = (NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Warning!",@"iTerm", [NSBundle bundleForClass: [self class]], @"Warning"),
                                     NSLocalizedStringFromTableInBundle(@"Keyboard input will be sent to all sessions in this terminal.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Keyboard Input"), 
                                     NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"Profile"), 
                                     NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel"), nil) == NSAlertDefaultReturn);

    if(sendInputToAllSessions) {
        [[self window] setBackgroundColor: [NSColor highlightColor]];
    }
    else {
        [[self window] setBackgroundColor: normalBackgroundColor];
    }
}

- (IBAction) toggleInputToAllSessions: (id) sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal toggleInputToAllSessions:%@]",
          __FILE__, __LINE__, sender);
#endif
    [self setSendInputToAllSessions: ![self sendInputToAllSessions]];
    
    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowBecameKey" object: self userInfo: nil];    
    [self setWindowTitle];
}

- (void)setFontSizeFollowWindowResize:(BOOL)flag
{
    fontSizeFollowWindowResize = flag;
}

- (IBAction)toggleFontSizeFollowWindowResize:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal toggleFontSizeFollowWindowResize:%@]",
          __FILE__, __LINE__, sender);
#endif
    fontSizeFollowWindowResize = !fontSizeFollowWindowResize;
    
    // cause reloading of menus
    [[iTermController sharedInstance] setCurrentTerminal: self];
}

- (BOOL) fontSizeFollowWindowResize
{
    return (fontSizeFollowWindowResize);
}


// NSWindow delegate methods
- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidDeminiaturize:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    [self setBlur: blur];
}

- (BOOL)windowShouldClose:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowShouldClose:%@]",
          __FILE__, __LINE__, aNotification);
#endif
        
    if ([[PreferencePanel sharedInstance] promptOnClose] && (![[PreferencePanel sharedInstance] onlyWhenMoreTabs] || [TABVIEW numberOfTabViewItems] > 1))
        return [self showCloseWindow];
    else
        return (YES);
}

- (void)windowWillClose:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillClose:%@]",
          __FILE__, __LINE__, aNotification);
#endif

    // tabBarControl is holding on to us, so we have to tell it to let go
    [tabBarControl setDelegate: nil];

    [self disableBlur];    
    if (_fullScreen) [NSMenu setMenuBarVisible: YES];

    // Save frame position for last window
    if([[[iTermController sharedInstance] terminals] count] == 1) {
        // Close the findbar because otherwise the wrong size
        // frame is saved.  You wouldn't want the findbar to
        // open automatically anyway.
            if (![findBar isHidden]) {
                [self showHideFindBar];
            }
            if ([[PreferencePanel sharedInstance] smartPlacement]) {
                [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, 0]];
            } else {
                // Save frame position for window
                [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, framePos]];
                windowPositions[framePos] = NO;
            }
    } else {
            if (![[PreferencePanel sharedInstance] smartPlacement]) {
                // Save frame position for window
                [[self window] saveFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, framePos]];
                windowPositions[framePos] = NO;
            }
        }

    [[iTermController sharedInstance] terminalWillClose: self];
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
    //[self disableBlur];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);
#endif
    //[self selectSessionAtIndex: [self currentSessionIndex]];
    [[iTermController sharedInstance] setCurrentTerminal: self];

    if (_fullScreen) [self hideMenuBar];

    if ([NSFontPanel sharedFontPanelExists]) {
        [[NSFontPanel sharedFontPanel] close];
    }
    
    // update the cursor
    [[[self currentSession] TEXTVIEW] updateDirtyRects];
}

- (void) windowDidResignKey: (NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResignKey:%@]",
          __FILE__, __LINE__, aNotification);
#endif

    //[self windowDidResignMain: aNotification];

    if (_fullScreen) { 
        [NSMenu setMenuBarVisible: YES];
    }
    else {
        // update the cursor
        [[[self currentSession] TEXTVIEW] updateDirtyRects];
    }
}

- (void)windowDidResignMain:(NSNotification *)aNotification
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
#endif
//    if (_fullScreen) [self toggleFullScreen: nil];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillResize: proposedFrameSize width = %f; height = %f]",
          __FILE__, __LINE__, proposedFrameSize.width, proposedFrameSize.height);
#endif
    if (sender!=[self window]) {
        NSLog(@"Aha!");
        return proposedFrameSize;
    }
    
    float nch = [sender frame].size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float wch = [sender frame].size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;

    if (fontSizeFollowWindowResize) {
        //scale = defaultFrame.size.height / [sender frame].size.height;
        float scale = (proposedFrameSize.height - nch) / HEIGHT / charHeight;
        NSFont *font = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([FONT pointSize] * scale))];
        font = [self _getMaxFont:font height:proposedFrameSize.height - nch lines:HEIGHT];
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        NSSize sz;
        [dic setObject:font forKey:NSFontAttributeName];
        sz = [@"W" sizeWithAttributes:dic];
        
        proposedFrameSize.height = [layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier * HEIGHT + nch;
        proposedFrameSize.width = sz.width * charHorizontalSpacingMultiplier * WIDTH + wch + MARGIN * 2;
    }
    else {
        int new_height = (proposedFrameSize.height - nch) / charHeight + 0.5;
        int new_width = (proposedFrameSize.width - wch - MARGIN*2) / charWidth + 0.5;
        if (new_height<2) new_height = 2;
        if (new_width<20) new_width = 20;
        proposedFrameSize.height = charHeight * new_height + nch;
        proposedFrameSize.width = charWidth * new_width + wch + MARGIN * 2;
        //NSLog(@"actual height: %f",proposedFrameSize.height);
    }
    
    return (proposedFrameSize);
}

- (void)windowDidResize:(NSNotification *)aNotification
{
    NSRect frame;
    int w, h;
    
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowDidResize: width = %f, height = %f]",
          __FILE__, __LINE__, [[self window] frame].size.width, [[self window] frame].size.height);
#endif
        
//    int tabBarHeight = [tabBarControl isHidden] ? 0 : [tabBarControl frame].size.height;
    frame = [[[self currentSession] SCROLLVIEW] documentVisibleRect];
/*    if (frame.size.height + tabBarHeight > [[[self window] contentView] frame].size.height) {
        frame.size.height = [[[self window] contentView] frame].size.height - tabBarHeight;
    } */
    
#if 0
    NSLog(@"scrollview content size %.1f, %.1f, %.1f, %.1f",
          frame.origin.x, frame.origin.y,
          frame.size.width, frame.size.height);
#endif
    if (fontSizeFollowWindowResize) {
        float scale = (frame.size.height) / HEIGHT / charHeight;
        NSFont *font = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([FONT pointSize] * scale))];
        font = [self _getMaxFont:font height:frame.size.height lines:HEIGHT];
        
        float height = [layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier;

        if (height != charHeight) {
            //NSLog(@"Old size: %f\t proposed New size:%f\tWindow Height: %f",[FONT pointSize], [font pointSize],frame.size.height);
            NSFont *nafont = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([NAFONT pointSize] * scale))];
            nafont = [self _getMaxFont:nafont height:frame.size.height lines:HEIGHT];
            
            [self setFont:font nafont:nafont];
            NSString *aTitle = [NSString stringWithFormat:@"%@ (%.0f)", [self currentSessionName], [font pointSize]];
            [self setWindowTitle: aTitle];
            tempTitle = YES;

        }
        
        WIDTH = (int)((frame.size.width - MARGIN * 2)/charWidth + 0.5);
        HEIGHT = (int)((frame.size.height)/charHeight + 0.5);
        [self setWindowSize];        
    }
    else {        
        w = (int)((frame.size.width - MARGIN * 2)/charWidth);
        h = (int)((frame.size.height)/charHeight);

        if (w<20) w=20;
        if (h<2) h=2;
        if (w!=WIDTH || h!=HEIGHT) {
            WIDTH = w;
            HEIGHT = h;
            // Display the new size in the window title.
            NSString *aTitle = [NSString stringWithFormat:@"%@ (%d,%d)", [self currentSessionName], WIDTH, HEIGHT];
            [self setWindowTitle: aTitle];
            tempTitle = YES;
            [self setWindowSize];
        }
    }    
    
    
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowDidResize" object: self userInfo: nil];    
}

// PTYWindowDelegateProtocol
- (void) windowWillToggleToolbarVisibility: (id) sender
{
}

- (void) windowDidToggleToolbarVisibility: (id) sender
{
    [self setWindowSize];
}

// Bookmarks
- (IBAction) toggleFullScreen: (id) sender
{
    if (!_fullScreen) {
        PseudoTerminal *fullScreenTerminal = [[PseudoTerminal alloc] initWithFullScreenWindowNibName:@"PseudoTerminal"];
        if (fullScreenTerminal) {
            PTYSession *currentSession = [self currentSession];
            
            [fullScreenTerminal initWindowWithSettingsFrom: self];
            [[[fullScreenTerminal window] contentView] lockFocus];
            [[NSColor blackColor] set];
            NSRectFill([[fullScreenTerminal window] frame]);
            [[[fullScreenTerminal window] contentView] unlockFocus];
            
            [[iTermController sharedInstance] addInTerminals: fullScreenTerminal];
            [fullScreenTerminal release];
            
            int n = [TABVIEW numberOfTabViewItems];
            int i;
            NSTabViewItem *aTabViewItem;
            PTYSession *aSession;
            
            fullScreenTerminal->_resizeInProgressFlag = YES;
            for(i=0;i<n;i++) {
                aTabViewItem = [[TABVIEW tabViewItemAtIndex:0] retain];
                aSession = [aTabViewItem identifier];
                
                // remove from our window
                [TABVIEW removeTabViewItem: aTabViewItem];
                
                // add the session to the new terminal
                [fullScreenTerminal insertSession: aSession atIndex: i];
                [[aSession TEXTVIEW] setFont:[fullScreenTerminal font] nafont:[fullScreenTerminal nafont]];
                [[aSession TEXTVIEW] setCharWidth: [fullScreenTerminal charWidth]];
                [[aSession TEXTVIEW] setLineHeight: [fullScreenTerminal charHeight]];
                [[aSession TEXTVIEW] setLineWidth: [fullScreenTerminal width] * [fullScreenTerminal charWidth]];
                [[aSession TEXTVIEW] setUseTransparency: NO];
                
                // release the tabViewItem
                [aTabViewItem release];
            }
            fullScreenTerminal->_resizeInProgressFlag = NO;
            [[fullScreenTerminal tabView] selectTabViewItemWithIdentifier:currentSession];
            [fullScreenTerminal setWindowSize];
            [fullScreenTerminal setWindowTitle];
            [[self window] close];
        }
    }
    else
    {
        PseudoTerminal *normalScreenTerminal = [[PseudoTerminal alloc] initWithWindowNibName: @"PseudoTerminal"];
        if ([[[PreferencePanel sharedInstance] window] isVisible]) [NSMenu setMenuBarVisible: YES];
        if (normalScreenTerminal) {
            PTYSession *currentSession = [self currentSession];
            [normalScreenTerminal initWindowWithSettingsFrom: self];

            [[iTermController sharedInstance] addInTerminals: normalScreenTerminal];
            [normalScreenTerminal release];
            
            int n = [TABVIEW numberOfTabViewItems];
            int i;
            NSTabViewItem *aTabViewItem;
            PTYSession *aSession;
            
            normalScreenTerminal->_resizeInProgressFlag = YES;
            _resizeInProgressFlag = YES;
            for(i=0;i<n;i++) {
                aTabViewItem = [[TABVIEW tabViewItemAtIndex:0] retain];
                aSession = [aTabViewItem identifier];
                
                // remove from our window
                [TABVIEW removeTabViewItem: aTabViewItem];
                
                // add the session to the new terminal
                [normalScreenTerminal insertSession: aSession atIndex: i];
                [[aSession TEXTVIEW] setFont:[normalScreenTerminal font] nafont:[normalScreenTerminal nafont]];
                [[aSession TEXTVIEW] setCharWidth: [normalScreenTerminal charWidth]];
                [[aSession TEXTVIEW] setLineHeight: [normalScreenTerminal charHeight]];
                [[aSession TEXTVIEW] setLineWidth: [normalScreenTerminal width] * [normalScreenTerminal charWidth]];
                [[aSession TEXTVIEW] setUseTransparency: [self useTransparency]];
                
                // release the tabViewItem
                [aTabViewItem release];
            }
            normalScreenTerminal->_resizeInProgressFlag = NO;
            [normalScreenTerminal setWindowSize];
            [[normalScreenTerminal tabView] selectTabViewItemWithIdentifier:currentSession];
            [[self window] close];
        }
    }
}

- (BOOL) fullScreen
{
    return _fullScreen;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal windowWillUseStandardFrame: defaultFramewidth = %f, height = %f]",
          __FILE__, __LINE__, defaultFrame.size.width, defaultFrame.size.height);
#endif
    float scale;
    
    float nch = [sender frame].size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float wch = [sender frame].size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
    
    defaultFrame.origin.x = [sender frame].origin.x;
    
    if (fontSizeFollowWindowResize) {
        scale = (defaultFrame.size.height - nch) / HEIGHT / charHeight;
        NSFont *font = [[NSFontManager sharedFontManager] convertFont:FONT toSize:(int)(([FONT pointSize] * scale))];
        font = [self _getMaxFont:font height:defaultFrame.size.height - nch lines:HEIGHT];
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        NSSize sz;
        [dic setObject:font forKey:NSFontAttributeName];
        sz = [@"W" sizeWithAttributes:dic];
        
        defaultFrame.size.height = [layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier * HEIGHT + nch;
        defaultFrame.size.width = sz.width * charHorizontalSpacingMultiplier * WIDTH + MARGIN*2 + wch;
        defaultFrame.origin.y = [sender frame].origin.y + [sender frame].size.height -  defaultFrame.size.height;
//        NSLog(@"actual height: %f\t (nch=%f) scale: %f\t new font:%f\told:%f",defaultFrame.size.height,nch,scale, [font pointSize], [FONT pointSize]);
    }
    else {
        int new_height = (defaultFrame.size.height - nch) / charHeight;
        int new_width =  (defaultFrame.size.width - wch - MARGIN * 2) /charWidth;
        
        // TODO: If you're holding down shift, go to full screen even if maxVertically==YES
        defaultFrame.size.height = charHeight * new_height + nch;
        defaultFrame.size.width = ([[PreferencePanel sharedInstance] maxVertically] ? [sender frame].size.width : new_width*charWidth+wch+MARGIN*2);
        //NSLog(@"actual width: %f, height: %f",defaultFrame.size.width,defaultFrame.size.height);
    }
        
    return defaultFrame;
}

- (void)windowWillShowInitial
{
    PTYWindow* window = (PTYWindow*)[self window];
    if (([[[iTermController sharedInstance] terminals] count] == 1) ||
        (![[PreferencePanel sharedInstance] smartPlacement])) {
        NSRect frame = [window frame];
        [self setFramePos];
        [window setFrameUsingName: [NSString stringWithFormat: WINDOW_NAME, framePos]];
        frame.origin = [window frame].origin;
        frame.origin.y += [window frame].size.height - frame.size.height;
        [window setFrame:frame display:NO];
    } else {
        [window smartLayout];
    }
}

// Close Window
- (BOOL)showCloseWindow
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal showCloseWindow]", __FILE__, __LINE__);
#endif
        
    return (NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Close Window?",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                            NSLocalizedStringFromTableInBundle(@"All sessions will be closed",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close window"),
                            NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                            NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                            ,nil)==NSAlertDefaultReturn);
}

- (void) resizeWindow:(int) w height:(int)h
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal resizeWindow:%d,%d]",
          __FILE__, __LINE__, w, h);
#endif
    
    // ignore resize request when we are in full screen mode.
    if (_fullScreen) return;
    
    NSRect frm = [[self window] frame];
    float rh = frm.size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float rw = frm.size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
    
    HEIGHT=h?h:(([[[self window] screen] frame].size.height - rh)/charHeight + 0.5);
    WIDTH=w?w:(([[[self window] screen] frame].size.width - rw - MARGIN*2)/charWidth + 0.5); 

    // resize the TABVIEW and TEXTVIEW
    [self setWindowSize];
}

// Resize the window so that the text display area has pixel size of w*h
- (void) resizeWindowToPixelsWidth:(int)w height:(int)h
{
    // ignore resize request when we are in full screen mode.
    if (_fullScreen) return;

    NSRect frm = [[self window] frame];
    float rh = frm.size.height - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.height;
    float rw = frm.size.width - [[[self currentSession] SCROLLVIEW] documentVisibleRect].size.width;
    
    frm.origin.y += frm.size.height;
    if (!h) h= [[[self window] screen] frame].size.height - rh;
    
    int n = (h) / charHeight + 0.5;
    frm.size.height = n*charHeight + rh;
        
    if (!w) w= [[[self window] screen] frame].size.width - rw;
    n = (w - MARGIN*2) / charWidth + 0.5;
    frm.size.width = n*charWidth + rw + MARGIN*2;
    
    frm.origin.y -= frm.size.height; //keep the top left point the same
    
    [[self window] setFrame:frm display:NO];
    [self windowDidResize:nil];
}

// Contextual menu
- (BOOL) suppressContextualMenu
{
    return (suppressContextualMenu);
}

- (void) setSuppressContextualMenu: (BOOL) aBool
{
    suppressContextualMenu = aBool;
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Constructs the context menu for right-clicking on a terminal when
    // right click does not paste.
    unsigned int modflag = 0;
    int nextIndex;
    NSMenuItem *aMenuItem;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal menuForEvent]", __FILE__, __LINE__);
#endif
    
    if(theMenu == nil || suppressContextualMenu)
        return;
    
    modflag = [theEvent modifierFlags];
    
    // Bookmarks
    [theMenu insertItemWithTitle: NSLocalizedStringFromTableInBundle(@"New",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:nil keyEquivalent:@"" atIndex: 0];
    nextIndex = 1;
    
    // Create a menu with a submenu to navigate between tabs if there are more than one
    if([TABVIEW numberOfTabViewItems] > 1)
    {    
        [theMenu insertItemWithTitle: NSLocalizedStringFromTableInBundle(@"Select",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:nil keyEquivalent:@"" atIndex: nextIndex];
        
        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];
        int i;
        
        for (i = 0; i < [TABVIEW numberOfTabViewItems]; i++)
        {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d", [[TABVIEW tabViewItemAtIndex: i] label], i+1]
                                                   action:@selector(selectTab:) keyEquivalent:@""];
            [aMenuItem setRepresentedObject: [[TABVIEW tabViewItemAtIndex: i] identifier]];
            [aMenuItem setTarget: TABVIEW];
            [tabMenu addItem: aMenuItem];
            [aMenuItem release];
        }
        [theMenu setSubmenu: tabMenu forItem: [theMenu itemAtIndex: nextIndex]];
        [tabMenu release];
        nextIndex++;
    }
    
    // Bookmarks
    [theMenu insertItemWithTitle: 
        NSLocalizedStringFromTableInBundle(@"Bookmarks",@"iTerm", [NSBundle bundleForClass: [self class]], @"Bookmarks") 
                          action:@selector(toggleBookmarksView:) keyEquivalent:@"" atIndex: nextIndex++];
    
    // Separator
    [theMenu insertItem:[NSMenuItem separatorItem] atIndex: nextIndex];
    
    // Build the bookmarks menu
    NSMenu *aMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:aMenu 
                                                  target:self 
                                           withShortcuts:NO];
    [aMenu addItem: [NSMenuItem separatorItem]];
    NSMenuItem *tip = [[[NSMenuItem alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Press Option for New Window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Toolbar Item: New") action:@selector(xyz) keyEquivalent: @""] autorelease];
    [tip setKeyEquivalentModifierMask: NSCommandKeyMask];
    [aMenu addItem: tip];
    tip = [[tip copy] autorelease];
    [tip setTitle:NSLocalizedStringFromTableInBundle(@"Open In New Window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Toolbar Item: New")];
    [tip setKeyEquivalentModifierMask: NSCommandKeyMask | NSAlternateKeyMask];
    [tip setAlternate:YES];
    [aMenu addItem: tip];
    
    [theMenu setSubmenu: aMenu forItem: [theMenu itemAtIndex: 0]];
    
    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    // Info
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Info...",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:@selector(showConfigWindow:) keyEquivalent:@""];
    [aMenuItem setTarget: self];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Close current session
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Close",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:@selector(closeCurrentSession:) keyEquivalent:@""];
    [aMenuItem setTarget: self];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];
    
}

// NSTabView
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willSelectTabViewItem]", __FILE__, __LINE__);
#endif
    if (![[self currentSession] exited]) {
        [[self currentSession] resetStatus];
    }
    
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: didSelectTabViewItem]", __FILE__, __LINE__);
#endif
    
    [[tabViewItem identifier] resetStatus];
    [[[tabViewItem identifier] TEXTVIEW] setNeedsDisplay: YES];
    if (_fullScreen) {
        [[[self window] contentView] lockFocus];
        [[NSColor blackColor] set];
        NSRectFill([[self window] frame]);
        [[[self window] contentView] unlockFocus];
    }
    else {
        [[tabViewItem identifier] setLabelAttribute];
        [self setWindowTitle];
    }

    [[self window] makeFirstResponder:[[tabViewItem identifier] TEXTVIEW]];

    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermSessionBecameKey" object: [tabViewItem identifier]];    
}

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willRemoveTabViewItem]", __FILE__, __LINE__);
#endif
}

- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willAddTabViewItem]", __FILE__, __LINE__);
#endif
    
    [self tabView: tabView willInsertTabViewItem: tabViewItem atIndex: [tabView numberOfTabViewItems]];
}

- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex: (int)anIndex
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabView: willInsertTabViewItem: atIndex: %d]", __FILE__, __LINE__, anIndex);
#endif
    [[tabViewItem identifier] setParent: self];
}

- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    PTYSession *aSession = [tabViewItem identifier];
    
    return [aSession exited] ||        
        ![[PreferencePanel sharedInstance] promptOnClose] || [[PreferencePanel sharedInstance] onlyWhenMoreTabs] ||
        (NSRunAlertPanel([NSString stringWithFormat:@"%@ #%d", [aSession name], [aSession realObjectCount]],
                        NSLocalizedStringFromTableInBundle(@"This session will be closed.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Close Session"),
                        NSLocalizedStringFromTableInBundle(@"OK",@"iTerm", [NSBundle bundleForClass: [self class]], @"OK"),
                        NSLocalizedStringFromTableInBundle(@"Cancel",@"iTerm", [NSBundle bundleForClass: [self class]], @"Cancel")
                        ,nil) == NSAlertDefaultReturn);
    
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl
{
    return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl
{
    //NSLog(@"shouldDropTabViewItem: %@ inTabBar: %@", [tabViewItem label], tabBarControl);
    return YES;
}

- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    //NSLog(@"didDropTabViewItem: %@ inTabBar: %@", [tabViewItem label], aTabBarControl);
    PTYSession *aSession = [tabViewItem identifier];
    PseudoTerminal *term = [aTabBarControl delegate];
    
    [[aSession SCREEN] resizeWidth:[term width] height:[term height]];
    [[aSession SHELL] setWidth:[term width]  height:[term height]];
    [[aSession TEXTVIEW] setFont:[term font] nafont:[term nafont]];
    [[aSession TEXTVIEW] setCharWidth: [term charWidth]];
    [[aSession TEXTVIEW] setLineHeight: [term charHeight]];
    [[aSession TEXTVIEW] setUseTransparency: [term useTransparency]];
    [[aSession TEXTVIEW] setLineWidth: [term width] * [term charWidth]];
    if ([[term tabView] numberOfTabViewItems] == 1) [term setWindowSize];

    int i;
    for (i=0;i<[aTabView numberOfTabViewItems];i++) 
    {
        PTYSession *currentSession = [[aTabView tabViewItemAtIndex: i] identifier];
        [currentSession setObjectCount:i+1];
    }        
}

- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem
{
    //NSLog(@"closeWindowForLastTabViewItem: %@", [tabViewItem label]);
    [[self window] close];
}

- (NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem offset:(NSSize *)offset styleMask:(unsigned int *)styleMask
{
    NSImage *viewImage;
    
    if (tabViewItem == [aTabView selectedTabViewItem]) { 
        NSView *textview = [tabViewItem view];
        NSRect tabFrame = [tabBarControl frame];
        int tabHeight = tabFrame.size.height;

        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        contentFrame.size.height += tabHeight;

        // grabs whole tabview image
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

        [textview lockFocus];
        NSBitmapImageRep *tabviewRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:viewRect] autorelease];
        [tabViewImage addRepresentation:tabviewRep];
        [textview unlockFocus];

        [viewImage lockFocus];
        //viewRect.origin.x += 10;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [tabViewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];

        //draw over where the tab bar would usually be
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        //draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[aTabView delegate] style] drawBackgroundInRect:tabFrame];
        [transform invert];
        [transform concat];

        [viewImage unlockFocus];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        }
        else {
            offset->height = viewRect.size.height + 22;
        }
        *styleMask = NSBorderlessWindowMask;
    }
    else {
        NSView *textview = [tabViewItem view];
        NSRect tabFrame = [tabBarControl frame];
        int tabHeight = tabFrame.size.height;
        
        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        contentFrame.size.height += tabHeight;
        
        // grabs whole tabview image
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *textviewImage = [[[NSImage alloc] initWithSize:viewRect.size] autorelease];
        
        [textviewImage setFlipped: YES];
        [textviewImage lockFocus];
        //draw the background flipped, which is actually the right way up
        [[[tabViewItem identifier] TEXTVIEW] drawRect:viewRect];
        [textviewImage unlockFocus];
        
        [viewImage lockFocus];
        //viewRect.origin.x += 10;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [textviewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];
        
        //draw over where the tab bar would usually be
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        //draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        [(id <PSMTabStyle>)[[aTabView delegate] style] drawBackgroundInRect:tabFrame];
        [transform invert];
        [transform concat];
        
        [viewImage unlockFocus];
        
        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        }
        else {
            offset->height = viewRect.size.height + 22;
        }
        *styleMask = NSBorderlessWindowMask;
    }
        
    return viewImage;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
#endif
    
    // check window size in case tabs have to be hidden or shown
    if (([TABVIEW numberOfTabViewItems] == 1) || ([[PreferencePanel sharedInstance] hideTab] && 
        ([TABVIEW numberOfTabViewItems] > 1 && [tabBarControl isHidden])) )
    {
        [self setWindowSize];      
    }
    
    int i;
    for (i=0;i<[TABVIEW numberOfTabViewItems];i++) 
    {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex: i] identifier];
        [aSession setObjectCount:i+1];
    }        
            
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];        
    //[tabBarControl update];
}

- (NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSMenuItem *aMenuItem;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PseudoTerminal tabViewContextualMenu]", __FILE__, __LINE__);
#endif    
    
    NSMenu *theMenu = [[[NSMenu alloc] init] autorelease];
    
    // Create a menu with a submenu to navigate between tabs if there are more than one
    if([TABVIEW numberOfTabViewItems] > 1)
    {    
        int nextIndex = 0;
        int i;
        
        [theMenu insertItemWithTitle: NSLocalizedStringFromTableInBundle(@"Select",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu") action:nil keyEquivalent:@"" atIndex: nextIndex];
        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];
        
        for (i = 0; i < [TABVIEW numberOfTabViewItems]; i++)
        {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d", [[TABVIEW tabViewItemAtIndex: i] label], i+1]
                                                   action:@selector(selectTab:) keyEquivalent:@""];
            [aMenuItem setRepresentedObject: [[TABVIEW tabViewItemAtIndex: i] identifier]];
            [aMenuItem setTarget: TABVIEW];
            [tabMenu addItem: aMenuItem];
            [aMenuItem release];
        }
        [theMenu setSubmenu: tabMenu forItem: [theMenu itemAtIndex: nextIndex]];
        [tabMenu release];
        nextIndex++;
        [theMenu addItem: [NSMenuItem separatorItem]];
   }
    
     
    // add tasks
    aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Close Tab",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context Menu") action:@selector(closeTabContextualMenuAction:) keyEquivalent:@""];
    [aMenuItem setRepresentedObject: tabViewItem];
    [theMenu addItem: aMenuItem];
    [aMenuItem release];
    if([TABVIEW numberOfTabViewItems] > 1)
    {
        aMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Move to new window",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context Menu") action:@selector(moveTabToNewWindowContextualMenuAction:) keyEquivalent:@""];
        [aMenuItem setRepresentedObject: tabViewItem];
        [theMenu addItem: aMenuItem];
        [aMenuItem release];
    }
    
    return theMenu;
}

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point
{
    PseudoTerminal *term;
    PTYSession *aSession = [tabViewItem identifier];
    
    if(aSession == nil)
        return nil;
    
    // create a new terminal window
    term = [[PseudoTerminal alloc] init];
    if(term == nil)
        return nil;
    
    [term initWindowWithSettingsFrom: self];
    
    [[iTermController sharedInstance] addInTerminals: term];
    [term release];
            
    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
        [[term window] setFrameTopLeftPoint:point];
    }
    else {
        [[term window] setFrameOrigin:point];
    }
    
    return [term tabBarControl];
}

- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)aTabViewItem
{
    NSDictionary *ade = [[aTabViewItem identifier] addressBookEntry];
    
    NSString *temp = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Name: %@\nCommand: %@",@"iTerm", [NSBundle bundleForClass: [self class]], @"Tab Tooltips"),
                      [ade objectForKey:KEY_NAME], [ITAddressBookMgr bookmarkCommand:ade]];
    
    return temp;
    
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem
{
    [tabView selectTabViewItem:tabViewItem];
    // TODO(georgen): bring this back
#if 0
    [ITConfigPanelController show];
#endif
}

- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView
{
    Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
    if (!prototype) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        prototype = aDict;
    }
    [self addNewSession:prototype];
}

- (void) setLabelColor: (NSColor *) color forTabViewItem: tabViewItem
{
    [tabBarControl setLabelColor: color forTabViewItem:tabViewItem];
}

- (PSMTabBarControl*) tabBarControl
{
    return tabBarControl;
}

- (PTYTabView *) tabView
{
    return TABVIEW;
}



// closes a tab
- (void) closeTabContextualMenuAction: (id) sender
{
    [self closeSession: [[sender representedObject] identifier]];
}

- (void) closeTabWithIdentifier: (id) identifier
{
    [self closeSession: identifier];
}

// moves a tab with its session to a new window
- (void) moveTabToNewWindowContextualMenuAction: (id) sender
{
    PseudoTerminal *term;
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYSession *aSession = [aTabViewItem identifier];
    
    if(aSession == nil)
        return;
    
    // create a new terminal window
    term = [[PseudoTerminal alloc] init];
    if(term == nil)
        return;
    
    [term initWindowWithAddressbook: [aSession addressBookEntry]];
    
    [[iTermController sharedInstance] addInTerminals: term];
    [term release];
    
    
    // temporarily retain the tabViewItem
    [aTabViewItem retain];
    
    // remove from our window
    [TABVIEW removeTabViewItem: aTabViewItem];
    
    // add the session to the new terminal
    [term insertSession: aSession atIndex: 0];
    [[aSession SCREEN] resizeWidth:[term width] height:[term height]];
    [[aSession SHELL] setWidth:[term width]  height:[term height]];
    [[aSession TEXTVIEW] setFont:[term font] nafont:[term nafont]];
    [[aSession TEXTVIEW] setCharWidth: [term charWidth]];
    [[aSession TEXTVIEW] setLineHeight: [term charHeight]];
    [[aSession TEXTVIEW] setLineWidth: [term width] * [term charWidth]];
    [term setWindowSize];
    
    // release the tabViewItem
    [aTabViewItem release];
}

- (IBAction)closeWindow:(id)sender
{
    [[self window] performClose:sender];
}

- (IBAction)sendCommand:(id)sender
{
    NSString *command = [commandField stringValue];
    
    if (command == nil || [[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@""])
        return;
    
    NSRange range = [command rangeOfString:@"://"];
    if (range.location != NSNotFound) {
        range = [[command substringToIndex:range.location] rangeOfString:@" "];
        if (range.location == NSNotFound) {
            NSURL *url = [NSURL URLWithString: command];
            NSString *urlType = [url scheme];
            id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:urlType];
            
            //NSLog(@"Got the URL:%@\n%@", urlType, bm);
            if (bm) [[iTermController sharedInstance] launchBookmark:bm 
                                                          inTerminal:[[iTermController sharedInstance] currentTerminal] 
                                                             withURL:command];
            else [[NSWorkspace sharedWorkspace] openURL:url];
            
            return;
        }
    }
    [[self currentSession] sendCommand: command];
    [commandField setStringValue:@""];
}

// TODO(georgen): This doesn't affect certain preferences.
// These are hard to fix because they're PseudoTerminal settings and not per-session:
// regular font
// nonascii font
// blur
// anti aliasing
- (void)reloadBookmarks
{
    for (int j = 0; j < [self numberOfSessions]; ++j) {
        PTYSession* session = [self sessionAtIndex:j];
        Bookmark *oldBookmark = [session addressBookEntry];
        NSString* oldName = [oldBookmark objectForKey:KEY_NAME];
        [oldName retain];
        NSString* guid = [oldBookmark objectForKey:KEY_GUID];
        Bookmark* newBookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
        if (!newBookmark) {
            newBookmark = [[BookmarkModel sessionsInstance] bookmarkWithGuid:guid];
        }
        if (newBookmark && newBookmark != oldBookmark) {
            // Same guid but different pointer means it has changed.
            [session setPreferencesFromAddressBookEntry:newBookmark];
            [session setAddressBookEntry:newBookmark];
            if (![[newBookmark objectForKey:KEY_NAME] isEqualToString:oldName]) {
                [session setName:[newBookmark objectForKey:KEY_NAME]];
            }
        }
        [oldName release];
     }         
}

// NSOutlineView delegate methods
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn 
               item:(id)item
{
    return (NO);
}

// Bookmarks
- (IBAction) toggleBookmarksView: (id) sender
{
    if (_fullScreen) return;
    
    [[(PTYWindow *)[self window] drawer] toggle: sender];    
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermWindowBecameKey" object: self userInfo: nil];    
}

- (NSSize)drawerWillResizeContents:(NSDrawer *)sender toSize:(NSSize)contentSize
{
    // save the width to preferences
    [[NSUserDefaults standardUserDefaults] setFloat: contentSize.width forKey: @"BookmarksDrawerWidth"];
    
    return (contentSize);
}

- (IBAction) parameterPanelEnd: (id) sender
{
    [NSApp stopModal];
}

- (void)_continueSearch
{
    // NSLog(@"PseudoTerminal continueSearch");
    BOOL more = NO;
    if ([[[self currentSession] TEXTVIEW] findInProgress]) {
        more = [[[self currentSession] TEXTVIEW] continueFind];
    }
    if (!more) {
        // NSLog(@"invalidating timer");
        [_timer invalidate];
        [findProgressIndicator setHidden:YES];
        _timer = nil;
    }
}

- (void)_newSearch:(BOOL)needTimer
{
    if (needTimer && !_timer) {
        // NSLog(@"creating timer");
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                  target:self 
                                                selector:@selector(_continueSearch) 
                                                userInfo:nil 
                                                 repeats:YES];
        [findProgressIndicator setHidden:NO];
        [findProgressIndicator startAnimation:self];
    } else if (!needTimer && _timer) {
        // NSLog(@"destroying timer");
        // did a search while one was in progress
        [_timer invalidate];
        _timer = nil;
        [findProgressIndicator setHidden:YES];
    }
}

- (IBAction)searchPrevious:(id)sender
{
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findPreviousWithOffset:1]];
}

- (IBAction)searchNext:(id)sender
{
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findNext]];
}

- (void)findWithSelection
{
    FindCommandHandler* fch = [FindCommandHandler sharedInstance];
    [self _newSearch:[fch findWithSelection]];
}

- (IBAction)closeFindBar:(id)sender
{
    if (![findBar isHidden]) {
        [self showHideFindBar];
    }
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextField *field = [aNotification object];
    if (field != findBarTextField) {
        return;
    }

    if ([previousFindString length] == 0) {
        [[[self currentSession] TEXTVIEW] resetFindCursor];
    } else {
        NSRange range =  [[findBarTextField stringValue] rangeOfString:previousFindString];
        if (range.location != 0) {
            [[[self currentSession] TEXTVIEW] resetFindCursor];
        }
    }
    [previousFindString setString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setSearchString:[findBarTextField stringValue]];
    [[FindCommandHandler sharedInstance] setIgnoresCase: [ignoreCase state]];
    [self _newSearch:[[FindCommandHandler sharedInstance] findPreviousWithOffset:0]];
};

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    NSControl *postingObject = [aNotification object]; 
    if (postingObject == findBarTextField) {
        // This is handled elsewhere.
        [previousFindString setString:@""];
        return;
    }
    
    switch (move) {
        case 16: // Return key
            [self sendCommand: nil];
            break;
        case 17: // Tab key
        {
            Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
            if (!prototype) {
                NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
                [ITAddressBookMgr setDefaultsInBookmark:aDict];
                prototype = aDict;
            }
            
            [self addNewSession:prototype
                    withCommand:[commandField stringValue]];
            break;
        }
        default:
            break;
    }
}

- (void) showHideFindBar
{
    BOOL hide = ![findBar isHidden];
    NSObject* firstResponder = [[self window] firstResponder];
    NSText* currentEditor = [findBarTextField currentEditor];
    if (hide && (!currentEditor || currentEditor != firstResponder)) {
        // The bar is visible but doesn't have focus. Just set the focus.
        [[self window] makeFirstResponder:findBarTextField];
        return;
    }
    if (hide && _timer) {
        [_timer invalidate];
        _timer = nil;
        [findProgressIndicator setHidden:YES];
    }
    [findBar setHidden: hide];
    [self setWindowSize];

    // On OS X 10.5.8, the scroll bar and resize indicator are messed up at this point. Resizing the tabview fixes it. This seems to be fixed in 10.6.
    NSRect tvframe = [TABVIEW frame];
    tvframe.size.height += 1;
    [TABVIEW setFrame: tvframe];
    tvframe.size.height -= 1;
    [TABVIEW setFrame: tvframe];
    
    if (!hide) {
        [[self window] makeFirstResponder:findBarTextField];
    } else {
        [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
    }
}


@end

@implementation PseudoTerminal (Private)

- (void) _commonInit
{
    layoutManager = [[NSLayoutManager alloc] init];
    charHorizontalSpacingMultiplier = charVerticalSpacingMultiplier = 1.0;
    [self setUseTransparency: YES];
    normalBackgroundColor = [[self window] backgroundColor];
}

- (NSFont *) _getMaxFont:(NSFont* ) font 
                  height:(float) height
                   lines:(float) lines
{
    float newSize = [font pointSize], newHeight;
    NSFont *newfont=nil;
    
    do {
        newfont = font;
        font = [[NSFontManager sharedFontManager] convertFont:font toSize:newSize];
        newSize++;
        newHeight = [layoutManager defaultLineHeightForFont:font] * charVerticalSpacingMultiplier * lines;
    } while (height >= newHeight);
    
    return newfont;
}

- (void) _reloadAddressBook: (NSNotification *) aNotification
{
    [bookmarksView reloadData];
}

- (void) _refreshTerminal: (NSNotification *) aNotification
{
    [self setWindowSize];
}

- (void) _getSessionParameters: (NSMutableString *) command withName:(NSMutableString *)name
{
    NSRange r1, r2, currentRange;
    
    while (1) {
        currentRange = NSMakeRange(0,[command length]);
        r1 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) break;
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) break;
        
        [parameterName setStringValue: [command substringWithRange:NSMakeRange(r1.location+2, r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet: parameterPanel
           modalForWindow: [self window]
            modalDelegate: self
           didEndSelector: nil
              contextInfo: nil];

        [NSApp runModalForWindow:parameterPanel];
        
        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];

        [name replaceOccurrencesOfString:[command  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[name length])];
        [command replaceOccurrencesOfString:[command  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[command length])];
    }
    
    while (1)
    {
        currentRange = NSMakeRange(0,[name length]);
        r1 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) break;
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) break;
        
        [parameterName setStringValue: [name substringWithRange:NSMakeRange(r1.location+2, r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet: parameterPanel
           modalForWindow: [self window]
            modalDelegate: self
           didEndSelector: nil
              contextInfo: nil];
        
        [NSApp runModalForWindow:parameterPanel];
        
        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];
        
        [name replaceOccurrencesOfString:[name  substringWithRange:NSMakeRange(r1.location, r2.location - r1.location+2)] withString:[parameterValue stringValue] options:NSLiteralSearch range:NSMakeRange(0,[name length])];
    }
    
}

- (void) hideMenuBar
{
    NSScreen* menubarScreen = nil;
    NSScreen* currentScreen = nil;

    if([[NSScreen screens] count] == 0)
        return;

    menubarScreen = [[NSScreen screens] objectAtIndex:0];
    currentScreen = [NSScreen mainScreen];

    if(currentScreen == menubarScreen)
        [NSMenu setMenuBarVisible: NO];
}

@end


@implementation PseudoTerminal (KeyValueCoding)

// accessors for attributes:
-(int)columns
{
    // NSLog(@"PseudoTerminal: -columns");
    return (WIDTH);
}

-(void)setColumns: (int)columns
{
    // NSLog(@"PseudoTerminal: setColumns: %d", columns);
    if(columns > 0)
    {
        WIDTH = columns;
        if([TABVIEW numberOfTabViewItems] > 0) {
            [self setWindowSize];
        }
    }
}

-(int)rows
{
    // NSLog(@"PseudoTerminal: -rows");
    return (HEIGHT);
}

-(void)setRows: (int)rows
{
    // NSLog(@"PseudoTerminal: setRows: %d", rows);
    if(rows > 0)
    {
        HEIGHT = rows;
        if([TABVIEW numberOfTabViewItems] > 0) {
            [self setWindowSize];
        }
    }
}


// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
-(id)valueInSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -valueInSessionsAtIndex: %d", anIndex);
    return ([[TABVIEW tabViewItemAtIndex:anIndex] identifier]);
}

-(NSArray*)sessions
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *sessions = [NSMutableArray arrayWithCapacity: n];
    int i;
    
    for (i= 0; i < n; i++)
    {
        [sessions addObject: [[TABVIEW tabViewItemAtIndex:i] identifier]];
    } 

    return sessions;
}

-(void)setSessions: (NSArray*)sessions {}

-(id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;
    
    if([propertyKey isEqualToString: sessionsKey] == YES)
    {
        PTYSession *aSession;
        
        for (i= 0; i < [TABVIEW numberOfTabViewItems]; i++)
        {
            aSession = [[TABVIEW tabViewItemAtIndex:i] identifier];
            if([[aSession name] isEqualToString: uniqueName] == YES)
                return (aSession);
        }
    }
    
    return result;
}

// The 'uniqueID' argument might be an NSString or an NSNumber.
-(id)valueWithID: (NSString *)uniqueID inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;
    
    if([propertyKey isEqualToString: sessionsKey] == YES)
    {
        PTYSession *aSession;
        
        for (i= 0; i < [TABVIEW numberOfTabViewItems]; i++)
        {
            aSession = [[TABVIEW tabViewItemAtIndex:i] identifier];
            if([[aSession tty] isEqualToString: uniqueID] == YES)
                return (aSession);
        }
    }
    
    return result;
}

-(void)addNewSession:(NSDictionary *) addressbookEntry
{
    NSAssert(addressbookEntry, @"Null address book entry");
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    PTYSession *aSession;
    NSString *oldCWD = nil;
    
    /* Get currently selected tabviewitem */
    if ([self currentSession]) {
        oldCWD = [[[self currentSession] SHELL] getWorkingDirectory];
    }

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        
        // Grab the addressbook command
        cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry]] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        // Get session parameters
        [self _getSessionParameters:cmd withName:name];
        
        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];
        
        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] <= 0) {
            if (oldCWD) {
                pwd = oldCWD;
            } else {
                pwd = NSHomeDirectory();
            }
        }
        NSDictionary *env=[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        
        [self setCurrentSessionName:name];    
        
        // Start the command        
        [self startProgram:cmd arguments:arg environment:env];
    }
    
    [aSession release];
}

-(void)addNewSession:(NSDictionary *) addressbookEntry withURL: (NSString *)url
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
       
        // We process the cmd to insert URL parts
        NSMutableString *cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry]] autorelease];
        NSMutableString *name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        NSURL *urlRep = [NSURL URLWithString: url];
        
        
        // Grab the addressbook command
        [cmd replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];

        // Update the addressbook title
        [name replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        
        // Get remaining session parameters
        [self _getSessionParameters: cmd withName:name];
        
        NSArray *arg;
        NSString *pwd;
        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];
        
        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] <= 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env=[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        
        [self setCurrentSessionName: name];    
        
        // Start the command        
        [self startProgram:cmd arguments:arg environment:env];
    }
    [aSession release];
}

-(void)addNewSession:(NSDictionary *) addressbookEntry withCommand: (NSString *)command
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    PTYSession *aSession;
    
    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession SCREEN] setScrollback:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setAddressBookEntry: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession SCREEN]) {
        
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        
        // Grab the addressbook command
        cmd = [[[NSMutableString alloc] initWithString:command] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        // Get session parameters
        [self _getSessionParameters: cmd withName:name];
        
        [PseudoTerminal breakDown:cmd cmdPath:&cmd cmdArgs:&arg];
        
        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry];
        if ([pwd length] <= 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env=[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        
        [self setCurrentSessionName:name];    
        
        // Start the command        
        [self startProgram:cmd arguments:arg environment:env];
    }
    
    [aSession release];
}

-(void)appendSession:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -appendSession: 0x%x", object);
    [self setupSession: object title: nil];
    if ([object SCREEN]) // screen initialized ok
        [self insertSession: object atIndex:[TABVIEW numberOfTabViewItems]];
    else {
    
    }
}

-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -replaceInSessions: 0x%x atIndex: %d", object, anIndex);
    NSLog(@"Replace Sessions: not implemented.");
}

-(void)addInSessions:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -addInSessions: 0x%x", object);
    [self insertInSessions: object];
}

-(void)insertInSessions:(PTYSession *)object
{
    // NSLog(@"PseudoTerminal: -insertInSessions: 0x%x", object);
    [self insertInSessions: object atIndex:[TABVIEW numberOfTabViewItems]];
}

-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -insertInSessions: 0x%x atIndex: %d", object, anIndex);
    [self setupSession: object title: nil];
    if ([object SCREEN]) // screen initialized ok
        [self insertSession: object atIndex: anIndex];
    else {
        
        
    }
}

-(void)removeFromSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -removeFromSessionsAtIndex: %d", anIndex);
    if(anIndex < [TABVIEW numberOfTabViewItems])
    {
        PTYSession *aSession = [[TABVIEW tabViewItemAtIndex:anIndex] identifier];
        [self closeSession: aSession];
    }
}

- (BOOL)windowInited
{
    return (windowInited);
}

- (void) setWindowInited: (BOOL) flag
{
    windowInited = flag;
}


// a class method to provide the keys for KVC:
+(NSArray*)kvcKeys
{
    static NSArray *_kvcKeys = nil;
    if( nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            columnsKey, rowsKey, sessionsKey,  nil ];
    }
    return _kvcKeys;
}

@end

@implementation PseudoTerminal (ScriptingSupport)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger anIndex = 0;
    id classDescription = nil;
    
    NSScriptObjectSpecifier *containerRef;
    
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    anIndex = [terminals indexOfObjectIdenticalTo:self];
    if (anIndex != NSNotFound) {
        containerRef     = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        //create and return the specifier
        return [[[NSIndexSpecifier allocWithZone:[self zone]]
               initWithContainerClassDescription: classDescription
                              containerSpecifier: containerRef
                                             key: @ "terminals"
                                           index: anIndex] autorelease];
    } 
    else
        return nil;
}

// Handlers for supported commands:

-(void)handleSelectScriptCommand: (NSScriptCommand *)command
{
    [[iTermController sharedInstance] setCurrentTerminal: self];
}

-(void)handleLaunchScriptCommand: (NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *session = [args objectForKey:@"session"];
    NSDictionary *abEntry;

    abEntry = [[BookmarkModel sharedInstance] bookmarkWithName:session];
    if (abEntry == nil) {
        abEntry = [[BookmarkModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        abEntry = aDict;
    }
    
    // If we have not set up a window, do it now
    if([self windowInited] == NO)
    {
        [self initWindowWithAddressbook:abEntry];
    }
    
    // TODO(georgen): test this
    // launch the session!
    [[iTermController sharedInstance] launchBookmark: abEntry inTerminal: self];
    
    return;
}

@end

