// $Id: PreferencePanel.m,v 1.162 2008-10-02 03:48:36 yfabian Exp $
/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
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

#import <iTerm/PreferencePanel.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/iTermController.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermKeyBindingMgr.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/BookmarkModel.h>
#import "PasteboardHistory.h"

static float versionNumber;

@implementation PreferencePanel

+ (PreferencePanel*)sharedInstance;
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[BookmarkModel sharedInstance]
                                     userDefaults:[NSUserDefaults standardUserDefaults]];
        shared->oneBookmarkMode = NO;
    }

    return shared;
}

+ (PreferencePanel*)sessionsInstance;
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[BookmarkModel sessionsInstance]
                                     userDefaults:nil];
        shared->oneBookmarkMode = YES;
    }

    return shared;
}


/*
 Static method to copy old preferences file, iTerm.plist or net.sourceforge.iTerm.plist, to new
 preferences file, com.googlecode.iterm2.plist
 */
+ (BOOL) migratePreferences {

    NSString *prefDir = [[NSHomeDirectory()
        stringByAppendingPathComponent:@"Library"]
        stringByAppendingPathComponent:@"Preferences"];

    NSString *reallyOldPrefs = [prefDir stringByAppendingPathComponent:@"iTerm.plist"];
    NSString *somewhatOldPrefs = [prefDir stringByAppendingPathComponent:@"net.sourceforge.iTerm.plist"];
    NSString *newPrefs = [prefDir stringByAppendingPathComponent:@"com.googlecode.iterm2.plist"];

    NSFileManager *mgr = [NSFileManager defaultManager];

    if ([mgr fileExistsAtPath:newPrefs]) {
        return NO;
    }
    NSString* source;
    if ([mgr fileExistsAtPath:somewhatOldPrefs]) {
        source = somewhatOldPrefs;
    } else if ([mgr fileExistsAtPath:reallyOldPrefs]) {
        source = reallyOldPrefs;
    } else {
        return NO;
    }

    NSLog(@"Preference file migrated");
    [mgr copyPath:source toPath:newPrefs handler:nil];
    [NSUserDefaults resetStandardUserDefaults];
    return (YES);
}

- (id)initWithDataSource:(BookmarkModel*)model userDefaults:(NSUserDefaults*)userDefaults
{
    unsigned int storedMajorVersion = 0, storedMinorVersion = 0, storedMicroVersion = 0;

    self = [super init];
    dataSource = model;
    prefs = userDefaults;
    oneBookmarkOnly = NO;
    [self readPreferences];
    if (defaultEnableBonjour == YES) {
        [[ITAddressBookMgr sharedInstance] locateBonjourServices];
    }

    // get the version
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    versionNumber = [(NSNumber *)[myDict objectForKey:@"CFBundleVersion"] floatValue];
    if (prefs && [prefs objectForKey: @"iTerm Version"]) {
        sscanf([[prefs objectForKey: @"iTerm Version"] cString], "%d.%d.%d", &storedMajorVersion, &storedMinorVersion, &storedMicroVersion);
        // briefly, version 0.7.0 was stored as 0.70
        if(storedMajorVersion == 0 && storedMinorVersion == 70)
            storedMinorVersion = 7;
    }
    //NSLog(@"Stored version = %d.%d.%d", storedMajorVersion, storedMinorVersion, storedMicroVersion);

    // sync the version number
    if (prefs) {
        [prefs setObject: [myDict objectForKey:@"CFBundleVersion"] forKey: @"iTerm Version"];
    }
    [toolbar setSelectedItemIdentifier:globalToolbarId];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_reloadURLHandlers:)
                                                 name:@"iTermReloadAddressBook"
                                               object:nil];

    return (self);
}

- (void)setOneBokmarkOnly
{
    oneBookmarkOnly = YES;
    [self showBookmarks];
    [toolbar setVisible:NO];
    [bookmarksTableView setHidden:YES];
    [addBookmarkButton setHidden:YES];
    [removeBookmarkButton setHidden:YES];
    [bookmarksPopup setHidden:YES];
    [bookmarkDirectory setHidden:YES];
    [bookmarkShortcutKeyLabel setHidden:YES];
    [bookmarkShortcutKeyModifiersLabel setHidden:YES];
    [bookmarkTagsLabel setHidden:YES];
    [bookmarkCommandLabel setHidden:YES];
    [bookmarkDirectoryLabel setHidden:YES];
    [bookmarkShortcutKey setHidden:YES];
    [tags setHidden:YES];
    [bookmarkCommandType setHidden:YES];
    [bookmarkCommand setHidden:YES];
    [bookmarkDirectoryType setHidden:YES];
    [bookmarkDirectory setHidden:YES];

    NSRect newFrame = [bookmarksSettingsTabViewParent frame];
    newFrame.origin.x = 0;
    [bookmarksSettingsTabViewParent setFrame:newFrame];

    newFrame = [[self window] frame];
    newFrame.size.width = [bookmarksSettingsTabViewParent frame].size.width + 26;
    [[self window] setFrame:newFrame display:YES];
}

- (void)awakeFromNib
{
    [self window];
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    NSAssert(bookmarksTableView, @"Null table view");
    [bookmarksTableView setDataSource:dataSource];

    bookmarksToolbarId = [bookmarksToolbarItem itemIdentifier];
    globalToolbarId = [globalToolbarItem itemIdentifier];
    advancedToolbarId = [advancedToolbarItem itemIdentifier];
    [toolbar setSelectedItemIdentifier:globalToolbarId];

    // add list of encodings
    NSEnumerator *anEnumerator;
    NSNumber *anEncoding;

    [characterEncoding removeAllItems];
    anEnumerator = [[[iTermController sharedInstance] sortedEncodingList] objectEnumerator];
    while ((anEncoding = [anEnumerator nextObject]) != NULL) {
        [characterEncoding addItemWithTitle:[NSString localizedNameOfStringEncoding:[anEncoding unsignedIntValue]]];
        [[characterEncoding lastItem] setTag:[anEncoding unsignedIntValue]];
    }

    [keyMappings setDoubleAction:@selector(editKeyMapping:)];
    keyString = nil;
    [bookmarksForUrlsTable setShowGraphic:NO];
    [bookmarksForUrlsTable hideSearch];
    [bookmarksForUrlsTable allowEmptySelection];
    [bookmarksForUrlsTable deselectAll];
    [bookmarksForUrlsTable setDelegate:self];

    [bookmarksTableView setDelegate:self];
    [bookmarksTableView allowMultipleSelections];

    [copyTo allowMultipleSelections];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowWillCloseNotification:)
                                                 name:NSWindowWillCloseNotification object: [self window]];
    if (oneBookmarkMode) {
        [self setOneBokmarkOnly];
    }
    [[tags cell] setDelegate:self];
    [tags setDelegate:self];
}

- (void)handleWindowWillCloseNotification:(NSNotification *)notification {
    // This is so tags get saved because Cocoa doesn't notify you that the
    // field changed unless the user presses enter twice in it (!).
    [self bookmarkSettingChanged:nil];
}

- (void)genericCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet close];
}

- (void)editKeyMapping:(id)sender
{
    int rowIndex = [keyMappings selectedRow];
    if (rowIndex < 0) {
        [self addNewMapping:self];
        return;
    }
    [keyPress setStringValue:[self formattedKeyCombinationForRow:rowIndex]];
    if (keyString) {
        [keyString release];
    }
    keyString = [[[self keyComboAtIndex:rowIndex] copy] retain];
    [action selectItemWithTag:[[[self keyInfoAtIndex:rowIndex] objectForKey:@"Action"] intValue]];
    NSString* text = [[self keyInfoAtIndex:rowIndex] objectForKey:@"Text"];
    [valueToSend setStringValue:text ? text : @""];

    [self updateValueToSend];
    newMapping = NO;
    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)saveKeyMapping:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
    NSAssert(dict, @"Can't find node");

    [iTermKeyBindingMgr setMappingAtIndex:[keyMappings selectedRow]
                                   forKey:keyString
                                   action:[[action selectedItem] tag]
                                    value:[valueToSend stringValue]
                                createNew:newMapping
                               inBookmark:dict];

    [dataSource setBookmark:dict withGuid:guid];
    [keyMappings reloadData];
    [self closeKeyMapping:sender];
    [self bookmarkSettingChanged:sender];
}

- (BOOL)keySheetIsOpen
{
    return [editKeyMappingWindow isVisible];
}

- (IBAction)closeKeyMapping:(id)sender
{
    [NSApp endSheet:editKeyMappingWindow];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return TRUE;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    if (!flag) {
        return nil;
    }
    if ([itemIdentifier isEqual:globalToolbarId]) {
        return globalToolbarItem;
    } else if ([itemIdentifier isEqual:bookmarksToolbarId]) {
        return bookmarksToolbarItem;
    } else if ([itemIdentifier isEqual:advancedToolbarId]) {
        return advancedToolbarItem;
    } else {
        return nil;
    }
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId,
                                     bookmarksToolbarId,
                                     advancedToolbarId,
                                     nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId, bookmarksToolbarId, advancedToolbarId, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
    // Optional delegate method: Returns the identifiers of the subset of
    // toolbar items that are selectable.
    return [NSArray arrayWithObjects:globalToolbarId,
                                     bookmarksToolbarId,
                                     advancedToolbarId,
                                     nil];
}

- (void)dealloc
{
    [defaultWordChars release];
    [super dealloc];
}

- (void) readPreferences
{
    if (!prefs) {
        // In one-bookmark mode there are no prefs, but this function only reads
        // non-bookmark related stuff.
        return;
    }
    // Force antialiasing to be allowed on small font sizes
    [prefs setInteger:1 forKey:@"AppleAntiAliasingThreshold"];
    [prefs setInteger:1 forKey:@"AppleSmoothFixedFontsSizeThreshold"];
    [prefs setInteger:0 forKey:@"AppleScrollAnimationEnabled"];

    defaultWindowStyle=[prefs objectForKey:@"WindowStyle"]?[prefs integerForKey:@"WindowStyle"]:0;
    defaultTabViewType=[prefs objectForKey:@"TabViewType"]?[prefs integerForKey:@"TabViewType"]:0;
    if (defaultTabViewType > 1) {
        defaultTabViewType = 0;
    }
    defaultCopySelection=[prefs objectForKey:@"CopySelection"]?[[prefs objectForKey:@"CopySelection"] boolValue]:YES;
    defaultPasteFromClipboard=[prefs objectForKey:@"PasteFromClipboard"]?[[prefs objectForKey:@"PasteFromClipboard"] boolValue]:YES;
    defaultHideTab=[prefs objectForKey:@"HideTab"]?[[prefs objectForKey:@"HideTab"] boolValue]: YES;
    defaultPromptOnClose = [prefs objectForKey:@"PromptOnClose"]?[[prefs objectForKey:@"PromptOnClose"] boolValue]: NO;
    defaultOnlyWhenMoreTabs = [prefs objectForKey:@"OnlyWhenMoreTabs"]?[[prefs objectForKey:@"OnlyWhenMoreTabs"] boolValue]: NO;
    defaultFocusFollowsMouse = [prefs objectForKey:@"FocusFollowsMouse"]?[[prefs objectForKey:@"FocusFollowsMouse"] boolValue]: NO;
    defaultEnableBonjour = [prefs objectForKey:@"EnableRendezvous"]?[[prefs objectForKey:@"EnableRendezvous"] boolValue]: YES;
    defaultEnableGrowl = [prefs objectForKey:@"EnableGrowl"]?[[prefs objectForKey:@"EnableGrowl"] boolValue]: NO;
    defaultCmdSelection = [prefs objectForKey:@"CommandSelection"]?[[prefs objectForKey:@"CommandSelection"] boolValue]: YES;
    defaultMaxVertically = [prefs objectForKey:@"MaxVertically"]?[[prefs objectForKey:@"MaxVertically"] boolValue]: YES;
    defaultUseCompactLabel = [prefs objectForKey:@"UseCompactLabel"]?[[prefs objectForKey:@"UseCompactLabel"] boolValue]: YES;
    defaultHighlightTabLabels = [prefs objectForKey:@"HighlightTabLabels"]?[[prefs objectForKey:@"HighlightTabLabels"] boolValue]: YES;
    [defaultWordChars release];
    defaultWordChars = [prefs objectForKey: @"WordCharacters"]?[[prefs objectForKey: @"WordCharacters"] retain]:@"/-+\\~_.";
    defaultOpenBookmark = [prefs objectForKey:@"OpenBookmark"]?[[prefs objectForKey:@"OpenBookmark"] boolValue]: NO;
    defaultQuitWhenAllWindowsClosed = [prefs objectForKey:@"QuitWhenAllWindowsClosed"]?[[prefs objectForKey:@"QuitWhenAllWindowsClosed"] boolValue]: NO;
    defaultCursorType=[prefs objectForKey:@"CursorType"]?[prefs integerForKey:@"CursorType"]:2;
    defaultCheckUpdate = [prefs objectForKey:@"SUEnableAutomaticChecks"]?[[prefs objectForKey:@"SUEnableAutomaticChecks"] boolValue]: YES;
    defaultUseBorder = [prefs objectForKey:@"UseBorder"]?[[prefs objectForKey:@"UseBorder"] boolValue]: NO;
    defaultHideScrollbar = [prefs objectForKey:@"HideScrollbar"]?[[prefs objectForKey:@"HideScrollbar"] boolValue]: NO;
    defaultSmartPlacement = [prefs objectForKey:@"SmartPlacement"]?[[prefs objectForKey:@"SmartPlacement"] boolValue]: YES;
    defaultInstantReplay = [prefs objectForKey:@"InstantReplay"]?[[prefs objectForKey:@"InstantReplay"] boolValue]: YES;
    defaultHotkey = [prefs objectForKey:@"Hotkey"]?[[prefs objectForKey:@"Hotkey"] boolValue]: NO;
    defaultHotkeyCode = [prefs objectForKey:@"HotkeyCode"]?[[prefs objectForKey:@"HotkeyCode"] intValue]: 0;
    defaultHotkeyChar = [prefs objectForKey:@"HotkeyChar"]?[[prefs objectForKey:@"HotkeyChar"] intValue]: 0;
    defaultHotkeyModifiers = [prefs objectForKey:@"HotkeyModifiers"]?[[prefs objectForKey:@"HotkeyModifiers"] intValue]: 0;
    defaultSavePasteHistory = [prefs objectForKey:@"SavePasteHistory"]?[[prefs objectForKey:@"SavePasteHistory"] boolValue]: NO;
    defaultIrMemory = [prefs objectForKey:@"IRMemory"]?[[prefs objectForKey:@"IRMemory"] intValue] : 4;
    defaultCheckTestRelease = [prefs objectForKey:@"CheckTestRelease"]?[[prefs objectForKey:@"CheckTestRelease"] boolValue]: YES;
    defaultColorInvertedCursor = [prefs objectForKey:@"ColorInvertedCursor"]?[[prefs objectForKey:@"ColorInvertedCursor"] boolValue]: NO;
    NSString *appCast = defaultCheckTestRelease ?
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
    [prefs setObject:appCast forKey:@"SUFeedURL"];

    NSArray *urlArray;

    // Migrate old-style URL handlers.
    // make sure bookmarks are loaded
    [ITAddressBookMgr sharedInstance];

    // read in the handlers by converting the index back to bookmarks
    urlHandlersByGuid = [[NSMutableDictionary alloc] init];
    NSDictionary *tempDict = [prefs objectForKey:@"URLHandlersByGuid"];
    if (!tempDict) {
        // Iterate over old style url handlers (which stored bookmark by index)
        // and add guid->urlkey to urlHandlersByGuid.
        tempDict = [prefs objectForKey:@"URLHandlers"];

        if (tempDict) {
            NSEnumerator *enumerator = [tempDict keyEnumerator];
            id key;

            while ((key = [enumerator nextObject])) {
                //NSLog(@"%@\n%@",[tempDict objectForKey:key], [[ITAddressBookMgr sharedInstance] bookmarkForIndex:[[tempDict objectForKey:key] intValue]]);
                int theIndex = [[tempDict objectForKey:key] intValue];
                if (theIndex >= 0 &&
                    theIndex  < [dataSource numberOfBookmarks]) {
                    NSString* guid = [[dataSource bookmarkAtIndex:theIndex] objectForKey:KEY_GUID];
                    [urlHandlersByGuid setObject:guid forKey:key];
                }
            }
        }
    } else {
        NSEnumerator *enumerator = [tempDict keyEnumerator];
        id key;

        while ((key = [enumerator nextObject])) {
            //NSLog(@"%@\n%@",[tempDict objectForKey:key], [[ITAddressBookMgr sharedInstance] bookmarkForIndex:[[tempDict objectForKey:key] intValue]]);
            NSString* guid = [tempDict objectForKey:key];
            if ([dataSource indexOfBookmarkWithGuid:guid] >= 0) {
                [urlHandlersByGuid setObject:guid forKey:key];
            }
        }
    }
    urlArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    urlTypes = [[NSMutableArray alloc] initWithCapacity:[urlArray count]];
    for (int i=0; i<[urlArray count]; i++) {
        [urlTypes addObject:[[[urlArray objectAtIndex:i] objectForKey: @"CFBundleURLSchemes"] objectAtIndex:0]];
    }
}

- (void)savePreferences
{
    if (!prefs) {
        // In one-bookmark mode there are no prefs but this function doesn't
        // affect bookmarks.
        return;
    }

    [prefs setBool:defaultCopySelection forKey:@"CopySelection"];
    [prefs setBool:defaultPasteFromClipboard forKey:@"PasteFromClipboard"];
    [prefs setBool:defaultHideTab forKey:@"HideTab"];
    [prefs setInteger:defaultWindowStyle forKey:@"WindowStyle"];
    [prefs setInteger:defaultTabViewType forKey:@"TabViewType"];
    [prefs setBool:defaultPromptOnClose forKey:@"PromptOnClose"];
    [prefs setBool:defaultOnlyWhenMoreTabs forKey:@"OnlyWhenMoreTabs"];
    [prefs setBool:defaultFocusFollowsMouse forKey:@"FocusFollowsMouse"];
    [prefs setBool:defaultEnableBonjour forKey:@"EnableRendezvous"];
    [prefs setBool:defaultEnableGrowl forKey:@"EnableGrowl"];
    [prefs setBool:defaultCmdSelection forKey:@"CommandSelection"];
    [prefs setBool:defaultMaxVertically forKey:@"MaxVertically"];
    [prefs setBool:defaultUseCompactLabel forKey:@"UseCompactLabel"];
    [prefs setBool:defaultHighlightTabLabels forKey:@"HighlightTabLabels"];
    [prefs setObject: defaultWordChars forKey: @"WordCharacters"];
    [prefs setBool:defaultOpenBookmark forKey:@"OpenBookmark"];
    [prefs setObject:[dataSource rawData] forKey: @"New Bookmarks"];
    [prefs setBool:defaultQuitWhenAllWindowsClosed forKey:@"QuitWhenAllWindowsClosed"];
    [prefs setBool:defaultCheckUpdate forKey:@"SUEnableAutomaticChecks"];
    [prefs setInteger:defaultCursorType forKey:@"CursorType"];
    [prefs setBool:defaultUseBorder forKey:@"UseBorder"];
    [prefs setBool:defaultHideScrollbar forKey:@"HideScrollbar"];
    [prefs setBool:defaultSmartPlacement forKey:@"SmartPlacement"];
    [prefs setBool:defaultInstantReplay forKey:@"InstantReplay"];
    [prefs setBool:defaultHotkey forKey:@"Hotkey"];
    [prefs setInteger:defaultHotkeyCode forKey:@"HotkeyCode"];
    [prefs setInteger:defaultHotkeyChar forKey:@"HotkeyChar"];
    [prefs setInteger:defaultHotkeyModifiers forKey:@"HotkeyModifiers"];
    [prefs setBool:defaultSavePasteHistory forKey:@"SavePasteHistory"];
    [prefs setInteger:defaultIrMemory forKey:@"IRMemory"];
    [prefs setBool:defaultCheckTestRelease forKey:@"CheckTestRelease"];
    [prefs setBool:defaultColorInvertedCursor forKey:@"ColorInvertedCursor"];

    // save the handlers by converting the bookmark into an index
    [prefs setObject:urlHandlersByGuid forKey:@"URLHandlersByGuid"];

    [prefs synchronize];
}

- (void)run
{
    // load nib if we haven't already
    if ([self window] == nil) {
        [self initWithWindowNibName:@"PreferencePanel"];
    }

    [[self window] setDelegate: self]; // also forces window to load

    [wordChars setDelegate: self];

    [windowStyle selectItemAtIndex: defaultWindowStyle];
    [tabPosition selectItemAtIndex: defaultTabViewType];
    [selectionCopiesText setState:defaultCopySelection?NSOnState:NSOffState];
    [middleButtonPastesFromClipboard setState:defaultPasteFromClipboard?NSOnState:NSOffState];
    [hideTab setState:defaultHideTab?NSOnState:NSOffState];
    [promptOnClose setState:defaultPromptOnClose?NSOnState:NSOffState];
    [onlyWhenMoreTabs setState:defaultOnlyWhenMoreTabs?NSOnState:NSOffState];
    [onlyWhenMoreTabs setEnabled: defaultPromptOnClose];
    [focusFollowsMouse setState: defaultFocusFollowsMouse?NSOnState:NSOffState];
    [enableBonjour setState: defaultEnableBonjour?NSOnState:NSOffState];
    [enableGrowl setState: defaultEnableGrowl?NSOnState:NSOffState];
    [cmdSelection setState: defaultCmdSelection?NSOnState:NSOffState];
    [maxVertically setState: defaultMaxVertically?NSOnState:NSOffState];
    [useCompactLabel setState: defaultUseCompactLabel?NSOnState:NSOffState];
    [highlightTabLabels setState: defaultHighlightTabLabels?NSOnState:NSOffState];
    [openBookmark setState: defaultOpenBookmark?NSOnState:NSOffState];
    [wordChars setStringValue: ([defaultWordChars length] > 0)?defaultWordChars:@""];
    [quitWhenAllWindowsClosed setState: defaultQuitWhenAllWindowsClosed?NSOnState:NSOffState];
    [checkUpdate setState: defaultCheckUpdate?NSOnState:NSOffState];
    [cursorType selectCellWithTag:defaultCursorType];
    [useBorder setState: defaultUseBorder?NSOnState:NSOffState];
    [hideScrollbar setState: defaultHideScrollbar?NSOnState:NSOffState];
    [smartPlacement setState: defaultSmartPlacement?NSOnState:NSOffState];
    [instantReplay setState: defaultInstantReplay?NSOnState:NSOffState];
    [savePasteHistory setState: defaultSavePasteHistory?NSOnState:NSOffState];
    [hotkey setState: defaultHotkey?NSOnState:NSOffState];
    if (defaultHotkeyCode) {
        [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", defaultHotkeyChar, defaultHotkeyModifiers]]];
    } else {
        [hotkeyField setStringValue:@""];
    }
    [irMemory setIntValue:defaultIrMemory];
    [checkTestRelease setState: defaultCheckTestRelease?NSOnState:NSOffState];
    [checkColorInvertedCursor setState: defaultColorInvertedCursor?NSOnState:NSOffState];

    [self showWindow: self];
    [[self window] setLevel:NSNormalWindowLevel];
    NSString* guid = [bookmarksTableView selectedGuid];
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        Bookmark* dict = [dataSource bookmarkWithGuid:guid];
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:NO];
        [self updateBookmarkFields:dict];
    } else {
        [bookmarksPopup setEnabled:YES];
        [bookmarksSettingsTabViewParent setHidden:YES];
        if ([[bookmarksTableView selectedGuids] count] == 0) {
            [removeBookmarkButton setEnabled:NO];
        } else {
            [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [[bookmarksTableView dataSource] numberOfBookmarks]];
        }
        [self updateBookmarkFields:nil];
    }

    if (![bookmarksTableView selectedGuid] && [bookmarksTableView numberOfRows]) {
        [bookmarksTableView selectRowIndex:0];
    }
    // Show the window.
    [[self window] makeKeyAndOrderFront:self];
}

- (IBAction)settingChanged:(id)sender
{

    if (sender == windowStyle ||
        sender == tabPosition ||
        sender == hideTab ||
        sender == useCompactLabel ||
        sender == highlightTabLabels ||
        sender == cursorType ||
        sender == useBorder ||
        sender == hideScrollbar ||
        sender == checkColorInvertedCursor) {
        defaultWindowStyle = [windowStyle indexOfSelectedItem];
        defaultTabViewType=[tabPosition indexOfSelectedItem];
        defaultUseCompactLabel = ([useCompactLabel state] == NSOnState);
        defaultHighlightTabLabels = ([highlightTabLabels state] == NSOnState);
        defaultHideTab=([hideTab state]==NSOnState);
        defaultCursorType = [[cursorType selectedCell] tag];
        defaultColorInvertedCursor = ([checkColorInvertedCursor state] == NSOnState);
        defaultUseBorder = ([useBorder state] == NSOnState);
        defaultHideScrollbar = ([hideScrollbar state] == NSOnState);
        [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermRefreshTerminal" object: nil userInfo: nil];
    } else {
        defaultCopySelection=([selectionCopiesText state]==NSOnState);
        defaultPasteFromClipboard=([middleButtonPastesFromClipboard state]==NSOnState);
        defaultPromptOnClose = ([promptOnClose state] == NSOnState);
        defaultOnlyWhenMoreTabs = ([onlyWhenMoreTabs state] == NSOnState);
        [onlyWhenMoreTabs setEnabled: defaultPromptOnClose];
        defaultFocusFollowsMouse = ([focusFollowsMouse state] == NSOnState);
        BOOL bonjourBefore = defaultEnableBonjour;
        defaultEnableBonjour = ([enableBonjour state] == NSOnState);
        if (bonjourBefore != defaultEnableBonjour) {
            if (defaultEnableBonjour == YES) {
                [[ITAddressBookMgr sharedInstance] locateBonjourServices];
            } else {
                [[ITAddressBookMgr sharedInstance] stopLocatingBonjourServices];

                // Remove existing bookmarks with the "bonjour" tag. Even if
                // network browsing is re-enabled, these bookmarks would never
                // be automatically removed.
                BookmarkModel* model = [BookmarkModel sharedInstance];
                NSString* kBonjourTag = @"bonjour";
                int n = [model numberOfBookmarksWithFilter:kBonjourTag];
                for (int i = n - 1; i >= 0; --i) {
                    Bookmark* bookmark = [model bookmarkAtIndex:i withFilter:kBonjourTag];
                    if ([model bookmark:bookmark hasTag:kBonjourTag]) {
                        [model removeBookmarkAtIndex:i withFilter:kBonjourTag];
                    }
                }
            }
        }

        defaultEnableGrowl = ([enableGrowl state] == NSOnState);
        defaultCmdSelection = ([cmdSelection state] == NSOnState);
        defaultMaxVertically = ([maxVertically state] == NSOnState);
        defaultOpenBookmark = ([openBookmark state] == NSOnState);
        [defaultWordChars release];
        defaultWordChars = [[wordChars stringValue] retain];
        defaultQuitWhenAllWindowsClosed = ([quitWhenAllWindowsClosed state] == NSOnState);
        defaultCheckUpdate = ([checkUpdate state] == NSOnState);
        defaultSmartPlacement = ([smartPlacement state] == NSOnState);
        defaultInstantReplay = ([instantReplay state] == NSOnState);
        defaultSavePasteHistory = ([savePasteHistory state] == NSOnState);
        if (!defaultSavePasteHistory) {
            [[PasteboardHistory sharedInstance] eraseHistory];
        }
        defaultIrMemory = [irMemory intValue];
        BOOL oldDefaultHotkey = defaultHotkey;
        defaultHotkey = ([hotkey state] == NSOnState);
        if (defaultHotkey != oldDefaultHotkey) {
            if (defaultHotkey) {
                [[iTermController sharedInstance] registerHotkey:defaultHotkeyCode modifiers:defaultHotkeyModifiers];
            } else {
                [[iTermController sharedInstance] unregisterHotkey];
            }
        }
        if (prefs &&
            defaultCheckTestRelease != ([checkTestRelease state] == NSOnState)) {
            defaultCheckTestRelease = ([checkTestRelease state] == NSOnState);

            NSString *appCast = defaultCheckTestRelease ?
                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
            [prefs setObject: appCast forKey:@"SUFeedURL"];
        }
    }
}

// NSWindow delegate
- (void)windowWillLoad
{
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setWindowFrameAutosaveName:@"Preferences"];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [self settingChanged:nil];
    [self savePreferences];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"nonTerminalWindowBecameKey"
                                                        object:nil
                                                      userInfo:nil];
}


// accessors for preferences


- (BOOL)copySelection
{
    return defaultCopySelection;
}

- (void) setCopySelection:(BOOL)flag
{
    defaultCopySelection = flag;
}

- (BOOL)pasteFromClipboard
{
    return defaultPasteFromClipboard;
}

- (void)setPasteFromClipboard:(BOOL)flag
{
    defaultPasteFromClipboard = flag;
}

- (BOOL)hideTab
{
    return defaultHideTab;
}

- (void)setTabViewType:(NSTabViewType)type
{
    defaultTabViewType = type;
}

- (NSTabViewType)tabViewType
{
    return defaultTabViewType;
}

- (int)windowStyle
{
    return defaultWindowStyle;
}

- (BOOL)promptOnClose
{
    return defaultPromptOnClose;
}

- (BOOL)onlyWhenMoreTabs
{
    return defaultOnlyWhenMoreTabs;
}

- (BOOL)focusFollowsMouse
{
    return defaultFocusFollowsMouse;
}

- (BOOL)enableBonjour
{
    return defaultEnableBonjour;
}

- (BOOL)enableGrowl
{
    return defaultEnableGrowl;
}

- (BOOL)cmdSelection
{
    return defaultCmdSelection;
}

- (BOOL)maxVertically
{
    return defaultMaxVertically;
}

- (BOOL)useCompactLabel
{
    return defaultUseCompactLabel;
}

- (BOOL)highlightTabLabels
{
    return defaultHighlightTabLabels;
}

- (BOOL)openBookmark
{
    return defaultOpenBookmark;
}

- (NSString *)wordChars
{
    if ([defaultWordChars length] <= 0) {
        return @"";
    }
    return defaultWordChars;
}

- (ITermCursorType)cursorType
{
    return defaultCursorType;
}

- (BOOL)useBorder
{
    return (defaultUseBorder);
}

- (BOOL)hideScrollbar
{
    return defaultHideScrollbar;
}

- (BOOL)smartPlacement
{
    return defaultSmartPlacement;
}

- (BOOL)instantReplay
{
    return defaultInstantReplay;
}

- (BOOL)savePasteHistory
{
    return defaultSavePasteHistory;
}

- (int)irMemory
{
    return defaultIrMemory;
}

- (BOOL)hotkey
{
    return defaultHotkey;
}

- (int)hotkeyCode
{
    return defaultHotkeyCode;
}

- (int)hotkeyModifiers
{
    return defaultHotkeyModifiers;
}

- (NSTextField*)hotkeyField
{
    return hotkeyField;
}

- (void)disableHotkey
{
    [hotkey setState:NSOffState];
    BOOL oldDefaultHotkey = defaultHotkey;
    defaultHotkey = NO;
    if (defaultHotkey != oldDefaultHotkey) {
        [[iTermController sharedInstance] unregisterHotkey];
    }
    [self savePreferences];
}

- (BOOL)checkColorInvertedCursor
{
    return defaultColorInvertedCursor;
}

- (BOOL)checkTestRelease
{
    return defaultCheckTestRelease;
}

- (BOOL)colorInvertedCursor
{
    return defaultColorInvertedCursor;
}

- (BOOL)quitWhenAllWindowsClosed
{
    return defaultQuitWhenAllWindowsClosed;
}

// The following are preferences with no UI, but accessible via "defaults read/write"
// examples:
//  defaults write net.sourceforge.iTerm UseUnevenTabs -bool true
//  defaults write net.sourceforge.iTerm MinTabWidth -int 100
//  defaults write net.sourceforge.iTerm MinCompactTabWidth -int 120
//  defaults write net.sourceforge.iTerm OptimumTabWidth -int 100

- (BOOL)useUnevenTabs
{
    assert(prefs);
    return [prefs objectForKey:@"UseUnevenTabs"] ? [[prefs objectForKey:@"UseUnevenTabs"] boolValue] : NO;
}

- (int) minTabWidth
{
    assert(prefs);
    return [prefs objectForKey:@"MinTabWidth"] ? [[prefs objectForKey:@"MinTabWidth"] intValue] : 75;
}

- (int) minCompactTabWidth
{
    assert(prefs);
    return [prefs objectForKey:@"MinCompactTabWidth"] ? [[prefs objectForKey:@"MinCompactTabWidth"] intValue] : 60;
}

- (int) optimumTabWidth
{
    assert(prefs);
    return [prefs objectForKey:@"OptimumTabWidth"] ? [[prefs objectForKey:@"OptimumTabWidth"] intValue] : 175;
}

- (NSString *) searchCommand
{
    assert(prefs);
    return [prefs objectForKey:@"SearchCommand"] ? [prefs objectForKey:@"SearchCommand"] : @"http://google.com/search?q=%@";
}

// URL handler stuff
- (Bookmark *) handlerBookmarkForURL:(NSString *)url
{
    NSString* guid = [urlHandlersByGuid objectForKey:url];
    if (!guid) {
        return nil;
    }
    int theIndex = [dataSource indexOfBookmarkWithGuid:guid];
    if (theIndex < 0) {
        return nil;
    }
    return [dataSource bookmarkAtIndex:theIndex];
}

// NSTableView data source
- (int)numberOfRowsInTableView: (NSTableView *)aTableView
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        if (!guid) {
            return 0;
        }
        Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Null node");
        return [iTermKeyBindingMgr numberOfMappingsForBookmark:bookmark];
    } else {
        return [urlTypes count];
    }
}


- (NSString*)keyComboAtIndex:(int)rowIndex
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");
    Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
    NSAssert(bookmark, @"Can't find node");
    return [iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark];
}

- (NSDictionary*)keyInfoAtIndex:(int)rowIndex
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");
    Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
    NSAssert(bookmark, @"Can't find node");
    return [iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark];
}

- (NSString*)formattedKeyCombinationForRow:(int)rowIndex
{
    return [iTermKeyBindingMgr formatKeyCombination:[self keyComboAtIndex:rowIndex]];
}

- (NSString*)formattedActionForRow:(int)rowIndex
{
    return [iTermKeyBindingMgr formatAction:[self keyInfoAtIndex:rowIndex]];
}

- (NSString*)valueToSendForRow:(int)rowIndex
{
    return [[self keyInfoAtIndex:rowIndex] objectForKey:@"Text"];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");

        if (aTableColumn == keyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:[iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark]];
        } else if (aTableColumn == actionColumn) {
            return [iTermKeyBindingMgr formatAction:[iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark]];
        }
    } else {
        return [urlTypes objectAtIndex:rowIndex];
    }
    // Shouldn't get here but must return something to avoid a warning.
    return nil;
}

- (void) _updateFontsDisplay
{
        // load the fonts
        NSString *fontName;
    if (normalFont != nil) {
            fontName = [NSString stringWithFormat: @"%gpt %@", [normalFont pointSize], [normalFont displayName]];
    } else {
       fontName = @"Unknown Font";
    }
    [normalFontField setStringValue: fontName];

    if (nonAsciiFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@", [nonAsciiFont pointSize], [nonAsciiFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [nonAsciiFontField setStringValue: fontName];
}

- (void)underlyingBookmarkDidChange
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (guid) {
        Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
        if (bookmark) {
            [self updateBookmarkFields:bookmark];
        }
    }
}

- (int)shortcutTagForKey:(NSString*)key
{
    const char* chars = [key UTF8String];
    if (!chars || !*chars) {
        return -1;
    }
    char c = *chars;
    if (c >= 'A' && c <= 'Z') {
        return c - 'A';
    }
    if (c >= '0' && c <= '9') {
        return 100 + c - '0';
    }
    NSLog(@"Unexpected shortcut key: '%@'", key);
    return -1;
}

- (NSString*)shortcutKeyForTag:(int)tag
{
    if (tag == -1) {
        return @"";
    }
    if (tag >= 0 && tag <= 25) {
        return [NSString stringWithFormat:@"%c", 'A' + tag];
    }
    if (tag >= 100 && tag <= 109) {
        return [NSString stringWithFormat:@"%c", '0' + tag - 100];
    }
    return @"";
}

- (void)updateShortcutTitles
{
    // Reset titles of all shortcuts.
    for (int i = 0; i < [bookmarkShortcutKey numberOfItems]; ++i) {
        NSMenuItem* item = [bookmarkShortcutKey itemAtIndex:i];
        [item setTitle:[self shortcutKeyForTag:[item tag]]];
    }

    // Add bookmark names to shortcuts that are bound.
    for (int i = 0; i < [dataSource numberOfBookmarks]; ++i) {
        Bookmark* temp = [dataSource bookmarkAtIndex:i];
        NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            NSLog(@"Bookmark %@ has shortcut %@", [temp objectForKey:KEY_NAME], existingShortcut);
            const int theIndex = [bookmarkShortcutKey indexOfItemWithTag:tag];
            NSMenuItem* item = [bookmarkShortcutKey itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"%@ (%@)", existingShortcut, [temp objectForKey:KEY_NAME]];
            [item setTitle:newTitle];
        }
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)updateBookmarkFields:(NSDictionary *)dict
{
    if ([dataSource numberOfBookmarks] < 2 || !dict) {
        [removeBookmarkButton setEnabled:NO];
    } else {
        [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [[bookmarksTableView dataSource] numberOfBookmarks]];
    }
    if (!dict) {
        [bookmarksSettingsTabViewParent setHidden:YES];
        [bookmarksPopup setEnabled:NO];
        return;
    } else {
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:YES];
    }

    NSString* name;
    NSString* shortcut;
    NSString* command;
    NSString* dir;
    NSString* customCommand;
    NSString* customDir;
    name = [dict objectForKey:KEY_NAME];
    shortcut = [dict objectForKey:KEY_SHORTCUT];
    command = [dict objectForKey:KEY_COMMAND];
    dir = [dict objectForKey:KEY_WORKING_DIRECTORY];
    customCommand = [dict objectForKey:KEY_CUSTOM_COMMAND];
    customDir = [dict objectForKey:KEY_CUSTOM_DIRECTORY];

    // General tab
    [bookmarkName setStringValue:name];
    [bookmarkShortcutKey selectItemWithTag:[self shortcutTagForKey:shortcut]];

    [self updateShortcutTitles];

    if ([customCommand isEqualToString:@"Yes"]) {
    [bookmarkCommandType selectCellWithTag:0];
    } else {
            [bookmarkCommandType selectCellWithTag:1];
    }
    [bookmarkCommand setStringValue:command];

    if ([customDir isEqualToString:@"Yes"]) {
            [bookmarkDirectoryType selectCellWithTag:0];
    } else if ([customDir isEqualToString:@"Recycle"]) {
            [bookmarkDirectoryType selectCellWithTag:2];
    } else {
            [bookmarkDirectoryType selectCellWithTag:1];
    }
    [bookmarkDirectory setStringValue:dir];

        // Colors tab
    [ansi0Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_0_COLOR]]];
    [ansi1Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_1_COLOR]]];
    [ansi2Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_2_COLOR]]];
    [ansi3Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_3_COLOR]]];
    [ansi4Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_4_COLOR]]];
    [ansi5Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_5_COLOR]]];
    [ansi6Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_6_COLOR]]];
    [ansi7Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_7_COLOR]]];
    [ansi8Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_8_COLOR]]];
    [ansi9Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_9_COLOR]]];
    [ansi10Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_10_COLOR]]];
    [ansi11Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_11_COLOR]]];
    [ansi12Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_12_COLOR]]];
    [ansi13Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_13_COLOR]]];
    [ansi14Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_14_COLOR]]];
    [ansi15Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_15_COLOR]]];
    [foregroundColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_FOREGROUND_COLOR]]];
    [backgroundColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_BACKGROUND_COLOR]]];
    [boldColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_BOLD_COLOR]]];
    [selectionColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_SELECTION_COLOR]]];
    [selectedTextColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_SELECTED_TEXT_COLOR]]];
    [cursorColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_CURSOR_COLOR]]];
    [cursorTextColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_CURSOR_TEXT_COLOR]]];

        // Display tab
    int cols = [[dict objectForKey:KEY_COLUMNS] intValue];
    [columnsField setStringValue:[NSString stringWithFormat:@"%d", cols]];
    int rows = [[dict objectForKey:KEY_ROWS] intValue];
    [rowsField setStringValue:[NSString stringWithFormat:@"%d", rows]];

    [normalFontField setStringValue:[[ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NORMAL_FONT]] displayName]];
    if (normalFont) {
        [normalFont release];
    }
    normalFont = [ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NORMAL_FONT]];
    [normalFont retain];

    [nonAsciiFontField setStringValue:[[ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NON_ASCII_FONT]] displayName]];
    if (nonAsciiFont) {
        [nonAsciiFont release];
    }
    nonAsciiFont = [ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NON_ASCII_FONT]];
    [nonAsciiFont retain];

    [self _updateFontsDisplay];

    float horizontalSpacing = [[dict objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
    float verticalSpacing = [[dict objectForKey:KEY_VERTICAL_SPACING] floatValue];

    [displayFontSpacingWidth setFloatValue:horizontalSpacing];
    [displayFontSpacingHeight setFloatValue:verticalSpacing];
    [blinkingCursor setState:[[dict objectForKey:KEY_BLINKING_CURSOR] boolValue] ? NSOnState : NSOffState];
    [disableBold setState:[[dict objectForKey:KEY_DISABLE_BOLD] boolValue] ? NSOnState : NSOffState];
    [transparency setFloatValue:[[dict objectForKey:KEY_TRANSPARENCY] floatValue]];
    [blur setState:[[dict objectForKey:KEY_BLUR] boolValue] ? NSOnState : NSOffState];
    [antiAliasing setState:[[dict objectForKey:KEY_ANTI_ALIASING] boolValue] ? NSOnState : NSOffState];
    NSString* imageFilename = [dict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    if (!imageFilename) {
        imageFilename = @"";
    }
    [backgroundImage setState:[imageFilename length] > 0 ? NSOnState : NSOffState];
    [backgroundImagePreview setImage:[[NSImage alloc] initByReferencingFile:imageFilename]];
    backgroundImageFilename = imageFilename;

        // Terminal tab
    [disableWindowResizing setState:[[dict objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] ? NSOnState : NSOffState];
    [syncTitle setState:[[dict objectForKey:KEY_SYNC_TITLE] boolValue] ? NSOnState : NSOffState];
    [closeSessionsOnEnd setState:[[dict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue] ? NSOnState : NSOffState];
    [nonAsciiDoubleWidth setState:[[dict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue] ? NSOnState : NSOffState];
    [silenceBell setState:[[dict objectForKey:KEY_SILENCE_BELL] boolValue] ? NSOnState : NSOffState];
    [visualBell setState:[[dict objectForKey:KEY_VISUAL_BELL] boolValue] ? NSOnState : NSOffState];
    [xtermMouseReporting setState:[[dict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue] ? NSOnState : NSOffState];
    [bookmarkGrowlNotifications setState:[[dict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue] ? NSOnState : NSOffState];
    [characterEncoding setTitle:[NSString localizedNameOfStringEncoding:[[dict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]]];
    [scrollbackLines setIntValue:[[dict objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    [terminalType setStringValue:[dict objectForKey:KEY_TERMINAL_TYPE]];
    [sendCodeWhenIdle setState:[[dict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue] ? NSOnState : NSOffState];
    [idleCode setIntValue:[[dict objectForKey:KEY_IDLE_CODE] intValue]];

        // Keyboard tab
    int rowIndex = [keyMappings selectedRow];
    if (rowIndex >= 0) {
        [removeMappingButton setEnabled:YES];
    } else {
        [removeMappingButton setEnabled:NO];
    }
    [keyMappings reloadData];
    [optionKeySends selectCellWithTag:[[dict objectForKey:KEY_OPTION_KEY_SENDS] intValue]];
    [tags setObjectValue:[dict objectForKey:KEY_TAGS]];

    // Epilogue
    [bookmarksTableView reloadData];
    [copyTo reloadData];
}

- (void)_commonDisplaySelectFont:(id)sender
{
    // make sure we get the messages from the NSFontManager
    [[self window] makeFirstResponder:self];

    NSFontPanel* aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
    [aFontPanel setAccessoryView: displayFontAccessoryView];
    [[NSFontManager sharedFontManager] setSelectedFont:(changingNAFont ? nonAsciiFont : normalFont) isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}


- (IBAction)displaySelectFont:(id)sender
{
        changingNAFont = [sender tag] == 1;
    [self _commonDisplaySelectFont:sender];
}

// sent by NSFontManager up the responder chain
- (void)changeFont:(id)fontManager
{
        if (changingNAFont) {
        NSFont* oldFont = nonAsciiFont;
        nonAsciiFont = [fontManager convertFont:oldFont];
        [nonAsciiFont retain];
        if (oldFont) {
            [oldFont release];
        }
        } else {
        NSFont* oldFont = normalFont;
        normalFont = [fontManager convertFont:oldFont];
        [normalFont retain];
        if (oldFont) {
            [oldFont release];
        }
    }

    [self bookmarkSettingChanged:fontManager];
}

- (NSString*)_chooseBackgroundImage
{
    NSOpenPanel *panel;
    int sts;
    NSString *filename = nil;

    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection: NO];

    sts = [panel runModalForDirectory: NSHomeDirectory() file:@"" types: [NSImage imageFileTypes]];
    if (sts == NSOKButton) {
                if ([[panel filenames] count] > 0) {
                        filename = [[panel filenames] objectAtIndex: 0];
        }

                if ([filename length] > 0) {
                        NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: filename];
                        if (anImage != nil) {
                                [backgroundImagePreview setImage:anImage];
                                [anImage release];
                                return filename;
                        } else {
                                [backgroundImage setState: NSOffState];
            }
                } else {
                        [backgroundImage setState: NSOffState];
        }
    } else {
                [backgroundImage setState: NSOffState];
    }
        return nil;
}

- (IBAction)bookmarkSettingChanged:(id)sender
{
    NSString* name = [bookmarkName stringValue];
    NSString* shortcut = [self shortcutKeyForTag:[[bookmarkShortcutKey selectedItem] tag]];
    NSString* command = [bookmarkCommand stringValue];
    NSString* dir = [bookmarkDirectory stringValue];

    NSString* customCommand = [[bookmarkCommandType selectedCell] tag] == 0 ? @"Yes" : @"No";
    NSString* customDir;

    switch ([[bookmarkDirectoryType selectedCell] tag]) {
        case 0:
            customDir = @"Yes";
            break;

        case 2:
            customDir = @"Recycle";
            break;

        case 1:
        default:
            customDir = @"No";
            break;
    }

    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Bookmark* origBookmark = [dataSource bookmarkWithGuid:guid];
    if (!origBookmark) {
        return;
    }
    NSMutableDictionary* newDict = [[NSMutableDictionary alloc] init];
    [newDict autorelease];
    NSString* isDefault = [origBookmark objectForKey:KEY_DEFAULT_BOOKMARK];
    if (!isDefault) {
        isDefault = @"No";
    }
    [newDict setObject:isDefault forKey:KEY_DEFAULT_BOOKMARK];
    [newDict setObject:name forKey:KEY_NAME];
    [newDict setObject:guid forKey:KEY_GUID];
    if (shortcut) {
        // If any bookmark has this shortcut, clear its shortcut.
        for (int i = 0; i < [dataSource numberOfBookmarks]; ++i) {
            Bookmark* temp = [dataSource bookmarkAtIndex:i];
            NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
            if ([existingShortcut isEqualToString:shortcut] && temp != origBookmark) {
                [dataSource setObject:nil forKey:KEY_SHORTCUT inBookmark:temp];
            }
        }

        [newDict setObject:shortcut forKey:KEY_SHORTCUT];
    }
    [newDict setObject:command forKey:KEY_COMMAND];
    [newDict setObject:dir forKey:KEY_WORKING_DIRECTORY];
    [newDict setObject:customCommand forKey:KEY_CUSTOM_COMMAND];
    [newDict setObject:customDir forKey:KEY_CUSTOM_DIRECTORY];

    // Colors tab
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi0Color color]] forKey:KEY_ANSI_0_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi1Color color]] forKey:KEY_ANSI_1_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi2Color color]] forKey:KEY_ANSI_2_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi3Color color]] forKey:KEY_ANSI_3_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi4Color color]] forKey:KEY_ANSI_4_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi5Color color]] forKey:KEY_ANSI_5_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi6Color color]] forKey:KEY_ANSI_6_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi7Color color]] forKey:KEY_ANSI_7_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi8Color color]] forKey:KEY_ANSI_8_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi9Color color]] forKey:KEY_ANSI_9_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi10Color color]] forKey:KEY_ANSI_10_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi11Color color]] forKey:KEY_ANSI_11_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi12Color color]] forKey:KEY_ANSI_12_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi13Color color]] forKey:KEY_ANSI_13_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi14Color color]] forKey:KEY_ANSI_14_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi15Color color]] forKey:KEY_ANSI_15_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[foregroundColor color]] forKey:KEY_FOREGROUND_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[backgroundColor color]] forKey:KEY_BACKGROUND_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[boldColor color]] forKey:KEY_BOLD_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[selectionColor color]] forKey:KEY_SELECTION_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[selectedTextColor color]] forKey:KEY_SELECTED_TEXT_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[cursorColor color]] forKey:KEY_CURSOR_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[cursorTextColor color]] forKey:KEY_CURSOR_TEXT_COLOR];

    // Display tab
    int rows, cols;
    rows = [rowsField intValue];
    cols = [columnsField intValue];
    if (cols > 0) {
        [newDict setObject:[NSNumber numberWithInt:cols] forKey:KEY_COLUMNS];
    }
    if (rows > 0) {
        [newDict setObject:[NSNumber numberWithInt:rows] forKey:KEY_ROWS];
    }

    [newDict setObject:[ITAddressBookMgr descFromFont:normalFont] forKey:KEY_NORMAL_FONT];
    [newDict setObject:[ITAddressBookMgr descFromFont:nonAsciiFont] forKey:KEY_NON_ASCII_FONT];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingWidth floatValue]] forKey:KEY_HORIZONTAL_SPACING];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingHeight floatValue]] forKey:KEY_VERTICAL_SPACING];
    [newDict setObject:[NSNumber numberWithBool:([blinkingCursor state]==NSOnState)] forKey:KEY_BLINKING_CURSOR];
    [newDict setObject:[NSNumber numberWithBool:([disableBold state]==NSOnState)] forKey:KEY_DISABLE_BOLD];
    [newDict setObject:[NSNumber numberWithFloat:[transparency floatValue]] forKey:KEY_TRANSPARENCY];
    [newDict setObject:[NSNumber numberWithBool:([blur state]==NSOnState)] forKey:KEY_BLUR];
    [newDict setObject:[NSNumber numberWithBool:([antiAliasing state]==NSOnState)] forKey:KEY_ANTI_ALIASING];
    [self _updateFontsDisplay];

    if (sender == backgroundImage) {
        NSString* filename = nil;
                if ([sender state] == NSOnState) {
                        filename = [self _chooseBackgroundImage];
        }
        if (!filename) {
                        [backgroundImagePreview setImage: nil];
            filename = @"";
        }
        backgroundImageFilename = filename;
    }
    [newDict setObject:backgroundImageFilename forKey:KEY_BACKGROUND_IMAGE_LOCATION];

    // Terminal tab
    [newDict setObject:[NSNumber numberWithBool:([disableWindowResizing state]==NSOnState)] forKey:KEY_DISABLE_WINDOW_RESIZING];
    [newDict setObject:[NSNumber numberWithBool:([syncTitle state]==NSOnState)] forKey:KEY_SYNC_TITLE];
    [newDict setObject:[NSNumber numberWithBool:([closeSessionsOnEnd state]==NSOnState)] forKey:KEY_CLOSE_SESSIONS_ON_END];
    [newDict setObject:[NSNumber numberWithBool:([nonAsciiDoubleWidth state]==NSOnState)] forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
    [newDict setObject:[NSNumber numberWithBool:([silenceBell state]==NSOnState)] forKey:KEY_SILENCE_BELL];
    [newDict setObject:[NSNumber numberWithBool:([visualBell state]==NSOnState)] forKey:KEY_VISUAL_BELL];
    [newDict setObject:[NSNumber numberWithBool:([xtermMouseReporting state]==NSOnState)] forKey:KEY_XTERM_MOUSE_REPORTING];
    [newDict setObject:[NSNumber numberWithBool:([bookmarkGrowlNotifications state]==NSOnState)] forKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS];
    [newDict setObject:[NSNumber numberWithUnsignedInt:[[characterEncoding selectedItem] tag]] forKey:KEY_CHARACTER_ENCODING];
    [newDict setObject:[NSNumber numberWithInt:[scrollbackLines intValue]] forKey:KEY_SCROLLBACK_LINES];
    [newDict setObject:[terminalType stringValue] forKey:KEY_TERMINAL_TYPE];
    [newDict setObject:[NSNumber numberWithBool:([sendCodeWhenIdle state]==NSOnState)] forKey:KEY_SEND_CODE_WHEN_IDLE];
    [newDict setObject:[NSNumber numberWithInt:[idleCode intValue]] forKey:KEY_IDLE_CODE];

    // Keyboard tab
    [newDict setObject:[origBookmark objectForKey:KEY_KEYBOARD_MAP] forKey:KEY_KEYBOARD_MAP];
    [newDict setObject:[NSNumber numberWithInt:[[optionKeySends selectedCell] tag]] forKey:KEY_OPTION_KEY_SENDS];
    [newDict setObject:[tags objectValue] forKey:KEY_TAGS];

    // Epilogue
    [dataSource setBookmark:newDict withGuid:guid];
    [bookmarksTableView reloadData];

    // Selectively update form fields.
    [self updateShortcutTitles];

    // Update existing sessions
    int n = [[iTermController sharedInstance] numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
        [pty reloadBookmarks];
    }
    if (prefs) {
        [prefs setObject:[dataSource rawData] forKey: @"New Bookmarks"];
    }
}

- (NSMenu*)bookmarkTable:(id)bookmarkTable menuForEvent:(NSEvent*)theEvent
{
    return nil;
}


- (void)bookmarkTableSelectionWillChange:(id)aBookmarkTableView
{
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        [self bookmarkSettingChanged:nil];
    }
}

- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable
{
    if ([[bookmarksTableView selectedGuids] count] != 1) {
        [bookmarksSettingsTabViewParent setHidden:YES];
        [bookmarksPopup setEnabled:NO];

        if ([[bookmarksTableView selectedGuids] count] == 0) {
            [removeBookmarkButton setEnabled:NO];
        } else {
            [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [[bookmarksTableView dataSource] numberOfBookmarks]];
        }
    } else {
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:YES];
        [removeBookmarkButton setEnabled:NO];
        if (bookmarkTable == bookmarksTableView) {
            NSString* guid = [bookmarksTableView selectedGuid];
            [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];
        }
    }
}

- (void)bookmarkTableRowSelected:(id)bookmarkTable
{
    // Do nothing for double click
}

// NSTableView delegate
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    //NSLog(@"%s", __PRETTY_FUNCTION__);
    if ([aNotification object] == keyMappings) {
        int rowIndex = [keyMappings selectedRow];
        if (rowIndex >= 0) {
            [removeMappingButton setEnabled:YES];
        } else {
            [removeMappingButton setEnabled:NO];
        }
    } else if ([aNotification object] == urlTable) {
        int i = [urlTable selectedRow];
        if (i < 0) {
            [bookmarksForUrlsTable deselectAll];
        } else {
            NSString* guid = [urlHandlersByGuid objectForKey:[urlTypes objectAtIndex:i]];
            if (guid) {
                [bookmarksForUrlsTable selectRowByGuid:guid];
            } else {
                [bookmarksForUrlsTable deselectAll];
            }
        }
    }
}

- (IBAction)showGlobalTabView:(id)sender
{
    [tabView selectTabViewItem:globalTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender
{
    [tabView selectTabViewItem:advancedTabViewItem];
}

- (IBAction)connectURL:(id)sender
{
    int i, j;

    i = [urlTable selectedRow];
    j = [bookmarksForUrlsTable selectedRow];
    if (i < 0) {
        return;
    }
    if (j < 0) {
        // No Handler selected
        [urlHandlersByGuid removeObjectForKey:[urlTypes objectAtIndex: i]];
    } else {
        Bookmark* bookmark =
            [dataSource
                bookmarkAtIndex:[bookmarksForUrlsTable selectedRow]];
        [urlHandlersByGuid setObject:[bookmark objectForKey:KEY_GUID]
                              forKey:[urlTypes objectAtIndex:i]];

        NSURL *appURL = nil;
        OSStatus err;
        BOOL set = NO;

        err = LSGetApplicationForURL(
            (CFURLRef)[NSURL URLWithString:[[urlTypes objectAtIndex: i] stringByAppendingString:@":"]],
                                     kLSRolesAll, NULL, (CFURLRef *)&appURL);
        if (err != noErr) {
            set = NSRunAlertPanel(
                [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(
                    @"iTerm is not the default handler for %@. Would you like to set iTerm as the default handler?",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"URL Handler"), [urlTypes objectAtIndex: i]],
                NSLocalizedStringFromTableInBundle(
                    @"There is no handler currently.",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"URL Handler"),
                NSLocalizedStringFromTableInBundle(
                    @"OK",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"OK"),
                NSLocalizedStringFromTableInBundle(
                    @"Cancel",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"Cancel"),
                nil) == NSAlertDefaultReturn;
        }
        else if (![[[NSFileManager defaultManager] displayNameAtPath:[appURL path]] isEqualToString:@"iTerm"]) {
            set = NSRunAlertPanel(
                [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(
                    @"iTerm is not the default handler for %@. Would you like to set iTerm as the default handler?",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"URL Handler"),
                [urlTypes objectAtIndex: i]],
                [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(
                    @"The current handler is: %@",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"URL Handler"),
                [[NSFileManager defaultManager] displayNameAtPath:[appURL path]]],
                NSLocalizedStringFromTableInBundle(
                    @"OK",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"OK"),
                NSLocalizedStringFromTableInBundle(
                    @"Cancel",
                    @"iTerm",
                    [NSBundle bundleForClass: [self class]],
                    @"Cancel")
                ,nil) == NSAlertDefaultReturn;
        }

        if (set) {
              LSSetDefaultHandlerForURLScheme ((CFStringRef)[urlTypes objectAtIndex: i],(CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
        }
    }
    //NSLog(@"urlHandlers:%@", urlHandlers);
}

- (IBAction)closeWindow:(id)sender
{
    [[self window] close];
}

// NSTextField delegate
- (void)controlTextDidChange:(NSNotification *)aNotification
{
    id obj = [aNotification object];
    if (obj == wordChars) {
        defaultWordChars = [[wordChars stringValue] retain];
    } else if (obj == bookmarkName ||
               obj == columnsField ||
               obj == rowsField ||
               obj == scrollbackLines ||
               obj == terminalType ||
               obj == idleCode) {
        [self bookmarkSettingChanged:nil];
    } else if (obj == tagFilter) {
        NSLog(@"Tag filter changed");
    }
}

- (void)textDidChange:(NSNotification *)aNotification
{
    [self bookmarkSettingChanged:nil];
}

- (BOOL)onScreen
{
    return [self window] && [[self window] isVisible];
}

- (NSTextField*)shortcutKeyTextField
{
    return keyPress;
}

- (void)shortcutKeyDown:(NSEvent*)event
{
    unsigned int keyMods;
    unsigned short keyCode;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    keyCode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;

    // turn off all the other modifier bits we don't care about
    unsigned int theModifiers = keyMods &
        (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask |
         NSCommandKeyMask | NSNumericPadKeyMask);

        // on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
        if (keyCode >= NSUpArrowFunctionKey &&
        keyCode <= NSRightArrowFunctionKey) {
                theModifiers |= NSNumericPadKeyMask;
    }
    if (keyString) {
        [keyString release];
    }
    keyString = [[NSString stringWithFormat:@"0x%x-0x%x", keyCode,
                               theModifiers] retain];

    [keyPress setStringValue:[iTermKeyBindingMgr formatKeyCombination:keyString]];
}

- (void)hotkeyKeyDown:(NSEvent*)event
{
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    // turn off all the other modifier bits we don't care about
    unsigned int theModifiers = keyMods &
    (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask |
     NSCommandKeyMask | NSNumericPadKeyMask);

    // on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
    if (keyChar >= NSUpArrowFunctionKey &&
        keyChar <= NSRightArrowFunctionKey) {
        theModifiers |= NSNumericPadKeyMask;
    }
    defaultHotkeyChar = keyChar;
    defaultHotkeyCode = keyCode;
    defaultHotkeyModifiers = keyMods;
    [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", keyChar, keyMods]]];
    [[iTermController sharedInstance] registerHotkey:keyCode modifiers:theModifiers];
}

- (void)updateValueToSend
{
    int tag = [[action selectedItem] tag];
    if (tag == KEY_ACTION_HEX_CODE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"ex: 0x7f"];
        [escPlus setHidden:YES];
    } else if (tag == KEY_ACTION_TEXT) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"Enter value to send"];
        [escPlus setHidden:YES];
    } else if (tag == KEY_ACTION_ESCAPE_SEQUENCE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"characters to send"];
        [escPlus setHidden:NO];
    } else {
        [valueToSend setHidden:YES];
        [valueToSend setStringValue:@""];
        [escPlus setHidden:YES];
    }
}

- (IBAction)actionChanged:(id)sender
{
    [self updateValueToSend];
}

- (NSWindow*)keySheet
{
    return editKeyMappingWindow;
}

- (IBAction)addNewMapping:(id)sender
{
    if (keyString) {
        [keyString release];
    }
    [keyPress setStringValue:@""];
    keyString = [[NSString alloc] init];
    [action selectItemWithTag:KEY_ACTION_IGNORE];
    [valueToSend setStringValue:@""];
    [self updateValueToSend];
    newMapping = YES;

    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)removeMapping:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
    NSAssert(tempDict, @"Can't find node");
    [iTermKeyBindingMgr removeMappingAtIndex:[keyMappings selectedRow] inBookmark:tempDict];
    [dataSource setBookmark:tempDict withGuid:guid];
    [keyMappings reloadData];
}

- (void)setKeyMappingsToPreset:(NSString*)presetName
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");
    NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
    NSAssert(tempDict, @"Can't find node");
    [iTermKeyBindingMgr setKeyMappingsToPreset:presetName inBookmark:tempDict];
    [dataSource setBookmark:tempDict withGuid:guid];
    [keyMappings reloadData];
    [self bookmarkSettingChanged:nil];
}

- (IBAction)useBasicKeyMappings:(id)sender
{
    [self setKeyMappingsToPreset:@"Basic Defaults"];
}

- (IBAction)useXtermKeyMappings:(id)sender
{
    [self setKeyMappingsToPreset:@"xterm Defaults"];
}

- (void)_loadPresetColors:(NSString*)presetName
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");

        NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                            ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    NSDictionary* settings = [presetsDict objectForKey:presetName];
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];

    for (id colorName in settings) {
        NSDictionary* preset = [settings objectForKey:colorName];
        float r = [[preset objectForKey:@"Red Component"] floatValue];
        float g = [[preset objectForKey:@"Green Component"] floatValue];
        float b = [[preset objectForKey:@"Blue Component"] floatValue];
        NSColor* color = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
        NSAssert([newDict objectForKey:colorName], @"Missing color in existing dict");
        [newDict setObject:[ITAddressBookMgr encodeColor:color] forKey:colorName];
    }

    [dataSource setBookmark:newDict withGuid:guid];
    [self updateBookmarkFields:newDict];
    [self bookmarkSettingChanged:self];  // this causes existing sessions to be updated
}

- (IBAction)loadLightBackgroundPreset:(id)sender
{
    [self _loadPresetColors:@"Light Background"];
}

- (IBAction)loadDarkBackgroundPreset:(id)sender
{
    [self _loadPresetColors:@"Dark Background"];
}

- (IBAction)addBookmark:(id)sender
{
    NSMutableDictionary* newDict = [[NSMutableDictionary alloc] init];
    // Copy the default bookmark's settings in
    Bookmark* prototype = [dataSource defaultBookmark];
    if (!prototype) {
        [ITAddressBookMgr setDefaultsInBookmark:newDict];
    } else {
        [newDict setValuesForKeysWithDictionary:[dataSource defaultBookmark]];
    }
    [newDict setObject:@"New Bookmark" forKey:KEY_NAME];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    NSString* guid = [BookmarkModel freshGuid];
    [newDict setObject:guid forKey:KEY_GUID];
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove depreated attribute with side effects
    [newDict setObject:[NSArray arrayWithObjects:nil] forKey:KEY_TAGS];
    if ([[BookmarkModel sharedInstance] bookmark:newDict hasTag:@"bonjour"]) {
        [newDict removeObjectForKey:KEY_BONJOUR_GROUP];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE_ADDRESS];
        [newDict setObject:@"" forKey:KEY_COMMAND];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
        [newDict setObject:@"" forKey:KEY_WORKING_DIRECTORY];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
    }
    [dataSource addBookmark:newDict];
    [bookmarksTableView reloadData];
    [bookmarksTableView eraseQuery];
    [bookmarksTableView selectRowByGuid:guid];
    [bookmarksSettingsTabViewParent selectTabViewItem:bookmarkSettingsGeneralTab];
    [[self window] makeFirstResponder:bookmarkName];
    [bookmarkName selectText:self];
}

- (IBAction)removeBookmark:(id)sender
{
    if ([dataSource numberOfBookmarks] == 1) {
        NSBeep();
    } else {
        BOOL found = NO;
        int lastIndex = 0;
        int numRemoved = 0;
        for (NSString* guid in [bookmarksTableView selectedGuids]) {
            found = YES;
            int i = [bookmarksTableView selectedRow];
            if (i > lastIndex) {
                lastIndex = i;
            }
            ++numRemoved;
            [dataSource removeBookmarkWithGuid:guid];
        }
        [bookmarksTableView reloadData];
        int toSelect = lastIndex - numRemoved;
        if (toSelect < 0) {
            toSelect = 0;
        }
        [bookmarksTableView selectRowIndex:toSelect];
        if (!found) {
            NSBeep();
        }
    }
}

- (IBAction)setAsDefault:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    [dataSource setDefaultByGuid:guid];
}

- (IBAction)duplicateBookmark:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    Bookmark* bookmark = [dataSource bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    NSString* newName = [NSString stringWithFormat:@"Copy of %@", [newDict objectForKey:KEY_NAME]];

    [newDict setObject:newName forKey:KEY_NAME];
    [newDict setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
    [newDict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [dataSource addBookmark:newDict];
    [bookmarksTableView reloadData];
    [bookmarksTableView selectRowByGuid:[newDict objectForKey:KEY_GUID]];
}

#pragma mark NSTokenField delegate

- (NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(NSInteger *)selectedIndex
{
    if (tokenField != tags) {
        return nil;
    }

    NSArray *allTags = [[dataSource allTags] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *result = [[[NSMutableArray alloc] init] autorelease];
    for (NSString *aTag in allTags) {
        if ([aTag hasPrefix:substring]) {
            [result addObject:[aTag retain]];
        }
    }
    return result;
}

- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
{
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark NSTokenFieldCell delegate

- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell representedObjectForEditingString:(NSString *)editingString
{
    static BOOL running;
    if (!running) {
        running = YES;
        [self bookmarkSettingChanged:tags];
        running = NO;
    }
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark -

- (void)showBookmarks
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
    [toolbar setSelectedItemIdentifier:bookmarksToolbarId];
}

- (void)openToBookmark:(NSString*)guid
{
    [self run];
    [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];
    [self showBookmarks];
    [bookmarksTableView selectRowByGuid:guid];
    [bookmarksSettingsTabViewParent selectTabViewItem:bookmarkSettingsGeneralTab];
    [[self window] makeFirstResponder:bookmarkName];
}

- (IBAction)openCopyBookmarks:(id)sender
{
    [bulkCopyLabel setStringValue:[NSString stringWithFormat:@"From bookmark \"%@\", copy these settings:", [[dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]] objectForKey:KEY_NAME]]];
    [NSApp beginSheet:copyPanel
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)copyBookmarks:(id)sender
{
    NSString* srcGuid = [bookmarksTableView selectedGuid];
    if (!srcGuid) {
        NSBeep();
        return;
    }

    NSSet* destGuids = [copyTo selectedGuids];
    for (NSString* destGuid in destGuids) {
        if ([destGuid isEqualToString:srcGuid]) {
            continue;
        }

        if (![dataSource bookmarkWithGuid:destGuid]) {
            NSLog(@"Selected bookmark %@ doesn't exist", destGuid);
            continue;
        }

        if ([copyColors state] == NSOnState) {
            [self copyAttributes:BulkCopyColors fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyDisplay state] == NSOnState) {
            [self copyAttributes:BulkCopyDisplay fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyTerminal state] == NSOnState) {
            [self copyAttributes:BulkCopyTerminal fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyKeyboard state] == NSOnState) {
            [self copyAttributes:BulkCopyKeyboard fromBookmark:srcGuid toBookmark:destGuid];
        }
    }
    [NSApp endSheet:copyPanel];
}

- (void)copyAttributes:(BulkCopySettings)attributes fromBookmark:(NSString*)guid toBookmark:(NSString*)destGuid
{
    Bookmark* dest = [dataSource bookmarkWithGuid:destGuid];
    Bookmark* src = [[BookmarkModel sharedInstance] bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [[NSMutableDictionary alloc] initWithDictionary:dest];
    NSString** keys = NULL;
    NSString* colorsKeys[] = {
        KEY_FOREGROUND_COLOR,
        KEY_BACKGROUND_COLOR,
        KEY_BOLD_COLOR,
        KEY_SELECTION_COLOR,
        KEY_SELECTED_TEXT_COLOR,
        KEY_CURSOR_COLOR,
        KEY_CURSOR_TEXT_COLOR,
        KEY_ANSI_0_COLOR,
        KEY_ANSI_1_COLOR,
        KEY_ANSI_2_COLOR,
        KEY_ANSI_3_COLOR,
        KEY_ANSI_4_COLOR,
        KEY_ANSI_5_COLOR,
        KEY_ANSI_6_COLOR,
        KEY_ANSI_7_COLOR,
        KEY_ANSI_8_COLOR,
        KEY_ANSI_9_COLOR,
        KEY_ANSI_10_COLOR,
        KEY_ANSI_11_COLOR,
        KEY_ANSI_12_COLOR,
        KEY_ANSI_13_COLOR,
        KEY_ANSI_14_COLOR,
        KEY_ANSI_15_COLOR,
        nil
    };
    NSString* displayKeys[] = {
        KEY_ROWS,
        KEY_COLUMNS,
        KEY_NORMAL_FONT,
        KEY_NON_ASCII_FONT,
        KEY_HORIZONTAL_SPACING,
        KEY_VERTICAL_SPACING,
        KEY_BLINKING_CURSOR,
        KEY_DISABLE_BOLD,
        KEY_TRANSPARENCY,
        KEY_BLUR,
        KEY_ANTI_ALIASING,
        KEY_BACKGROUND_IMAGE_LOCATION,
        nil
    };
    NSString* terminalKeys[] = {
        KEY_DISABLE_WINDOW_RESIZING,
        KEY_SYNC_TITLE,
        KEY_CLOSE_SESSIONS_ON_END,
        KEY_AMBIGUOUS_DOUBLE_WIDTH,
        KEY_SILENCE_BELL,
        KEY_VISUAL_BELL,
        KEY_XTERM_MOUSE_REPORTING,
        KEY_BOOKMARK_GROWL_NOTIFICATIONS,
        KEY_CHARACTER_ENCODING,
        KEY_SCROLLBACK_LINES,
        KEY_TERMINAL_TYPE,
        KEY_SEND_CODE_WHEN_IDLE,
        KEY_IDLE_CODE,
        nil
    };
    NSString* keyboardKeys[] = {
        KEY_KEYBOARD_MAP,
        KEY_OPTION_KEY_SENDS,
        nil
    };
    switch (attributes) {
        case BulkCopyColors:
            keys = colorsKeys;
            break;
        case BulkCopyDisplay:
            keys = displayKeys;
            break;
        case BulkCopyTerminal:
            keys = terminalKeys;
            break;
        case BulkCopyKeyboard:
            keys = keyboardKeys;
            break;
        default:
            NSLog(@"Unexpected copy attribute %d", (int)attributes);
            return;
    }

    for (int i = 0; keys[i]; ++i) {
        id srcValue = [src objectForKey:keys[i]];
        if (srcValue) {
            [newDict setObject:srcValue forKey:keys[i]];
        } else {
            [newDict removeObjectForKey:keys[i]];
        }
    }

    [dataSource setBookmark:newDict withGuid:[dest objectForKey:KEY_GUID]];
}

- (IBAction)cancelCopyBookmarks:(id)sender
{
    [NSApp endSheet:copyPanel];
}

@end


@implementation PreferencePanel (Private)

- (void)_reloadURLHandlers:(NSNotification *)aNotification
{
    [bookmarksForUrlsTable reloadData];
}

@end
