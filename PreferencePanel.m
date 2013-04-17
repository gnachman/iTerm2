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

#include <stdlib.h>
#import "PreferencePanel.h"
#import "NSStringITerm.h"
#import "iTermController.h"
#import "ITAddressBookMgr.h"
#import "iTermKeyBindingMgr.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"
#import "ProfileModel.h"
#import "PasteboardHistory.h"
#import "SessionView.h"
#import "WindowArrangements.h"
#import "TriggerController.h"
#import "SmartSelectionController.h"
#import "TrouterPrefsController.h"
#import "PointerPrefsController.h"
#import "iTermFontPanel.h"

#define CUSTOM_COLOR_PRESETS @"Custom Color Presets"
#define HOTKEY_WINDOW_GENERATED_PROFILE_NAME @"Hotkey Window"
NSString* kDeleteKeyString = @"0x7f-0x0";

static float versionNumber;

@interface NSFileManager (TemporaryDirectory)

- (NSString *)temporaryDirectory;

@end
@implementation NSFileManager (TemporaryDirectory)

- (NSString *)temporaryDirectory
{
    // Create a unique directory in the system temporary directory
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:guid];
    if (![self createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]) {
        return nil;
    }
    return path;
}

@end

@implementation PreferencePanel

+ (PreferencePanel*)sharedInstance;
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sharedInstance]
                                     userDefaults:[NSUserDefaults standardUserDefaults]];
        shared->oneBookmarkMode = NO;
    }

    return shared;
}

+ (PreferencePanel*)sessionsInstance;
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sessionsInstance]
                                     userDefaults:nil];
        shared->oneBookmarkMode = YES;
    }

    return shared;
}


/*
 Static method to copy old preferences file, iTerm.plist or net.sourceforge.iTerm.plist, to new
 preferences file, com.googlecode.iterm2.plist
 */
+ (BOOL)migratePreferences
{
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
    [mgr copyItemAtPath:source toPath:newPrefs error:nil];
    [NSUserDefaults resetStandardUserDefaults];
    return (YES);
}

- (id)initWithDataSource:(ProfileModel*)model userDefaults:(NSUserDefaults*)userDefaults
{
    unsigned int storedMajorVersion = 0, storedMinorVersion = 0, storedMicroVersion = 0;

    self = [super init];
    dataSource = model;
    prefs = userDefaults;
    oneBookmarkOnly = NO;
    if (userDefaults) {
        [self loadPrefs];
    }
    // Override smooth scrolling, which breaks various things (such as the
    // assumption, when detectUserScroll is called, that scrolls happen
    // immediately), and generally sucks with a terminal.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSScrollAnimationEnabled"];

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_savedArrangementChanged:)
                                                 name:@"iTermSavedArrangementChanged"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyBindingsChanged)
                                                 name:@"iTermKeyBindingsChanged"
                                               object:nil];
    return (self);
}

- (void)_savedArrangementChanged:(id)sender
{
    [openArrangementAtStartup setState:defaultOpenArrangementAtStartup ? NSOnState : NSOffState];
    [openArrangementAtStartup setEnabled:[WindowArrangements count] > 0];
    if ([WindowArrangements count] == 0) {
        [openArrangementAtStartup setState:NO];
    }
}

- (void)setOneBookmarkOnly
{
    oneBookmarkOnly = YES;
    [self showBookmarks];
    [toolbar setVisible:NO];
    [editAdvancedConfigButton setHidden:YES];
    [bookmarksTableView setHidden:YES];
    [addBookmarkButton setHidden:YES];
    [removeBookmarkButton setHidden:YES];
    [bookmarksPopup setHidden:YES];
    [bookmarkDirectory setHidden:YES];
    [bookmarkShortcutKeyLabel setHidden:YES];
    [bookmarkShortcutKeyModifiersLabel setHidden:YES];
    [bookmarkTagsLabel setHidden:YES];
    [bookmarkCommandLabel setHidden:YES];
    [initialTextLabel setHidden:YES];
    [bookmarkDirectoryLabel setHidden:YES];
    [bookmarkShortcutKey setHidden:YES];
    [tags setHidden:YES];
    [bookmarkCommandType setHidden:YES];
    [bookmarkCommand setHidden:YES];
    [initialText setHidden:YES];
    [bookmarkDirectoryType setHidden:YES];
    [bookmarkDirectory setHidden:YES];
    [bookmarkUrlSchemes setHidden:YES];
    [bookmarkUrlSchemesHeaderLabel setHidden:YES];
    [bookmarkUrlSchemesLabel setHidden:YES];
    [copyToProfileButton setHidden:NO];
    [setProfileLabel setHidden:NO];
    [setProfileBookmarkListView setHidden:NO];
    [changeProfileButton setHidden:NO];

    [columnsLabel setTextColor:[NSColor disabledControlTextColor]];
    [rowsLabel setTextColor:[NSColor disabledControlTextColor]];
    [columnsField setEnabled:NO];
    [rowsField setEnabled:NO];
    [windowTypeButton setEnabled:NO];
    [screenLabel setTextColor:[NSColor disabledControlTextColor]];
    [screenButton setEnabled:NO];
    [spaceButton setEnabled:NO];
    [spaceLabel setTextColor:[NSColor disabledControlTextColor]];
    [windowTypeLabel setTextColor:[NSColor disabledControlTextColor]];
    [newWindowttributesHeader setTextColor:[NSColor disabledControlTextColor]];

    NSRect newFrame = [bookmarksSettingsTabViewParent frame];
    newFrame.origin.x = 0;
    [bookmarksSettingsTabViewParent setFrame:newFrame];

    newFrame = [[self window] frame];
    newFrame.size.width = [bookmarksSettingsTabViewParent frame].size.width + 26;
    [[self window] setFrame:newFrame display:YES];
}

- (void)_addColorPresetsInDict:(NSDictionary*)presetsDict toMenu:(NSMenu*)theMenu
{
    for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:key action:@selector(loadColorPreset:) keyEquivalent:@""];
        [theMenu addItem:presetItem];
        [presetItem release];
    }
}

- (void)_rebuildColorPresetsMenu
{
    while ([presetsMenu numberOfItems] > 1) {
        [presetsMenu removeItemAtIndex:1];
    }

    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                            ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    [self _addColorPresetsInDict:presetsDict toMenu:presetsMenu];

    NSDictionary* customPresets = [[NSUserDefaults standardUserDefaults] objectForKey:CUSTOM_COLOR_PRESETS];
    if (customPresets && [customPresets count] > 0) {
        [presetsMenu addItem:[NSMenuItem separatorItem]];
        [self _addColorPresetsInDict:customPresets toMenu:presetsMenu];
    }

    [presetsMenu addItem:[NSMenuItem separatorItem]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Import..."
                                                     action:@selector(importColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Export..."
                                                     action:@selector(exportColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Delete Preset..."
                                                     action:@selector(deleteColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Visit Online Gallery"
                                                     action:@selector(visitGallery:)
                                              keyEquivalent:@""] autorelease]];
}

- (void)_addColorPreset:(NSString*)presetName withColors:(NSDictionary*)theDict
{
    NSMutableDictionary* customPresets = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:CUSTOM_COLOR_PRESETS]];
    if (!customPresets) {
        customPresets = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    int i = 1;
    NSString* temp = presetName;
    while ([customPresets objectForKey:temp]) {
        ++i;
        temp = [NSString stringWithFormat:@"%@ (%d)", presetName, i];
    }
    [customPresets setObject:theDict forKey:temp];
    [[NSUserDefaults standardUserDefaults] setObject:customPresets forKey:CUSTOM_COLOR_PRESETS];

    [self _rebuildColorPresetsMenu];
}

- (NSString*)_presetNameFromFilename:(NSString*)filename
{
    return [[filename stringByDeletingPathExtension] lastPathComponent];
}

- (BOOL)importColorPresetFromFile:(NSString*)filename
{
    NSDictionary* aDict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (!aDict) {
        NSRunAlertPanel(@"Import Failed.",
                        @"The selected file could not be read or did not contain a valid color scheme.",
                        @"OK",
                        nil,
                        nil,
                        nil);
        return NO;
    } else {
        [self _addColorPreset:[self _presetNameFromFilename:filename]
                   withColors:aDict];
        return YES;
    }
}

- (void)importColorPreset:(id)sender
{
    // Create the File Open Dialog class.
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];

    // Set options.
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:NO];
    [openDlg setAllowsMultipleSelection:YES];
    [openDlg setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    if ([openDlg runModalForDirectory:nil file:nil] == NSOKButton) {
        // Get an array containing the full filenames of all
        // files and directories selected.
        for (NSString* filename in [openDlg filenames]) {
            [self importColorPresetFromFile:filename];
        }
    }
}

- (void)_exportColorPresetToFile:(NSString*)filename
{
    NSArray* colorKeys = [NSArray arrayWithObjects:
                          @"Ansi 0 Color",
                          @"Ansi 1 Color",
                          @"Ansi 2 Color",
                          @"Ansi 3 Color",
                          @"Ansi 4 Color",
                          @"Ansi 5 Color",
                          @"Ansi 6 Color",
                          @"Ansi 7 Color",
                          @"Ansi 8 Color",
                          @"Ansi 9 Color",
                          @"Ansi 10 Color",
                          @"Ansi 11 Color",
                          @"Ansi 12 Color",
                          @"Ansi 13 Color",
                          @"Ansi 14 Color",
                          @"Ansi 15 Color",
                          @"Foreground Color",
                          @"Background Color",
                          @"Bold Color",
                          @"Selection Color",
                          @"Selected Text Color",
                          @"Cursor Color",
                          @"Cursor Text Color",
                          nil];
    NSColorWell* wells[] = {
        ansi0Color,
        ansi1Color,
        ansi2Color,
        ansi3Color,
        ansi4Color,
        ansi5Color,
        ansi6Color,
        ansi7Color,
        ansi8Color,
        ansi9Color,
        ansi10Color,
        ansi11Color,
        ansi12Color,
        ansi13Color,
        ansi14Color,
        ansi15Color,
        foregroundColor,
        backgroundColor,
        boldColor,
        selectionColor,
        selectedTextColor,
        cursorColor,
        cursorTextColor
    };
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    int i = 0;
    for (NSString* colorKey in colorKeys) {
        NSColor* theColor = [[wells[i++] color] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        double r = [theColor redComponent];
        double g = [theColor greenComponent];
        double b = [theColor blueComponent];

        NSDictionary* colorDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithDouble:r], @"Red Component",
                                   [NSNumber numberWithDouble:g], @"Green Component",
                                   [NSNumber numberWithDouble:b], @"Blue Component",
                                   nil];
        [theDict setObject:colorDict forKey:colorKey];
    }
    if (![theDict writeToFile:filename atomically:NO]) {
        NSRunAlertPanel(@"Save Failed.",
                        [NSString stringWithFormat:@"Could not save to %@", filename],
                        @"OK",
                        nil,
                        nil,
                        nil);
    }
}

- (void)exportColorPreset:(id)sender
{
    // Create the File Open Dialog class.
    NSSavePanel* saveDlg = [NSSavePanel savePanel];

    // Set options.
    [saveDlg setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    if ([saveDlg runModalForDirectory:nil file:nil] == NSOKButton) {
        [self _exportColorPresetToFile:[saveDlg filename]];
    }
}

- (void)deleteColorPreset:(id)sender
{
    NSDictionary* customPresets = [[NSUserDefaults standardUserDefaults] objectForKey:CUSTOM_COLOR_PRESETS];
    if (!customPresets || [customPresets count] == 0) {
        NSRunAlertPanel(@"No deletable color presets.",
                        @"You cannot erase the built-in presets and no custom presets have been imported.",
                        @"OK",
                        nil,
                        nil);
        return;
    }

    NSAlert *alert = [NSAlert alertWithMessageText:@"Select a preset to delete:"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];

    NSPopUpButton* pub = [[[NSPopUpButton alloc] init] autorelease];
    for (NSString* key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [pub addItemWithTitle:key];
    }
    [pub sizeToFit];
    [alert setAccessoryView:pub];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        NSMutableDictionary* newCustom = [NSMutableDictionary dictionaryWithDictionary:customPresets];
        [newCustom removeObjectForKey:[[pub selectedItem] title]];
        [[NSUserDefaults standardUserDefaults] setObject:newCustom
                                                  forKey:CUSTOM_COLOR_PRESETS];
        [self _rebuildColorPresetsMenu];
    }
}

- (void)visitGallery:(id)sender
{
    NSString* COLOR_GALLERY_URL = @"http://www.iterm2.com/colorgallery";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:COLOR_GALLERY_URL]];
}

- (BOOL)_dirIsWritable:(NSString *)dir
{
    if ([[dir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
        return NO;
    }

    NSString *filename = [NSString stringWithFormat:@"%@/.testwritable.%d", dir, (int)getpid()];
    NSError *error = nil;
    [@"test" writeToFile:filename
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:&error];
    if (error) {
        return NO;
    }
    unlink([filename UTF8String]);
    return YES;
}

- (BOOL)_logDirIsWritable
{
    return [self _dirIsWritable:[logDir stringValue]];
}

- (void)_updateLogDirWarning
{
    [logDirWarning setHidden:[autoLog state] == NSOffState || [self _logDirIsWritable]];
}

- (BOOL)_prefsDirIsWritable
{
    return [self _dirIsWritable:[defaultPrefsCustomFolder stringByExpandingTildeInPath]];
}

- (BOOL)_stringIsUrlLike:(NSString *)theString {
    return [theString hasPrefix:@"http://"] || [theString hasPrefix:@"https://"];
}

- (void)_updatePrefsDirWarning
{
    if ([self _stringIsUrlLike:defaultPrefsCustomFolder] &&
        [NSURL URLWithString:defaultPrefsCustomFolder]) {
        // Don't warn about URLs, too expensive to check
        [prefsDirWarning setHidden:YES];
        return;
    }
    [prefsDirWarning setHidden:!defaultLoadPrefsFromCustomFolder || [self _prefsDirIsWritable]];
}

- (void)setScreens
{
    int selectedTag = [screenButton selectedTag];
    [screenButton removeAllItems];
    int i = 0;
    [screenButton addItemWithTitle:@"No Preference"];
    [[screenButton lastItem] setTag:-1];
    for (NSScreen* screen in [NSScreen screens]) {
        if (i == 0) {
            [screenButton addItemWithTitle:[NSString stringWithFormat:@"Main Screen", i]];
        } else {
            [screenButton addItemWithTitle:[NSString stringWithFormat:@"Screen %d", i+1]];
        }
        [[screenButton lastItem] setTag:i];
        i++;
    }
    if (selectedTag >= 0 && selectedTag < i) {
        [screenButton selectItemWithTag:selectedTag];
    } else {
        [screenButton selectItemWithTag:-1];
    }
    if ([windowTypeButton selectedTag] == WINDOW_TYPE_NORMAL) {
        [screenButton setEnabled:NO];
        [screenLabel setTextColor:[NSColor disabledControlTextColor]];
        [screenButton selectItemWithTag:-1];
    } else if (!oneBookmarkOnly) {
        [screenButton setEnabled:YES];
        [screenLabel setTextColor:[NSColor blackColor]];
    }
}

- (void)awakeFromNib
{
    [self window];
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    NSAssert(bookmarksTableView, @"Null table view");
    [bookmarksTableView setUnderlyingDatasource:dataSource];
    bookmarksToolbarId = [bookmarksToolbarItem itemIdentifier];
    globalToolbarId = [globalToolbarItem itemIdentifier];
    appearanceToolbarId = [appearanceToolbarItem itemIdentifier];
    keyboardToolbarId = [keyboardToolbarItem itemIdentifier];
    arrangementsToolbarId = [arrangementsToolbarItem itemIdentifier];
    mouseToolbarId = [mouseToolbarItem itemIdentifier];
  
    [globalToolbarItem setEnabled:YES];
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
    [self setScreens];

    [keyMappings setDoubleAction:@selector(editKeyMapping:)];
    [globalKeyMappings setDoubleAction:@selector(editKeyMapping:)];
    keyString = nil;

    [copyTo allowMultipleSelections];

    // Add presets to preset color selection.
    [self _rebuildColorPresetsMenu];

    // Add preset keybindings to button-popup-list.
    NSArray* presetArray = [iTermKeyBindingMgr presetKeyMappingsNames];
    if (presetArray != nil) {
        [presetsPopupButton addItemsWithTitles:presetArray];
    } else {
        [presetsPopupButton setEnabled:NO];
        [presetsErrorLabel setFont:[NSFont boldSystemFontOfSize:12]];
        [presetsErrorLabel setStringValue:@"PresetKeyMappings.plist failed to load"];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowWillCloseNotification:)
                                                 name:NSWindowWillCloseNotification object: [self window]];
    if (oneBookmarkMode) {
        [self setOneBookmarkOnly];
    }
    [[tags cell] setDelegate:self];
    [tags setDelegate:self];

    if (IsLionOrLater()) {
        [lionStyleFullscreen setHidden:NO];
    } else {
        [lionStyleFullscreen setHidden:YES];
    }
    [initialText setContinuous:YES];
    [blurRadius setContinuous:YES];
    [transparency setContinuous:YES];
    [blend setContinuous:YES];
    [dimmingAmount setContinuous:YES];
    [minimumContrast setContinuous:YES];

    [prefsCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
    [browseCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
    [pushToCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
    [self _updatePrefsDirWarning];
}

- (void)handleWindowWillCloseNotification:(NSNotification *)notification
{
    // This is so tags get saved because Cocoa doesn't notify you that the
    // field changed unless the user presses enter twice in it (!).
    [self bookmarkSettingChanged:nil];
}

- (void)genericCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [action setTitle:@"Ignore"];
    [sheet close];
}

- (BOOL)_originatorIsBookmark:(id)originator
{
    return originator == addNewMapping || originator == keyMappings;
}

- (void)setAdvancedBookmarkMatrix:(NSMatrix *)matrix withValue:(NSString *)value
{
    if ([value isEqualToString:@"Yes"]) {
        [matrix selectCellWithTag:0];
    } else if ([value isEqualToString:@"Recycle"]) {
        [matrix selectCellWithTag:2];
    } else {
        [matrix selectCellWithTag:1];
    }
}

- (void)safelySetStringValue:(NSString *)value in:(NSTextField *)field
{
    if (value) {
        [field setStringValue:value];
    } else {
        [field setStringValue:@""];
    }
}

- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender
{
    // Populate initial values
    Profile* bookmark = [dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]];

    [self setAdvancedBookmarkMatrix:awdsWindowDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_WIN_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_WIN_DIRECTORY] 
                            in:awdsWindowDirectory];

    [self setAdvancedBookmarkMatrix:awdsTabDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_TAB_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_TAB_DIRECTORY]
                            in:awdsTabDirectory];

    [self setAdvancedBookmarkMatrix:awdsPaneDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_PANE_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_PANE_DIRECTORY]
                            in:awdsPaneDirectory];


    [NSApp beginSheet:advancedWorkingDirSheet_
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedWorkingDirSheetClosed:returnCode:contextInfo:)
          contextInfo:nil];
}

- (void)setValueInBookmark:(NSMutableDictionary *)dict
        forAdvancedWorkingDirMatrix:(NSMatrix *)matrix
        key:(NSString *)key
{
    NSString *value;
    NSString *values[] = { @"Yes", @"No", @"Recycle" };
    value = values[matrix.selectedTag];
    [dict setObject:value forKey:key];
}

- (IBAction)closeAdvancedWorkingDirSheet:(id)sender
{
    Profile* bookmark = [dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsWindowDirectoryType
          key:KEY_AWDS_WIN_OPTION];
    [dict setObject:[awdsWindowDirectory stringValue] forKey:KEY_AWDS_WIN_DIRECTORY];

    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsTabDirectoryType
          key:KEY_AWDS_TAB_OPTION];
    [dict setObject:[awdsTabDirectory stringValue] forKey:KEY_AWDS_TAB_DIRECTORY];

    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsPaneDirectoryType
          key:KEY_AWDS_PANE_OPTION];
    [dict setObject:[awdsPaneDirectory stringValue] forKey:KEY_AWDS_PANE_DIRECTORY];

    [dataSource setBookmark:dict withGuid:[bookmark objectForKey:KEY_GUID]];
    [self bookmarkSettingChanged:nil];

    [NSApp endSheet:advancedWorkingDirSheet_];
}

- (void)advancedWorkingDirSheetClosed:(NSWindow *)sheet
                           returnCode:(int)returnCode
                          contextInfo:(void *)contextInfo
{
    [sheet close];
}

- (IBAction)editSmartSelection:(id)sender
{
    [smartSelectionWindowController_ window];
    [smartSelectionWindowController_ windowWillOpen];
    [NSApp beginSheet:[smartSelectionWindowController_ window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeSmartSelectionSheet:(id)sender
{
    [NSApp endSheet:[smartSelectionWindowController_ window]];
}

- (void)advancedTabCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet close];
}

- (IBAction)editTriggers:(id)sender
{
    [NSApp beginSheet:[triggerWindowController_ window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeTriggersSheet:(id)sender
{
    [NSApp endSheet:[triggerWindowController_ window]];
}

- (IBAction)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        [self closeWindow:self];
    }
}

+ (void)populatePopUpButtonWithBookmarks:(NSPopUpButton*)button selectedGuid:(NSString*)selectedGuid
{
    int selectedIndex = 0;
    int i = 0;
    [button removeAllItems];
    NSArray* bookmarks = [[ProfileModel sharedInstance] bookmarks];
    for (Profile* bookmark in bookmarks) {
        int j = 0;
        NSString* temp;
        do {
            if (j == 0) {
                temp = [bookmark objectForKey:KEY_NAME];
            } else {
                temp = [NSString stringWithFormat:@"%@ (%d)", [bookmark objectForKey:KEY_NAME], j];
            }
            j++;
        } while ([button indexOfItemWithTitle:temp] != -1);
        [button addItemWithTitle:temp];
        NSMenuItem* item = [button lastItem];
        [item setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
        if ([[item representedObject] isEqualToString:selectedGuid]) {
            selectedIndex = i;
        }
        i++;
    }
    [button selectItemAtIndex:selectedIndex];
}

+ (void)recursiveAddMenu:(NSMenu *)menu
            toButtonMenu:(NSMenu *)buttonMenu
                   depth:(int)depth{
    for (NSMenuItem* item in [menu itemArray]) {
        if ([item isSeparatorItem]) {
            continue;
        }
        if ([[item title] isEqualToString:@"Services"] ||  // exclude services menu
            isnumber([[item title] characterAtIndex:0])) {  // exclude windows in window menu
            continue;
        }
        NSMenuItem *theItem = [[[NSMenuItem alloc] init] autorelease];
        [theItem setTitle:[item title]];
        [theItem setIndentationLevel:depth];
        if ([item hasSubmenu]) {
            if (depth == 0 && [[buttonMenu itemArray] count]) {
                [buttonMenu addItem:[NSMenuItem separatorItem]];
            }
            [theItem setEnabled:NO];
            [buttonMenu addItem:theItem];
            [PreferencePanel recursiveAddMenu:[item submenu]
                                 toButtonMenu:buttonMenu
                                        depth:depth + 1];
        } else {
            [buttonMenu addItem:theItem];
        }
    }
}

+ (void)populatePopUpButtonWithMenuItems:(NSPopUpButton *)button
                           selectedValue:(NSString *)selectedValue {
    [PreferencePanel recursiveAddMenu:[NSApp mainMenu]
                         toButtonMenu:[button menu]
                                depth:0];
    if (selectedValue) {
        NSMenuItem *theItem = [[button menu] itemWithTitle:selectedValue];
        if (theItem) {
            [button setTitle:selectedValue];
            [theItem setState:NSOnState];
        }
    }
}

- (void)editKeyMapping:(id)sender
{
    int rowIndex;
    modifyMappingOriginator = sender;
    if ([self _originatorIsBookmark:sender]) {
        rowIndex = [keyMappings selectedRow];
    } else {
        rowIndex = [globalKeyMappings selectedRow];
    }
    if (rowIndex < 0) {
        [self addNewMapping:sender];
        return;
    }
    [keyPress setStringValue:[self formattedKeyCombinationForRow:rowIndex originator:sender]];
    if (keyString) {
        [keyString release];
    }
    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    for (NSMenuItem* item in [action itemArray]) {
        [item setState:NSOffState];
    }
    keyString = [[self keyComboAtIndex:rowIndex originator:sender] copy];
    int theTag = [[[self keyInfoAtIndex:rowIndex originator:sender] objectForKey:@"Action"] intValue];
    [action selectItemWithTag:theTag];
    // Can't search for an item with tag 0 using the API, so search manually.
    for (NSMenuItem* anItem in [[action menu] itemArray]) {
        if (![anItem isSeparatorItem] && [anItem tag] == theTag) {
            [action setTitle:[anItem title]];
            break;
        }
    }
    NSString* text = [[self keyInfoAtIndex:rowIndex originator:sender] objectForKey:@"Text"];
    [valueToSend setStringValue:text ? text : @""];
    [PreferencePanel populatePopUpButtonWithBookmarks:bookmarkPopupButton
                                         selectedGuid:text];
    [PreferencePanel populatePopUpButtonWithMenuItems:menuToSelect
                                         selectedValue:text];
    [self updateValueToSend];
    newMapping = NO;
    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)changeProfile:(id)sender
{
    NSString* origGuid = [bookmarksTableView selectedGuid];
    Profile* origBookmark = [dataSource bookmarkWithGuid:origGuid];
    NSString *theName = [[[origBookmark objectForKey:KEY_NAME] copy] autorelease];
    NSString *guid = [setProfileBookmarkListView selectedGuid];
    Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    [dict setObject:theName forKey:KEY_NAME];
    [dict setObject:origGuid forKey:KEY_GUID];

    // Change the dict in the sessions bookmarks so that if you copy it back, it gets copied to
    // the new profile.
    [dict setObject:guid forKey:KEY_ORIGINAL_GUID];
    [dataSource setBookmark:dict withGuid:origGuid];

    [self updateBookmarkFields:dict];
    [self bookmarkSettingChanged:nil];
}

- (BOOL)_warnAboutDeleteOverride
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NeverWarnAboutDeleteOverride"] != nil) {
        return YES;
    }
    switch (NSRunAlertPanel(@"Some Profile Overrides the Delete Key",
                            @"Careful! You have at least one profile that has a key mapping for the Delete key. It will take precedence over this setting. Check your profiles' keyboard settings if Delete does not work as expected.",
                            @"OK",
                            @"Never warn me again",
                            @"Cancel",
                            nil)) {
        case NSAlertDefaultReturn:
            return YES;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:@"NeverWarnAboutDeleteOverride"];
            return YES;
        case NSAlertOtherReturn:
            return NO;
    }

    return YES;
}

- (BOOL)_warnAboutOverride
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NeverWarnAboutOverrides"] != nil) {
        return YES;
    }
    switch (NSRunAlertPanel(@"Overriding Global Shortcut",
                            @"The keyboard shortcut you have set for this profile will take precedence over an existing shortcut for the same key combination in a global shortcut.",
                            @"OK",
                            @"Never warn me again",
                            @"Cancel",
                            nil)) {
        case NSAlertDefaultReturn:
            return YES;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:@"NeverWarnAboutOverrides"];
            return YES;
        case NSAlertOtherReturn:
            return NO;
    }

    return YES;
}

- (BOOL)_warnAboutPossibleOverride
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NeverWarnAboutPossibleOverrides"] != nil) {
        return YES;
    }
    switch (NSRunAlertPanel(@"Some Profile Overrides this Shortcut",
                            @"The global keyboard shortcut you have set is overridden by at least one profile. Check your profiles' keyboard settings if it does not work as expected.",
                            @"OK",
                            @"Never warn me again",
                            @"Cancel",
                            nil)) {
        case NSAlertDefaultReturn:
            return YES;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:@"NeverWarnAboutPossibleOverrides"];
            return YES;
        case NSAlertOtherReturn:
            return NO;
    }

    return YES;
}

- (BOOL)_anyBookmarkHasKeyMapping:(NSString*)theString
{
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([iTermKeyBindingMgr haveKeyMappingForKeyString:theString inBookmark:bookmark]) {
            return YES;
        }
    }
    return NO;
}

- (IBAction)saveKeyMapping:(id)sender
{
    if ([[keyPress stringValue] length] == 0) {
        NSBeep();
        return;
    }
    NSMutableDictionary* dict;
    NSString* theParam = [valueToSend stringValue];
    int theAction = [[action selectedItem] tag];
    if (theAction == KEY_ACTION_SELECT_MENU_ITEM) {
        theParam = [[menuToSelect selectedItem] title];
    } else if (theAction == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
        theAction == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
        theAction == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
        theAction == KEY_ACTION_NEW_WINDOW_WITH_PROFILE) {
        theParam = [[bookmarkPopupButton selectedItem] representedObject];
    }
    if ([self _originatorIsBookmark:modifyMappingOriginator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        dict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
        NSAssert(dict, @"Can't find node");
        if ([iTermKeyBindingMgr haveGlobalKeyMappingForKeyString:keyString]) {
            if (![self _warnAboutOverride]) {
                return;
            }
        }

        [iTermKeyBindingMgr setMappingAtIndex:[keyMappings selectedRow]
                                       forKey:keyString
                                       action:theAction
                                        value:theParam
                                    createNew:newMapping
                                   inBookmark:dict];
        [dataSource setBookmark:dict withGuid:guid];
        [keyMappings reloadData];
        [self bookmarkSettingChanged:sender];
    } else {
        dict = [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalKeyMap]];
        if ([self _anyBookmarkHasKeyMapping:keyString]) {
            if (![self _warnAboutPossibleOverride]) {
                return;
            }
        }
        [iTermKeyBindingMgr setMappingAtIndex:[globalKeyMappings selectedRow]
                                       forKey:keyString
                                       action:theAction
                                        value:theParam
                                    createNew:newMapping
                                 inDictionary:dict];
        [iTermKeyBindingMgr setGlobalKeyMap:dict];
        [globalKeyMappings reloadData];
        [self settingChanged:nil];
    }

    [self closeKeyMapping:sender];
}

- (BOOL)keySheetIsOpen
{
    return [editKeyMappingWindow isVisible];
}

- (WindowArrangements *)arrangements
{
    return arrangements_;
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
    } else if ([itemIdentifier isEqual:appearanceToolbarId]) {
        return appearanceToolbarItem;
    } else if ([itemIdentifier isEqual:bookmarksToolbarId]) {
        return bookmarksToolbarItem;
    } else if ([itemIdentifier isEqual:keyboardToolbarId]) {
        return keyboardToolbarItem;
    } else if ([itemIdentifier isEqual:arrangementsToolbarId]) {
        return arrangementsToolbarItem;
    } else if ([itemIdentifier isEqual:mouseToolbarId]) {
        return mouseToolbarItem;
    } else {
        return nil;
    }
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId,
                                     appearanceToolbarId,
                                     bookmarksToolbarId,
                                     keyboardToolbarId,
                                     arrangementsToolbarId,
                                     mouseToolbarId,
                                     nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId, appearanceToolbarId, bookmarksToolbarId,
            keyboardToolbarId, arrangementsToolbarId, mouseToolbarId, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
    // Optional delegate method: Returns the identifiers of the subset of
    // toolbar items that are selectable.
    return [NSArray arrayWithObjects:globalToolbarId,
                                     appearanceToolbarId,
                                     bookmarksToolbarId,
                                     keyboardToolbarId,
                                     arrangementsToolbarId,
                                     mouseToolbarId,
                                     nil];
}

- (void)dealloc
{
    [defaultWordChars release];
    [super dealloc];
}

// Force the key binding for delete to be either ^H or absent.
- (void)_setDeleteKeyMapToCtrlH:(BOOL)sendCtrlH inBookmark:(NSMutableDictionary*)bookmark
{
    if (sendCtrlH) {
        [iTermKeyBindingMgr setMappingAtIndex:0
                                       forKey:kDeleteKeyString
                                       action:KEY_ACTION_SEND_C_H_BACKSPACE
                                        value:@""
                                    createNew:YES
                                   inBookmark:bookmark];
    } else {
        [iTermKeyBindingMgr removeMappingWithCode:0x7f
                                        modifiers:0
                                       inBookmark:bookmark];
    }
}

// Returns true if and only if there is a key mapping in the bookmark for delete
// to send exactly ^H.
- (BOOL)_deleteSendsCtrlHInBookmark:(Profile*)bookmark
{
    NSString* text;
    return ([iTermKeyBindingMgr localActionForKeyCode:0x7f
                                            modifiers:0
                                                 text:&text
                                          keyMappings:[bookmark objectForKey:KEY_KEYBOARD_MAP]] == KEY_ACTION_SEND_C_H_BACKSPACE);
}

- (void)readPreferences
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
    defaultOpenTmuxWindowsIn = [prefs objectForKey:@"OpenTmuxWindowsIn"]?[prefs integerForKey:@"OpenTmuxWindowsIn"]:OPEN_TMUX_WINDOWS_IN_WINDOWS;
    defaultAutoHideTmuxClientSession = [prefs objectForKey:@"AutoHideTmuxClientSession"] ? [[prefs objectForKey:@"AutoHideTmuxClientSession"] boolValue] : NO;
    defaultTabViewType=[prefs objectForKey:@"TabViewType"]?[prefs integerForKey:@"TabViewType"]:0;
    if (defaultTabViewType > 1) {
        defaultTabViewType = 0;
    }
    defaultAllowClipboardAccess=[prefs objectForKey:@"AllowClipboardAccess"]?[[prefs objectForKey:@"AllowClipboardAccess"] boolValue]:NO;
    defaultCopySelection=[prefs objectForKey:@"CopySelection"]?[[prefs objectForKey:@"CopySelection"] boolValue]:YES;
    defaultCopyLastNewline = [prefs objectForKey:@"CopyLastNewline"] ? [[prefs objectForKey:@"CopyLastNewline"] boolValue] : NO;
    defaultPasteFromClipboard=[prefs objectForKey:@"PasteFromClipboard"]?[[prefs objectForKey:@"PasteFromClipboard"] boolValue]:YES;
    defaultThreeFingerEmulatesMiddle=[prefs objectForKey:@"ThreeFingerEmulates"]?[[prefs objectForKey:@"ThreeFingerEmulates"] boolValue]:NO;
    defaultHideTab=[prefs objectForKey:@"HideTab"]?[[prefs objectForKey:@"HideTab"] boolValue]: YES;
    defaultPromptOnQuit = [prefs objectForKey:@"PromptOnQuit"]?[[prefs objectForKey:@"PromptOnQuit"] boolValue]: YES;
    defaultOnlyWhenMoreTabs = [prefs objectForKey:@"OnlyWhenMoreTabs"]?[[prefs objectForKey:@"OnlyWhenMoreTabs"] boolValue]: YES;
    defaultFocusFollowsMouse = [prefs objectForKey:@"FocusFollowsMouse"]?[[prefs objectForKey:@"FocusFollowsMouse"] boolValue]: NO;
    defaultTripleClickSelectsFullLines = [prefs objectForKey:@"TripleClickSelectsFullWrappedLines"] ? [[prefs objectForKey:@"TripleClickSelectsFullWrappedLines"] boolValue] : NO;
    defaultHotkeyTogglesWindow = [prefs objectForKey:@"HotKeyTogglesWindow"]?[[prefs objectForKey:@"HotKeyTogglesWindow"] boolValue]: NO;
    defaultHotKeyBookmarkGuid = [[prefs objectForKey:@"HotKeyBookmark"] copy];
    defaultEnableBonjour = [prefs objectForKey:@"EnableRendezvous"]?[[prefs objectForKey:@"EnableRendezvous"] boolValue]: NO;
    defaultCmdSelection = [prefs objectForKey:@"CommandSelection"]?[[prefs objectForKey:@"CommandSelection"] boolValue]: YES;
    defaultPassOnControlLeftClick = [prefs objectForKey:@"PassOnControlClick"]?[[prefs objectForKey:@"PassOnControlClick"] boolValue] : NO;
    defaultMaxVertically = [prefs objectForKey:@"MaxVertically"] ? [[prefs objectForKey:@"MaxVertically"] boolValue] : NO;
    defaultClosingHotkeySwitchesSpaces = [prefs objectForKey:@"ClosingHotkeySwitchesSpaces"] ? [[prefs objectForKey:@"ClosingHotkeySwitchesSpaces"] boolValue] : YES;
    defaultFsTabDelay = [prefs objectForKey:@"FsTabDelay"] ? [[prefs objectForKey:@"FsTabDelay"] floatValue] : 1.0;
    defaultUseCompactLabel = [prefs objectForKey:@"UseCompactLabel"]?[[prefs objectForKey:@"UseCompactLabel"] boolValue]: YES;
    defaultHideActivityIndicator = [prefs objectForKey:@"HideActivityIndicator"]?[[prefs objectForKey:@"HideActivityIndicator"] boolValue]: NO;
    defaultHighlightTabLabels = [prefs objectForKey:@"HighlightTabLabels"]?[[prefs objectForKey:@"HighlightTabLabels"] boolValue]: YES;
    defaultAdvancedFontRendering = [prefs objectForKey:@"HiddenAdvancedFontRendering"]?[[prefs objectForKey:@"HiddenAdvancedFontRendering"] boolValue] : NO;
    defaultStrokeThickness = [prefs objectForKey:@"HiddenAFRStrokeThickness"] ? [[prefs objectForKey:@"HiddenAFRStrokeThickness"] floatValue] : 0;
    [defaultWordChars release];
    defaultWordChars = [prefs objectForKey: @"WordCharacters"]?[[prefs objectForKey: @"WordCharacters"] retain]:@"/-+\\~_.";
    defaultTmuxDashboardLimit = [prefs objectForKey: @"TmuxDashboardLimit"]?[[prefs objectForKey:@"TmuxDashboardLimit"] intValue]:10;
    defaultOpenBookmark = [prefs objectForKey:@"OpenBookmark"]?[[prefs objectForKey:@"OpenBookmark"] boolValue]: NO;
    defaultQuitWhenAllWindowsClosed = [prefs objectForKey:@"QuitWhenAllWindowsClosed"]?[[prefs objectForKey:@"QuitWhenAllWindowsClosed"] boolValue]: NO;
    defaultCheckUpdate = [prefs objectForKey:@"SUEnableAutomaticChecks"]?[[prefs objectForKey:@"SUEnableAutomaticChecks"] boolValue]: YES;
    defaultHideScrollbar = [prefs objectForKey:@"HideScrollbar"]?[[prefs objectForKey:@"HideScrollbar"] boolValue]: NO;
    defaultShowPaneTitles = [prefs objectForKey:@"ShowPaneTitles"]?[[prefs objectForKey:@"ShowPaneTitles"] boolValue]: YES;
    defaultDisableFullscreenTransparency = [prefs objectForKey:@"DisableFullscreenTransparency"] ? [[prefs objectForKey:@"DisableFullscreenTransparency"] boolValue] : NO;
    defaultSmartPlacement = [prefs objectForKey:@"SmartPlacement"]?[[prefs objectForKey:@"SmartPlacement"] boolValue]: NO;
    defaultAdjustWindowForFontSizeChange = [prefs objectForKey:@"AdjustWindowForFontSizeChange"]?[[prefs objectForKey:@"AdjustWindowForFontSizeChange"] boolValue]: YES;
    defaultWindowNumber = [prefs objectForKey:@"WindowNumber"]?[[prefs objectForKey:@"WindowNumber"] boolValue]: YES;
    defaultJobName = [prefs objectForKey:@"JobName"]?[[prefs objectForKey:@"JobName"] boolValue]: YES;
    defaultShowBookmarkName = [prefs objectForKey:@"ShowBookmarkName"]?[[prefs objectForKey:@"ShowBookmarkName"] boolValue] : NO;
    defaultHotkey = [prefs objectForKey:@"Hotkey"]?[[prefs objectForKey:@"Hotkey"] boolValue]: NO;
    defaultHotkeyCode = [prefs objectForKey:@"HotkeyCode"]?[[prefs objectForKey:@"HotkeyCode"] intValue]: 0;
    defaultHotkeyChar = [prefs objectForKey:@"HotkeyChar"]?[[prefs objectForKey:@"HotkeyChar"] intValue]: 0;
    defaultHotkeyModifiers = [prefs objectForKey:@"HotkeyModifiers"]?[[prefs objectForKey:@"HotkeyModifiers"] intValue]: 0;
    defaultSavePasteHistory = [prefs objectForKey:@"SavePasteHistory"]?[[prefs objectForKey:@"SavePasteHistory"] boolValue]: NO;
    if ([WindowArrangements count] > 0) {
        defaultOpenArrangementAtStartup = [prefs objectForKey:@"OpenArrangementAtStartup"]?[[prefs objectForKey:@"OpenArrangementAtStartup"] boolValue]: NO;
    } else {
        defaultOpenArrangementAtStartup = NO;
    }
    defaultIrMemory = [prefs objectForKey:@"IRMemory"]?[[prefs objectForKey:@"IRMemory"] intValue] : 4;
    defaultCheckTestRelease = [prefs objectForKey:@"CheckTestRelease"]?[[prefs objectForKey:@"CheckTestRelease"] boolValue]: YES;
    defaultDimInactiveSplitPanes = [prefs objectForKey:@"DimInactiveSplitPanes"]?[[prefs objectForKey:@"DimInactiveSplitPanes"] boolValue]: YES;
    defaultDimBackgroundWindows = [prefs objectForKey:@"DimBackgroundWindows"]?[[prefs objectForKey:@"DimBackgroundWindows"] boolValue]: NO;
    defaultAnimateDimming = [prefs objectForKey:@"AnimateDimming"]?[[prefs objectForKey:@"AnimateDimming"] boolValue]: NO;
    defaultDimOnlyText = [prefs objectForKey:@"DimOnlyText"]?[[prefs objectForKey:@"DimOnlyText"] boolValue]: NO;
    defaultDimmingAmount = [prefs objectForKey:@"SplitPaneDimmingAmount"] ? [[prefs objectForKey:@"SplitPaneDimmingAmount"] floatValue] : 0.4;
    defaultShowWindowBorder = [[prefs objectForKey:@"UseBorder"] boolValue];
    defaultLionStyleFullscreen = [prefs objectForKey:@"UseLionStyleFullscreen"] ? [[prefs objectForKey:@"UseLionStyleFullscreen"] boolValue] : YES;
    defaultLoadPrefsFromCustomFolder = [prefs objectForKey:@"LoadPrefsFromCustomFolder"] ? [[prefs objectForKey:@"LoadPrefsFromCustomFolder"] boolValue] : NO;
    defaultPrefsCustomFolder = [prefs objectForKey:@"PrefsCustomFolder"] ? [prefs objectForKey:@"PrefsCustomFolder"] : @"";

    defaultControl = [prefs objectForKey:@"Control"] ? [[prefs objectForKey:@"Control"] intValue] : MOD_TAG_CONTROL;
    defaultLeftOption = [prefs objectForKey:@"LeftOption"] ? [[prefs objectForKey:@"LeftOption"] intValue] : MOD_TAG_LEFT_OPTION;
    defaultRightOption = [prefs objectForKey:@"RightOption"] ? [[prefs objectForKey:@"RightOption"] intValue] : MOD_TAG_RIGHT_OPTION;
    defaultLeftCommand = [prefs objectForKey:@"LeftCommand"] ? [[prefs objectForKey:@"LeftCommand"] intValue] : MOD_TAG_LEFT_COMMAND;
    defaultRightCommand = [prefs objectForKey:@"RightCommand"] ? [[prefs objectForKey:@"RightCommand"] intValue] : MOD_TAG_RIGHT_COMMAND;
    if ([self isAnyModifierRemapped]) {
        [[iTermController sharedInstance] beginRemappingModifiers];
    }
    defaultSwitchTabModifier = [prefs objectForKey:@"SwitchTabModifier"] ? [[prefs objectForKey:@"SwitchTabModifier"] intValue] : MOD_TAG_ANY_COMMAND;
    defaultSwitchWindowModifier = [prefs objectForKey:@"SwitchWindowModifier"] ? [[prefs objectForKey:@"SwitchWindowModifier"] intValue] : MOD_TAG_CMD_OPT;

    NSString *appCast = defaultCheckTestRelease ?
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
    [prefs setObject:appCast forKey:@"SUFeedURL"];

    // Migrate old-style (iTerm 0.x) URL handlers.
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
                    NSString* guid = [[dataSource profileAtIndex:theIndex] objectForKey:KEY_GUID];
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
            if ([dataSource indexOfProfileWithGuid:guid] >= 0) {
                [urlHandlersByGuid setObject:guid forKey:key];
            }
        }
    }
}

- (void)savePreferences
{
    if (!prefs) {
        // In one-bookmark mode there are no prefs but this function doesn't
        // affect bookmarks.
        return;
    }

    [prefs setBool:defaultAllowClipboardAccess forKey:@"AllowClipboardAccess"];
    [prefs setBool:defaultCopySelection forKey:@"CopySelection"];
    [prefs setBool:defaultCopyLastNewline forKey:@"CopyLastNewline"];
    [prefs setBool:defaultPasteFromClipboard forKey:@"PasteFromClipboard"];
    [prefs setBool:defaultThreeFingerEmulatesMiddle forKey:@"ThreeFingerEmulates"];
    [prefs setBool:defaultHideTab forKey:@"HideTab"];
    [prefs setInteger:defaultWindowStyle forKey:@"WindowStyle"];
	[prefs setInteger:defaultOpenTmuxWindowsIn forKey:@"OpenTmuxWindowsIn"];
    [prefs setBool:defaultAutoHideTmuxClientSession forKey:@"AutoHideTmuxClientSession"];
    [prefs setInteger:defaultTabViewType forKey:@"TabViewType"];
    [prefs setBool:defaultPromptOnQuit forKey:@"PromptOnQuit"];
    [prefs setBool:defaultOnlyWhenMoreTabs forKey:@"OnlyWhenMoreTabs"];
    [prefs setBool:defaultFocusFollowsMouse forKey:@"FocusFollowsMouse"];
    [prefs setBool:defaultTripleClickSelectsFullLines forKey:@"TripleClickSelectsFullWrappedLines"];
    [prefs setBool:defaultHotkeyTogglesWindow forKey:@"HotKeyTogglesWindow"];
    [prefs setValue:defaultHotKeyBookmarkGuid forKey:@"HotKeyBookmark"];
    [prefs setBool:defaultEnableBonjour forKey:@"EnableRendezvous"];
    [prefs setBool:defaultCmdSelection forKey:@"CommandSelection"];
    [prefs setFloat:defaultFsTabDelay forKey:@"FsTabDelay"];
    [prefs setBool:defaultPassOnControlLeftClick forKey:@"PassOnControlClick"];
    [prefs setBool:defaultMaxVertically forKey:@"MaxVertically"];
    [prefs setBool:defaultClosingHotkeySwitchesSpaces forKey:@"ClosingHotkeySwitchesSpaces"];
    [prefs setBool:defaultUseCompactLabel forKey:@"UseCompactLabel"];
    [prefs setBool:defaultHideActivityIndicator forKey:@"HideActivityIndicator"];
    [prefs setBool:defaultHighlightTabLabels forKey:@"HighlightTabLabels"];
    [prefs setBool:defaultAdvancedFontRendering forKey:@"HiddenAdvancedFontRendering"];
    [prefs setFloat:defaultStrokeThickness forKey:@"HiddenAFRStrokeThickness"];
    [prefs setObject:defaultWordChars forKey: @"WordCharacters"];
    [prefs setObject:[NSNumber numberWithInt:defaultTmuxDashboardLimit]
			  forKey:@"TmuxDashboardLimit"];
    [prefs setBool:defaultOpenBookmark forKey:@"OpenBookmark"];
    [prefs setObject:[dataSource rawData] forKey: @"New Bookmarks"];
    [prefs setBool:defaultQuitWhenAllWindowsClosed forKey:@"QuitWhenAllWindowsClosed"];
    [prefs setBool:defaultCheckUpdate forKey:@"SUEnableAutomaticChecks"];
    [prefs setBool:defaultHideScrollbar forKey:@"HideScrollbar"];
    [prefs setBool:defaultShowPaneTitles forKey:@"ShowPaneTitles"];
    [prefs setBool:defaultDisableFullscreenTransparency forKey:@"DisableFullscreenTransparency"];
    [prefs setBool:defaultSmartPlacement forKey:@"SmartPlacement"];
    [prefs setBool:defaultAdjustWindowForFontSizeChange forKey:@"AdjustWindowForFontSizeChange"];
    [prefs setBool:defaultWindowNumber forKey:@"WindowNumber"];
    [prefs setBool:defaultJobName forKey:@"JobName"];
    [prefs setBool:defaultShowBookmarkName forKey:@"ShowBookmarkName"];
    [prefs setBool:defaultHotkey forKey:@"Hotkey"];
    [prefs setInteger:defaultHotkeyCode forKey:@"HotkeyCode"];
    [prefs setInteger:defaultHotkeyChar forKey:@"HotkeyChar"];
    [prefs setInteger:defaultHotkeyModifiers forKey:@"HotkeyModifiers"];
    [prefs setBool:defaultSavePasteHistory forKey:@"SavePasteHistory"];
    [prefs setBool:defaultOpenArrangementAtStartup forKey:@"OpenArrangementAtStartup"];
    [prefs setInteger:defaultIrMemory forKey:@"IRMemory"];
    [prefs setBool:defaultCheckTestRelease forKey:@"CheckTestRelease"];
    [prefs setBool:defaultDimInactiveSplitPanes forKey:@"DimInactiveSplitPanes"];
    [prefs setBool:defaultDimBackgroundWindows forKey:@"DimBackgroundWindows"];
    [prefs setBool:defaultAnimateDimming forKey:@"AnimateDimming"];
    [prefs setBool:defaultDimOnlyText forKey:@"DimOnlyText"];
    [prefs setFloat:defaultDimmingAmount forKey:@"SplitPaneDimmingAmount"];
    [prefs setBool:defaultShowWindowBorder forKey:@"UseBorder"];
    [prefs setBool:defaultLionStyleFullscreen forKey:@"UseLionStyleFullscreen"];
    [prefs setBool:defaultLoadPrefsFromCustomFolder forKey:@"LoadPrefsFromCustomFolder"];
    [prefs setObject:defaultPrefsCustomFolder forKey:@"PrefsCustomFolder"];

    [prefs setInteger:defaultControl forKey:@"Control"];
    [prefs setInteger:defaultLeftOption forKey:@"LeftOption"];
    [prefs setInteger:defaultRightOption forKey:@"RightOption"];
    [prefs setInteger:defaultLeftCommand forKey:@"LeftCommand"];
    [prefs setInteger:defaultRightCommand forKey:@"RightCommand"];
    [prefs setInteger:defaultSwitchTabModifier forKey:@"SwitchTabModifier"];
    [prefs setInteger:defaultSwitchWindowModifier forKey:@"SwitchWindowModifier"];

    // save the handlers by converting the bookmark into an index
    [prefs setObject:urlHandlersByGuid forKey:@"URLHandlersByGuid"];

    [prefs synchronize];
}

- (void)_populateHotKeyBookmarksMenu
{
    if (!hotkeyBookmark) {
        return;
    }
    [PreferencePanel populatePopUpButtonWithBookmarks:hotkeyBookmark
                                         selectedGuid:defaultHotKeyBookmarkGuid];
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
    [openTmuxWindows selectItemAtIndex: defaultOpenTmuxWindowsIn];
    [autoHideTmuxClientSession setState:defaultAutoHideTmuxClientSession?NSOnState:NSOffState];
    [tabPosition selectItemAtIndex: defaultTabViewType];
    [allowClipboardAccessFromTerminal setState:defaultAllowClipboardAccess?NSOnState:NSOffState];
    [selectionCopiesText setState:defaultCopySelection?NSOnState:NSOffState];
    [copyLastNewline setState:defaultCopyLastNewline ? NSOnState : NSOffState];
    [middleButtonPastesFromClipboard setState:defaultPasteFromClipboard?NSOnState:NSOffState];
    [threeFingerEmulatesMiddle setState:defaultThreeFingerEmulatesMiddle ? NSOnState : NSOffState];
    [hideTab setState:defaultHideTab?NSOnState:NSOffState];
    [promptOnQuit setState:defaultPromptOnQuit?NSOnState:NSOffState];
    [onlyWhenMoreTabs setState:defaultOnlyWhenMoreTabs?NSOnState:NSOffState];
    [focusFollowsMouse setState: defaultFocusFollowsMouse?NSOnState:NSOffState];
    [tripleClickSelectsFullLines setState:defaultTripleClickSelectsFullLines?NSOnState:NSOffState];
    [hotkeyTogglesWindow setState: defaultHotkeyTogglesWindow?NSOnState:NSOffState];
    [self _populateHotKeyBookmarksMenu];
    [enableBonjour setState: defaultEnableBonjour?NSOnState:NSOffState];
    [cmdSelection setState: defaultCmdSelection?NSOnState:NSOffState];
    [passOnControlLeftClick setState: defaultPassOnControlLeftClick?NSOnState:NSOffState];
    [maxVertically setState: defaultMaxVertically?NSOnState:NSOffState];
    [closingHotkeySwitchesSpaces setState:defaultClosingHotkeySwitchesSpaces?NSOnState:NSOffState];
    [useCompactLabel setState: defaultUseCompactLabel?NSOnState:NSOffState];
    [hideActivityIndicator setState:defaultHideActivityIndicator?NSOnState:NSOffState];
    [highlightTabLabels setState: defaultHighlightTabLabels?NSOnState:NSOffState];
    [advancedFontRendering setState: defaultAdvancedFontRendering?NSOnState:NSOffState];
    [strokeThickness setEnabled:defaultAdvancedFontRendering];
    [strokeThicknessLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
    [strokeThicknessMinLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
    [strokeThicknessMaxLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
    [strokeThickness setFloatValue:defaultStrokeThickness];
    [fsTabDelay setFloatValue:defaultFsTabDelay];

    [openBookmark setState: defaultOpenBookmark?NSOnState:NSOffState];
    [wordChars setStringValue: ([defaultWordChars length] > 0)?defaultWordChars:@""];
    [tmuxDashboardLimit setIntValue:defaultTmuxDashboardLimit];
    [quitWhenAllWindowsClosed setState: defaultQuitWhenAllWindowsClosed?NSOnState:NSOffState];
    [checkUpdate setState: defaultCheckUpdate?NSOnState:NSOffState];
    [hideScrollbar setState: defaultHideScrollbar?NSOnState:NSOffState];
    [showPaneTitles setState:defaultShowPaneTitles?NSOnState:NSOffState];
    [disableFullscreenTransparency setState:defaultDisableFullscreenTransparency ? NSOnState : NSOffState];
    [smartPlacement setState: defaultSmartPlacement?NSOnState:NSOffState];
    [adjustWindowForFontSizeChange setState: defaultAdjustWindowForFontSizeChange?NSOnState:NSOffState];
    [windowNumber setState: defaultWindowNumber?NSOnState:NSOffState];
    [jobName setState: defaultJobName?NSOnState:NSOffState];
    [showBookmarkName setState: defaultShowBookmarkName?NSOnState:NSOffState];
    [savePasteHistory setState: defaultSavePasteHistory?NSOnState:NSOffState];
    [openArrangementAtStartup setState:defaultOpenArrangementAtStartup ? NSOnState : NSOffState];
    [openArrangementAtStartup setEnabled:[WindowArrangements count] > 0];
    if ([WindowArrangements count] == 0) {
        [openArrangementAtStartup setState:NO];
    }
    [hotkey setState: defaultHotkey?NSOnState:NSOffState];
    if (defaultHotkeyCode) {
        [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", defaultHotkeyChar, defaultHotkeyModifiers]]];
    } else {
        [hotkeyField setStringValue:@""];
    }
    [hotkeyField setEnabled:defaultHotkey];
    [hotkeyLabel setTextColor:defaultHotkey ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
    [hotkeyTogglesWindow setEnabled:defaultHotkey];
    [hotkeyBookmark setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];

    [irMemory setIntValue:defaultIrMemory];
    [checkTestRelease setState:defaultCheckTestRelease?NSOnState:NSOffState];
    [dimInactiveSplitPanes setState:defaultDimInactiveSplitPanes?NSOnState:NSOffState];
    [animateDimming setState:defaultAnimateDimming?NSOnState:NSOffState];
    [dimBackgroundWindows setState:defaultDimBackgroundWindows?NSOnState:NSOffState];
    [dimOnlyText setState:defaultDimOnlyText?NSOnState:NSOffState];
    [dimmingAmount setFloatValue:defaultDimmingAmount];
    [showWindowBorder setState:defaultShowWindowBorder?NSOnState:NSOffState];
    [lionStyleFullscreen setState:defaultLionStyleFullscreen?NSOnState:NSOffState];
    [loadPrefsFromCustomFolder setState:defaultLoadPrefsFromCustomFolder?NSOnState:NSOffState];
    [prefsCustomFolder setStringValue:defaultPrefsCustomFolder ? defaultPrefsCustomFolder : @""];

    [self showWindow: self];
    [[self window] setLevel:NSNormalWindowLevel];
    NSString* guid = [bookmarksTableView selectedGuid];
    [bookmarksTableView reloadData];
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        Profile* dict = [dataSource bookmarkWithGuid:guid];
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

    [controlButton selectItemWithTag:defaultControl];
    [leftOptionButton selectItemWithTag:defaultLeftOption];
    [rightOptionButton selectItemWithTag:defaultRightOption];
    [leftCommandButton selectItemWithTag:defaultLeftCommand];
    [rightCommandButton selectItemWithTag:defaultRightCommand];

    [switchTabModifierButton selectItemWithTag:defaultSwitchTabModifier];
    [switchWindowModifierButton selectItemWithTag:defaultSwitchWindowModifier];

    int rowIndex = [globalKeyMappings selectedRow];
    if (rowIndex >= 0) {
        [globalRemoveMappingButton setEnabled:YES];
    } else {
        [globalRemoveMappingButton setEnabled:NO];
    }
    [globalKeyMappings reloadData];

    // Show the window.
    [[self window] makeKeyAndOrderFront:self];
}

- (float)fsTabDelay
{
    return defaultFsTabDelay;
}

- (BOOL)trimTrailingWhitespace
{
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:@"TrimWhitespaceOnCopy"];
    if (n) {
        return [n boolValue];
    } else {
        return YES;
    }
}

- (BOOL)advancedFontRendering
{
    return defaultAdvancedFontRendering;
}

- (float)strokeThickness
{
    return defaultStrokeThickness;
}

- (float)legacyMinimumContrast
{
    return [prefs objectForKey:@"MinimumContrast"] ? [[prefs objectForKey:@"MinimumContrast"] floatValue] : 0;;
}

- (int)modifierTagToMask:(int)tag
{
    switch (tag) {
        case MOD_TAG_ANY_COMMAND:
            return NSCommandKeyMask;

        case MOD_TAG_CMD_OPT:
            return NSCommandKeyMask | NSAlternateKeyMask;

        case MOD_TAG_OPTION:
            return NSAlternateKeyMask;

        default:
            NSLog(@"Unexpected value for modifierTagToMask: %d", tag);
            return NSCommandKeyMask | NSAlternateKeyMask;
    }
}

- (void)_generateHotkeyWindowProfile
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:[[ProfileModel sharedInstance] defaultBookmark]];
    [dict setObject:[NSNumber numberWithInt:WINDOW_TYPE_TOP] forKey:KEY_WINDOW_TYPE];
    [dict setObject:[NSNumber numberWithInt:25] forKey:KEY_ROWS];
    [dict setObject:[NSNumber numberWithFloat:0.3] forKey:KEY_TRANSPARENCY];
    [dict setObject:[NSNumber numberWithFloat:0.5] forKey:KEY_BLEND];
    [dict setObject:[NSNumber numberWithFloat:2.0] forKey:KEY_BLUR_RADIUS];
    [dict setObject:[NSNumber numberWithBool:YES] forKey:KEY_BLUR];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SCREEN];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SPACE];
    [dict setObject:@"" forKey:KEY_SHORTCUT];
    [dict setObject:HOTKEY_WINDOW_GENERATED_PROFILE_NAME forKey:KEY_NAME];
    [dict removeObjectForKey:KEY_TAGS];
    [dict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [[ProfileModel sharedInstance] addBookmark:dict];
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSOKButton) {
        [prefsCustomFolder setStringValue:[panel directory]];
        [self settingChanged:prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (IBAction)settingChanged:(id)sender
{
    if (sender == lionStyleFullscreen) {
        defaultLionStyleFullscreen = ([lionStyleFullscreen state] == NSOnState);
    } else if (sender == loadPrefsFromCustomFolder) {
        defaultLoadPrefsFromCustomFolder = [loadPrefsFromCustomFolder state] == NSOnState;
        if (defaultLoadPrefsFromCustomFolder) {
            // Just turned it on.
            if ([[prefsCustomFolder stringValue] length] == 0) {
                // Field was initially empty so browse for a dir.
                if ([self choosePrefsCustomFolder]) {
                    // User didn't hit cancel; if he chose a writable directory ask if he wants to write to it.
                    if ([self _prefsDirIsWritable]) {
                        if ([[NSAlert alertWithMessageText:@"Copy local preferences to custom folder now?"
                                         defaultButton:@"Copy"
                                       alternateButton:@"Don't Copy"
                                           otherButton:nil
                                 informativeTextWithFormat:@""] runModal] == NSOKButton) {
                            [self pushToCustomFolder:nil];
                        }
                    }
                }
            }
        }
        [prefsCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
        [browseCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
        [pushToCustomFolder setEnabled:defaultLoadPrefsFromCustomFolder];
        [self _updatePrefsDirWarning];
    } else if (sender == prefsCustomFolder) {
        // The OS will never call us directly with this sender, but we do call ourselves this way.
        [prefs setObject:[prefsCustomFolder stringValue]
                  forKey:@"PrefsCustomFolder"];
        defaultPrefsCustomFolder = [prefs objectForKey:@"PrefsCustomFolder"];
        customFolderChanged_ = YES;
        [self _updatePrefsDirWarning];
    } else if (sender == windowStyle ||
        sender == tabPosition ||
        sender == hideTab ||
        sender == useCompactLabel ||
        sender == hideActivityIndicator ||
        sender == highlightTabLabels ||
        sender == hideScrollbar ||
        sender == showPaneTitles ||
        sender == disableFullscreenTransparency ||
        sender == advancedFontRendering ||
        sender == strokeThickness ||
        sender == dimInactiveSplitPanes ||
        sender == dimBackgroundWindows ||
        sender == animateDimming ||
        sender == dimOnlyText ||
        sender == dimmingAmount ||
		sender == openTmuxWindows ||
        sender == threeFingerEmulatesMiddle ||
        sender == autoHideTmuxClientSession ||
        sender == showWindowBorder) {
        defaultWindowStyle = [windowStyle indexOfSelectedItem];
        defaultOpenTmuxWindowsIn = [[openTmuxWindows selectedItem] tag];
        defaultAutoHideTmuxClientSession = ([autoHideTmuxClientSession state] == NSOnState);
        defaultTabViewType=[tabPosition indexOfSelectedItem];
        defaultUseCompactLabel = ([useCompactLabel state] == NSOnState);
        defaultHideActivityIndicator = ([hideActivityIndicator state] == NSOnState);
        defaultHighlightTabLabels = ([highlightTabLabels state] == NSOnState);
        defaultShowPaneTitles = ([showPaneTitles state] == NSOnState);
        defaultAdvancedFontRendering = ([advancedFontRendering state] == NSOnState);
        [strokeThickness setEnabled:defaultAdvancedFontRendering];
        [strokeThicknessLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
        [strokeThicknessMinLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
        [strokeThicknessMaxLabel setTextColor:defaultAdvancedFontRendering ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
        defaultStrokeThickness = [strokeThickness floatValue];
        defaultHideTab = ([hideTab state] == NSOnState);
        defaultDimInactiveSplitPanes = ([dimInactiveSplitPanes state] == NSOnState);
        defaultDimBackgroundWindows = ([dimBackgroundWindows state] == NSOnState);
        defaultAnimateDimming= ([animateDimming state] == NSOnState);
        defaultDimOnlyText = ([dimOnlyText state] == NSOnState);
        defaultDimmingAmount = [dimmingAmount floatValue];
        defaultShowWindowBorder = ([showWindowBorder state] == NSOnState);
        defaultThreeFingerEmulatesMiddle=([threeFingerEmulatesMiddle state] == NSOnState);
        defaultHideScrollbar = ([hideScrollbar state] == NSOnState);
        defaultDisableFullscreenTransparency = ([disableFullscreenTransparency state] == NSOnState);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermRefreshTerminal"
                                                            object:nil
                                                          userInfo:nil];
        if (sender == threeFingerEmulatesMiddle) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                                object:nil
                                                              userInfo:nil];
        }
    } else if (sender == windowNumber ||
               sender == jobName ||
               sender == showBookmarkName) {
        defaultWindowNumber = ([windowNumber state] == NSOnState);
        defaultJobName = ([jobName state] == NSOnState);
        defaultShowBookmarkName = ([showBookmarkName state] == NSOnState);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermUpdateLabels"
                                                            object:nil
                                                          userInfo:nil];
    } else if (sender == switchTabModifierButton ||
               sender == switchWindowModifierButton) {
        defaultSwitchTabModifier = [switchTabModifierButton selectedTag];
        defaultSwitchWindowModifier = [switchWindowModifierButton selectedTag];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermModifierChanged"
                                                            object:nil
                                                          userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                    [NSNumber numberWithInt:[self modifierTagToMask:defaultSwitchTabModifier]], @"TabModifier",
                                                                    [NSNumber numberWithInt:[self modifierTagToMask:defaultSwitchWindowModifier]], @"WindowModifier",
                                                                    nil, nil]];
    } else {
        if (sender == hotkeyTogglesWindow &&
            [hotkeyTogglesWindow state] == NSOnState &&
            ![[ProfileModel sharedInstance] bookmarkWithName:HOTKEY_WINDOW_GENERATED_PROFILE_NAME]) {
            // User's turning on hotkey window. There is no bookmark with the autogenerated name.
            [self _generateHotkeyWindowProfile];
            [hotkeyBookmark selectItemWithTitle:HOTKEY_WINDOW_GENERATED_PROFILE_NAME];
            NSRunAlertPanel(@"Set Up Hotkey Window",
                            [NSString stringWithFormat:@"A new profile called \"%@\" was created for you. It is tuned to work well for the Hotkey Window feature, but you can change it in the Profiles tab.",
                             HOTKEY_WINDOW_GENERATED_PROFILE_NAME],
                            @"OK",
                            nil,
                            nil,
                            nil);
        }

        defaultFsTabDelay = [fsTabDelay floatValue];
        defaultAllowClipboardAccess = ([allowClipboardAccessFromTerminal state]==NSOnState);
        defaultCopySelection = ([selectionCopiesText state]==NSOnState);
        defaultCopyLastNewline = ([copyLastNewline state] == NSOnState);
        defaultPasteFromClipboard=([middleButtonPastesFromClipboard state]==NSOnState);
        defaultPromptOnQuit = ([promptOnQuit state] == NSOnState);
        defaultOnlyWhenMoreTabs = ([onlyWhenMoreTabs state] == NSOnState);
        defaultFocusFollowsMouse = ([focusFollowsMouse state] == NSOnState);
        defaultTripleClickSelectsFullLines = ([tripleClickSelectsFullLines state] == NSOnState);
        defaultHotkeyTogglesWindow = ([hotkeyTogglesWindow state] == NSOnState);
        [defaultHotKeyBookmarkGuid release];
        defaultHotKeyBookmarkGuid = [[[hotkeyBookmark selectedItem] representedObject] copy];
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
                ProfileModel* model = [ProfileModel sharedInstance];
                NSString* kBonjourTag = @"bonjour";
                int n = [model numberOfBookmarksWithFilter:kBonjourTag];
                for (int i = n - 1; i >= 0; --i) {
                    Profile* bookmark = [model profileAtIndex:i withFilter:kBonjourTag];
                    if ([model bookmark:bookmark hasTag:kBonjourTag]) {
                        [model removeBookmarkAtIndex:i withFilter:kBonjourTag];
                    }
                }
            }
        }

        defaultCmdSelection = ([cmdSelection state] == NSOnState);
        defaultPassOnControlLeftClick = ([passOnControlLeftClick state] == NSOnState);
        defaultMaxVertically = ([maxVertically state] == NSOnState);
        defaultClosingHotkeySwitchesSpaces = ([closingHotkeySwitchesSpaces state] == NSOnState);
        defaultOpenBookmark = ([openBookmark state] == NSOnState);
        [defaultWordChars release];
        defaultWordChars = [[wordChars stringValue] retain];
		defaultTmuxDashboardLimit = [[tmuxDashboardLimit stringValue] intValue];
        defaultQuitWhenAllWindowsClosed = ([quitWhenAllWindowsClosed state] == NSOnState);
        defaultCheckUpdate = ([checkUpdate state] == NSOnState);
        defaultSmartPlacement = ([smartPlacement state] == NSOnState);
        defaultAdjustWindowForFontSizeChange = ([adjustWindowForFontSizeChange state] == NSOnState);
        defaultSavePasteHistory = ([savePasteHistory state] == NSOnState);
        if (!defaultSavePasteHistory) {
            [[PasteboardHistory sharedInstance] eraseHistory];
        }
        defaultOpenArrangementAtStartup = ([openArrangementAtStartup state] == NSOnState);

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
        [hotkeyField setEnabled:defaultHotkey];
        [hotkeyLabel setTextColor:defaultHotkey ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
        [hotkeyTogglesWindow setEnabled:defaultHotkey];
        [hotkeyBookmark setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];

        if (prefs &&
            defaultCheckTestRelease != ([checkTestRelease state] == NSOnState)) {
            defaultCheckTestRelease = ([checkTestRelease state] == NSOnState);

            NSString *appCast = defaultCheckTestRelease ?
                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
            [prefs setObject: appCast forKey:@"SUFeedURL"];
        }
    }

    // Keyboard tab
    BOOL wasAnyModifierRemapped = [self isAnyModifierRemapped];
    defaultControl = [controlButton selectedTag];
    defaultLeftOption = [leftOptionButton selectedTag];
    defaultRightOption = [rightOptionButton selectedTag];
    defaultLeftCommand = [leftCommandButton selectedTag];
    defaultRightCommand = [rightCommandButton selectedTag];
    if ((!wasAnyModifierRemapped && [self isAnyModifierRemapped]) ||
        ([self isAnyModifierRemapped] && ![[iTermController sharedInstance] haveEventTap])) {
        [[iTermController sharedInstance] beginRemappingModifiers];
    }

    int rowIndex = [globalKeyMappings selectedRow];
    if (rowIndex >= 0) {
        [globalRemoveMappingButton setEnabled:YES];
    } else {
        [globalRemoveMappingButton setEnabled:NO];
    }
    [globalKeyMappings reloadData];
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


- (BOOL)allowClipboardAccess
{
    return defaultAllowClipboardAccess;
}

- (void) setAllowClipboardAccess:(BOOL)flag
{
    defaultAllowClipboardAccess = flag;
}

- (BOOL)copySelection
{
    return defaultCopySelection;
}

- (BOOL)copyLastNewline
{
    return defaultCopyLastNewline;
}

- (void) setCopySelection:(BOOL)flag
{
    defaultCopySelection = flag;
}

- (BOOL)legacyPasteFromClipboard
{
    return defaultPasteFromClipboard;
}

- (BOOL)pasteFromClipboard
{
    return defaultPasteFromClipboard;
}

- (BOOL)legacyThreeFingerEmulatesMiddle
{
    return defaultThreeFingerEmulatesMiddle;
}

- (BOOL)threeFingerEmulatesMiddle
{
    return defaultThreeFingerEmulatesMiddle;
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

- (int)openTmuxWindowsIn
{
	return defaultOpenTmuxWindowsIn;
}

- (BOOL)autoHideTmuxClientSession
{
    return defaultAutoHideTmuxClientSession;
}

- (int)tmuxDashboardLimit
{
	return defaultTmuxDashboardLimit;
}

- (BOOL)promptOnQuit
{
    return defaultPromptOnQuit;
}

- (BOOL)onlyWhenMoreTabs
{
    return defaultOnlyWhenMoreTabs;
}

- (BOOL)focusFollowsMouse
{
    return defaultFocusFollowsMouse;
}

- (BOOL)tripleClickSelectsFullLines
{
    return defaultTripleClickSelectsFullLines;
}

- (BOOL)enableBonjour
{
    return defaultEnableBonjour;
}

- (BOOL)enableGrowl
{
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    for (Profile* bookmark in [[ProfileModel sessionsInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)cmdSelection
{
    return defaultCmdSelection;
}

- (BOOL)passOnControlLeftClick
{
    return defaultPassOnControlLeftClick;
}

- (BOOL)maxVertically
{
    return defaultMaxVertically;
}

- (BOOL)closingHotkeySwitchesSpaces
{
    return defaultClosingHotkeySwitchesSpaces;
}

- (BOOL)useCompactLabel
{
    return defaultUseCompactLabel;
}

- (BOOL)hideActivityIndicator
{
    return defaultHideActivityIndicator;
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

- (ITermCursorType)legacyCursorType
{
    return [prefs objectForKey:@"CursorType"] ? [prefs integerForKey:@"CursorType"] : CURSOR_BOX;
}

- (BOOL)hideScrollbar
{
    return defaultHideScrollbar;
}

- (BOOL)showPaneTitles
{
    return defaultShowPaneTitles;
}

- (BOOL)disableFullscreenTransparency
{
    return defaultDisableFullscreenTransparency;
}

- (BOOL)smartPlacement
{
    return defaultSmartPlacement;
}

- (BOOL)adjustWindowForFontSizeChange
{
    return defaultAdjustWindowForFontSizeChange;
}

- (BOOL)windowNumber
{
    return defaultWindowNumber;
}

- (BOOL)jobName
{
    return defaultJobName;
}

- (BOOL)showBookmarkName
{
    return defaultShowBookmarkName;
}

- (BOOL)instantReplay
{
    return YES;
}

- (BOOL)savePasteHistory
{
    return defaultSavePasteHistory;
}

- (int)control
{
    return defaultControl;
}

- (int)leftOption
{
    return defaultLeftOption;
}

- (int)rightOption
{
    return defaultRightOption;
}

- (int)leftCommand
{
    return defaultLeftCommand;
}

- (int)rightCommand
{
    return defaultRightCommand;
}

- (BOOL)isAnyModifierRemapped
{
    return ([self control] != MOD_TAG_CONTROL ||
            [self leftOption] != MOD_TAG_LEFT_OPTION ||
            [self rightOption] != MOD_TAG_RIGHT_OPTION ||
            [self leftCommand] != MOD_TAG_LEFT_COMMAND ||
            [self rightCommand] != MOD_TAG_RIGHT_COMMAND);
}

- (int)switchTabModifier
{
    return defaultSwitchTabModifier;
}

- (int)switchWindowModifier
{
    return defaultSwitchWindowModifier;
}

- (BOOL)openArrangementAtStartup
{
    return defaultOpenArrangementAtStartup;
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

- (BOOL)dimInactiveSplitPanes
{
    return defaultDimInactiveSplitPanes;
}

- (BOOL)dimBackgroundWindows
{
    return defaultDimBackgroundWindows;
}

- (BOOL)animateDimming
{
    return defaultAnimateDimming;
}

- (BOOL)dimOnlyText
{
    return defaultDimOnlyText;
}

- (float)dimmingAmount
{
    return defaultDimmingAmount;
}

- (BOOL)showWindowBorder
{
    return defaultShowWindowBorder;
}

- (BOOL)lionStyleFullscreen
{
    if (IsLionOrLater()) {
        return defaultLionStyleFullscreen;
    } else {
        return NO;
    }
}

- (NSString *)_prefsFilename
{
    NSString *prefDir = [[NSHomeDirectory()
                          stringByAppendingPathComponent:@"Library"]
                          stringByAppendingPathComponent:@"Preferences"];
    return [prefDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",
                                                    [[NSBundle mainBundle] bundleIdentifier]]];
}

- (NSString *)_prefsFilenameWithBaseDir:(NSString *)base
{
    return [NSString stringWithFormat:@"%@/%@.plist", base, [[NSBundle mainBundle] bundleIdentifier]];
}

- (NSString *)remotePrefsLocation
{
    NSString *folder = [prefs objectForKey:@"PrefsCustomFolder"] ? [prefs objectForKey:@"PrefsCustomFolder"] : @"";
    NSString *filename = [self _prefsFilenameWithBaseDir:folder];
    if ([self _stringIsUrlLike:folder]) {
        filename = folder;
    } else {
		filename = [filename stringByExpandingTildeInPath];
	}
    return filename;
}

- (NSDictionary *)_remotePrefs
{
    BOOL doLoad = [prefs objectForKey:@"LoadPrefsFromCustomFolder"] ? [[prefs objectForKey:@"LoadPrefsFromCustomFolder"] boolValue] : NO;
    if (!doLoad) {
        return nil;
    }
    NSString *filename = [self remotePrefsLocation];
    NSDictionary *remotePrefs;
    if ([self _stringIsUrlLike:filename]) {
        // Download the URL's contents.
        NSURL *url = [NSURL URLWithString:filename];
        const NSTimeInterval kFetchTimeout = 5.0;
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval:kFetchTimeout];
        NSURLResponse *response = nil;
        NSError *error = nil;

        NSData *data = [NSURLConnection sendSynchronousRequest:req
                                             returningResponse:&response
                                                         error:&error];
        if (!data || error) {
            [[NSAlert alertWithMessageText:@"Failed to load preferences from URL. Falling back to local copy."
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"HTTP request failed: %@", [error description] ? [error description] : @"unknown error"] runModal];
            return NO;
        }

        // Write it to disk
        NSFileManager *mgr = [NSFileManager defaultManager];
        NSString *tempDir = [mgr temporaryDirectory];
        NSString *tempFile = [tempDir stringByAppendingPathComponent:@"temp.plist"];
        error = nil;
        if (![data writeToFile:tempFile options:0 error:&error]) {
            [[NSAlert alertWithMessageText:@"Failed to write to temp file while getting remote prefs. Falling back to local copy."
                             defaultButton:@"OK"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Error on file %@: %@", tempFile, [error localizedFailureReason]] runModal];
            return NO;
        }

        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:tempFile];

        [mgr removeItemAtPath:tempFile error:nil];
        [mgr removeItemAtPath:tempDir error:nil];
    } else {
        remotePrefs = [NSDictionary dictionaryWithContentsOfFile:filename];
    }
    return remotePrefs;
}

+ (BOOL)loadingPrefsFromCustomFolder
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"LoadPrefsFromCustomFolder"] ? [[[NSUserDefaults standardUserDefaults] objectForKey:@"LoadPrefsFromCustomFolder"] boolValue] : NO;
}

- (BOOL)preferenceKeyIsSyncable:(NSString *)key
{
    NSArray *exemptKeys = [NSArray arrayWithObjects:@"LoadPrefsFromCustomFolder",
                           @"PrefsCustomFolder",
                           @"iTerm Version",
                           nil];
    return ![exemptKeys containsObject:key] &&
           ![key hasPrefix:@"NS"] &&
           ![key hasPrefix:@"SU"] &&
           ![key hasPrefix:@"NoSync"] &&
           ![key hasPrefix:@"UK"];
}

- (BOOL)loadPrefs
{
    static BOOL done;
    if (done) {
        return YES;
    }
    done = YES;

    BOOL doLoad = [PreferencePanel loadingPrefsFromCustomFolder];
    if (!doLoad) {
        return YES;
    }
    NSDictionary *remotePrefs = [self _remotePrefs];

    if (remotePrefs && [remotePrefs count]) {
        NSDictionary *localPrefs = [NSDictionary dictionaryWithContentsOfFile:[self _prefsFilename]];
        // Empty out the current prefs
        for (NSString *key in localPrefs) {
            if ([self preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            }
        }

        for (NSString *key in remotePrefs) {
            if ([self preferenceKeyIsSyncable:key]) {
                [[NSUserDefaults standardUserDefaults] setObject:[remotePrefs objectForKey:key]
                                                          forKey:key];
            }
        }
        return YES;
    } else {
        [[NSAlert alertWithMessageText:@"Failed to load preferences from custom directory. Falling back to local copy."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"Missing or malformed file at \"%@\"", [self remotePrefsLocation]] runModal];
    }
    return NO;
}

- (BOOL)prefsDifferFromRemote
{
    BOOL doLoad = [prefs objectForKey:@"LoadPrefsFromCustomFolder"] ? [[prefs objectForKey:@"LoadPrefsFromCustomFolder"] boolValue] : NO;
    if (!doLoad) {
        return NO;
    }
    NSDictionary *remotePrefs = [self _remotePrefs];
    if (remotePrefs && [remotePrefs count]) {
        // Grab all prefs from our bundle only (no globals, etc.).
        NSDictionary *localPrefs = [prefs persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        // Iterate over each set of prefs and validate that the other has the same value for each key.
        for (NSString *key in localPrefs) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[remotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                NSLog(@"Prefs differ for key %@. local=\"%@\", remote=\"%@\" [case 1]",
                      key,
                      [localPrefs objectForKey:key],
                      [remotePrefs objectForKey:key]);
                return YES;
            }
        }

        for (NSString *key in remotePrefs) {
            if ([self preferenceKeyIsSyncable:key] &&
                ![[remotePrefs objectForKey:key] isEqual:[localPrefs objectForKey:key]]) {
                NSLog(@"Prefs differ for key %@. local=\"%@\", remote=\"%@\" [case 2]",
                      key,
                      [localPrefs objectForKey:key],
                      [remotePrefs objectForKey:key]);
                return YES;
            }
        }
        return NO;
    } else {
        // Can't load remote prefs, so no problem.
        return NO;
    }
}

- (NSString *)loadPrefsFromCustomFolder
{
    if (defaultLoadPrefsFromCustomFolder) {
        return defaultPrefsCustomFolder;
    } else {
        return nil;
    }
}

- (BOOL)checkTestRelease
{
    return defaultCheckTestRelease;
}

// Smart cursor color used to be a global value. This provides the default when
// migrating.
- (BOOL)legacySmartCursorColor
{
    return [prefs objectForKey:@"ColorInvertedCursor"]?[[prefs objectForKey:@"ColorInvertedCursor"] boolValue]: YES;
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

- (float) hotkeyTermAnimationDuration
{
    assert(prefs);
    return [prefs objectForKey:@"HotkeyTermAnimationDuration"] ? [[prefs objectForKey:@"HotkeyTermAnimationDuration"] floatValue] : 0.25;
}

- (NSString *) searchCommand
{
    assert(prefs);
    return [prefs objectForKey:@"SearchCommand"] ? [prefs objectForKey:@"SearchCommand"] : @"http://google.com/search?q=%@";
}

// URL handler stuff
- (Profile *)handlerBookmarkForURL:(NSString *)url
{
    NSString* handlerId = (NSString*) LSCopyDefaultHandlerForURLScheme((CFStringRef) url);
    if ([handlerId isEqualToString:@"com.googlecode.iterm2"] ||
        [handlerId isEqualToString:@"net.sourceforge.iterm"]) {
        CFRelease(handlerId);
        NSString* guid = [urlHandlersByGuid objectForKey:url];
        if (!guid) {
            return nil;
        }
        int theIndex = [dataSource indexOfProfileWithGuid:guid];
        if (theIndex < 0) {
            return nil;
        }
        return [dataSource profileAtIndex:theIndex];
    } else {
        if (handlerId) {
            CFRelease(handlerId);
        }
        return nil;
    }
}

// NSTableView data source
- (int)numberOfRowsInTableView: (NSTableView *)aTableView
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        if (!guid) {
            return 0;
        }
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Null node");
        return [iTermKeyBindingMgr numberOfMappingsForBookmark:bookmark];
    } else if (aTableView == globalKeyMappings) {
        return [[iTermKeyBindingMgr globalKeyMap] count];
    } else if (aTableView == jobsTable_) {
        NSString* guid = [bookmarksTableView selectedGuid];
        if (!guid) {
            return 0;
        }
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
        return [jobNames count];
    }
    // We can only get here while loading the nib (on some machines, this function is called
    // before the IBOutlets are populated).
    return 0;
}


- (NSString*)keyComboAtIndex:(int)rowIndex originator:(id)originator
{
    if ([self _originatorIsBookmark:originator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");
        return [iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark];
    } else {
        return [iTermKeyBindingMgr globalShortcutAtIndex:rowIndex];
    }
}

- (NSDictionary*)keyInfoAtIndex:(int)rowIndex originator:(id)originator
{
    if ([self _originatorIsBookmark:originator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");
        return [iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark];
    } else {
        return [iTermKeyBindingMgr globalMappingAtIndex:rowIndex];
    }
}

- (NSString*)formattedKeyCombinationForRow:(int)rowIndex originator:(id)originator
{
    return [iTermKeyBindingMgr formatKeyCombination:[self keyComboAtIndex:rowIndex
                                                               originator:originator]];
}

- (NSString*)formattedActionForRow:(int)rowIndex originator:(id)originator
{
    return [iTermKeyBindingMgr formatAction:[self keyInfoAtIndex:rowIndex originator:originator]];
}

- (void)keyBindingsChanged
{
    [keyMappings reloadData];
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    if (aTableView == jobsTable_) {
        NSString* guid = [bookmarksTableView selectedGuid];
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSMutableArray *jobs = [NSMutableArray arrayWithArray:[bookmark objectForKey:KEY_JOBS]];
        [jobs replaceObjectAtIndex:rowIndex withObject:anObject];
        [dataSource setObject:jobs forKey:KEY_JOBS inBookmark:bookmark];
    }
    [self bookmarkSettingChanged:nil];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");

        if (aTableColumn == keyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:[iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark]];
        } else if (aTableColumn == actionColumn) {
            return [iTermKeyBindingMgr formatAction:[iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark]];
        }
    } else if (aTableView == globalKeyMappings) {
        if (aTableColumn == globalKeyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:[iTermKeyBindingMgr globalShortcutAtIndex:rowIndex]];
        } else if (aTableColumn == globalActionColumn) {
            return [iTermKeyBindingMgr formatAction:[iTermKeyBindingMgr globalMappingAtIndex:rowIndex]];
        }
    } else if (aTableView == jobsTable_) {
        NSString* guid = [bookmarksTableView selectedGuid];
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        return [[bookmark objectForKey:KEY_JOBS] objectAtIndex:rowIndex];
    }
    // Shouldn't get here but must return something to avoid a warning.
    return nil;
}

- (void)_updateFontsDisplay
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
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
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
    // NSLog(@"Unexpected shortcut key: '%@'", key);
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
        Profile* temp = [dataSource profileAtIndex:i];
        NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            //NSLog(@"Bookmark %@ has shortcut %@", [temp objectForKey:KEY_NAME], existingShortcut);
            const int theIndex = [bookmarkShortcutKey indexOfItemWithTag:tag];
            NSMenuItem* item = [bookmarkShortcutKey itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"%@ (%@)", existingShortcut, [temp objectForKey:KEY_NAME]];
            [item setTitle:newTitle];
        }
    }
}

- (void)_populateBookmarkUrlSchemesFromDict:(Profile*)dict
{
    if ([[[bookmarkUrlSchemes menu] itemArray] count] == 0) {
        NSArray* urlArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        for (int i=0; i<[urlArray count]; i++) {
            [bookmarkUrlSchemes addItemWithTitle:[[[urlArray objectAtIndex:i] objectForKey: @"CFBundleURLSchemes"] objectAtIndex:0]];
        }
        [bookmarkUrlSchemes setTitle:@"Select URL Schemes…"];
    }

    NSString* guid = [dict objectForKey:KEY_GUID];
    [[bookmarkUrlSchemes menu] setAutoenablesItems:YES];
    [[bookmarkUrlSchemes menu] setDelegate:self];
    for (NSMenuItem* item in [[bookmarkUrlSchemes menu] itemArray]) {
        Profile* handler = [self handlerBookmarkForURL:[item title]];
        if (handler && [[handler objectForKey:KEY_GUID] isEqualToString:guid]) {
            [item setState:NSOnState];
        } else {
            [item setState:NSOffState];
        }
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)updateBookmarkFields:(NSDictionary *)dict
{
    if ([dataSource numberOfBookmarks] < 2 || !dict) {
        [removeBookmarkButton setEnabled:NO];
    } else {
        [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [dataSource numberOfBookmarks]];
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
    NSString* text;
    NSString* dir;
    NSString* customCommand;
    NSString* customDir;
    name = [dict objectForKey:KEY_NAME];
    shortcut = [dict objectForKey:KEY_SHORTCUT];
    command = [dict objectForKey:KEY_COMMAND];
    text = [dict objectForKey:KEY_INITIAL_TEXT];
    if (!text) {
        text = @"";
    }
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
    [initialText setStringValue:text];

    BOOL enabledAdvancedEdit = NO;
    if ([customDir isEqualToString:@"Yes"]) {
        [bookmarkDirectoryType selectCellWithTag:0];
    } else if ([customDir isEqualToString:@"Recycle"]) {
        [bookmarkDirectoryType selectCellWithTag:2];
    } else if ([customDir isEqualToString:@"Advanced"]) {
        [bookmarkDirectoryType selectCellWithTag:3];
        enabledAdvancedEdit = YES;
    } else {
        [bookmarkDirectoryType selectCellWithTag:1];
    }
    [editAdvancedConfigButton setEnabled:enabledAdvancedEdit];

    [bookmarkDirectory setStringValue:dir];
    [self _populateBookmarkUrlSchemesFromDict:dict];

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

    BOOL smartCursorColor;
    if ([dict objectForKey:KEY_SMART_CURSOR_COLOR]) {
        smartCursorColor = [[dict objectForKey:KEY_SMART_CURSOR_COLOR] boolValue];
    } else {
        smartCursorColor = [self legacySmartCursorColor];
    }
    [checkColorInvertedCursor setState:smartCursorColor ? NSOnState : NSOffState];

    [cursorColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    [cursorTextColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorTextColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    float minContrast;
    if ([dict objectForKey:KEY_MINIMUM_CONTRAST]) {
        minContrast = [[dict objectForKey:KEY_MINIMUM_CONTRAST] floatValue];
    } else {
        minContrast = [self legacyMinimumContrast];
    }
    [minimumContrast setFloatValue:minContrast];

    // Display tab
    int cols = [[dict objectForKey:KEY_COLUMNS] intValue];
    [columnsField setStringValue:[NSString stringWithFormat:@"%d", cols]];
    int rows = [[dict objectForKey:KEY_ROWS] intValue];
    [rowsField setStringValue:[NSString stringWithFormat:@"%d", rows]];
    [windowTypeButton selectItemWithTag:[dict objectForKey:KEY_WINDOW_TYPE] ? [[dict objectForKey:KEY_WINDOW_TYPE] intValue] : WINDOW_TYPE_NORMAL];
    [self setScreens];
    if (![screenButton selectItemWithTag:[dict objectForKey:KEY_SCREEN] ? [[dict objectForKey:KEY_SCREEN] intValue] : -1]) {
        [screenButton selectItemWithTag:-1];
    }
    if ([dict objectForKey:KEY_SPACE]) {
        [spaceButton selectItemWithTag:[[dict objectForKey:KEY_SPACE] intValue]];
    } else {
        [spaceButton selectItemWithTag:0];
    }
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
    [blinkAllowed setState:[[dict objectForKey:KEY_BLINK_ALLOWED] boolValue] ? NSOnState : NSOffState];
    [cursorType selectCellWithTag:[dict objectForKey:KEY_CURSOR_TYPE] ? [[dict objectForKey:KEY_CURSOR_TYPE] intValue] : [self legacyCursorType]];

    NSNumber* useBoldFontEntry = [dict objectForKey:KEY_USE_BOLD_FONT];
    NSNumber* disableBoldEntry = [dict objectForKey:KEY_DISABLE_BOLD];
    if (useBoldFontEntry) {
        [useBoldFont setState:[useBoldFontEntry boolValue] ? NSOnState : NSOffState];
    } else if (disableBoldEntry) {
        // Only deprecated option is set.
        [useBoldFont setState:[disableBoldEntry boolValue] ? NSOffState : NSOnState];
    } else {
        [useBoldFont setState:NSOnState];
    }

    if ([dict objectForKey:KEY_USE_BRIGHT_BOLD] != nil) {
        [useBrightBold setState:[[dict objectForKey:KEY_USE_BRIGHT_BOLD] boolValue] ? NSOnState : NSOffState];
    } else {
        [useBrightBold setState:NSOnState];
    }

    [useItalicFont setState:[[dict objectForKey:KEY_USE_ITALIC_FONT] boolValue] ? NSOnState : NSOffState];

    [transparency setFloatValue:[[dict objectForKey:KEY_TRANSPARENCY] floatValue]];
	if ([dict objectForKey:KEY_BLEND]) {
	  [blend setFloatValue:[[dict objectForKey:KEY_BLEND] floatValue]];
	} else {
		// Old clients used transparency for blending
		[blend setFloatValue:[[dict objectForKey:KEY_TRANSPARENCY] floatValue]];
	}
    [blurRadius setFloatValue:[dict objectForKey:KEY_BLUR_RADIUS] ? [[dict objectForKey:KEY_BLUR_RADIUS] floatValue] : 2.0];
    [blur setState:[[dict objectForKey:KEY_BLUR] boolValue] ? NSOnState : NSOffState];
    if ([dict objectForKey:KEY_ASCII_ANTI_ALIASED]) {
        [asciiAntiAliased setState:[[dict objectForKey:KEY_ASCII_ANTI_ALIASED] boolValue] ? NSOnState : NSOffState];
    } else {
        [asciiAntiAliased setState:[[dict objectForKey:KEY_ANTI_ALIASING] boolValue] ? NSOnState : NSOffState];
    }
    if ([dict objectForKey:KEY_NONASCII_ANTI_ALIASED]) {
        [nonasciiAntiAliased setState:[[dict objectForKey:KEY_NONASCII_ANTI_ALIASED] boolValue] ? NSOnState : NSOffState];
    } else {
        [nonasciiAntiAliased setState:[[dict objectForKey:KEY_ANTI_ALIASING] boolValue] ? NSOnState : NSOffState];
    }
    NSString* imageFilename = [dict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    if (!imageFilename) {
        imageFilename = @"";
    }
    [backgroundImage setState:[imageFilename length] > 0 ? NSOnState : NSOffState];
    [backgroundImagePreview setImage:[[[NSImage alloc] initByReferencingFile:imageFilename] autorelease]];
    backgroundImageFilename = imageFilename;
    [backgroundImageTiled setState:[[dict objectForKey:KEY_BACKGROUND_IMAGE_TILED] boolValue] ? NSOnState : NSOffState];

    // Terminal tab
    [disableWindowResizing setState:[[dict objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] ? NSOnState : NSOffState];
	[hideAfterOpening setState:[[dict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue] ? NSOnState : NSOffState];
    [syncTitle setState:[[dict objectForKey:KEY_SYNC_TITLE] boolValue] ? NSOnState : NSOffState];
    [closeSessionsOnEnd setState:[[dict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue] ? NSOnState : NSOffState];
    [nonAsciiDoubleWidth setState:[[dict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue] ? NSOnState : NSOffState];
    [silenceBell setState:[[dict objectForKey:KEY_SILENCE_BELL] boolValue] ? NSOnState : NSOffState];
    [visualBell setState:[[dict objectForKey:KEY_VISUAL_BELL] boolValue] ? NSOnState : NSOffState];
    [flashingBell setState:[[dict objectForKey:KEY_FLASHING_BELL] boolValue] ? NSOnState : NSOffState];
    [xtermMouseReporting setState:[[dict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue] ? NSOnState : NSOffState];
    [disableSmcupRmcup setState:[[dict objectForKey:KEY_DISABLE_SMCUP_RMCUP] boolValue] ? NSOnState : NSOffState];
    [allowTitleReporting setState:[[dict objectForKey:KEY_ALLOW_TITLE_REPORTING] boolValue] ? NSOnState : NSOffState];
    [disablePrinting setState:[[dict objectForKey:KEY_DISABLE_PRINTING] boolValue] ? NSOnState : NSOffState];
    [scrollbackWithStatusBar setState:[[dict objectForKey:KEY_SCROLLBACK_WITH_STATUS_BAR] boolValue] ? NSOnState : NSOffState];
    [scrollbackInAlternateScreen setState:[dict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] ? 
         ([[dict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] boolValue] ? NSOnState : NSOffState) : NSOnState];
    [bookmarkGrowlNotifications setState:[[dict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue] ? NSOnState : NSOffState];
    [setLocaleVars setState:[dict objectForKey:KEY_SET_LOCALE_VARS] ? ([[dict objectForKey:KEY_SET_LOCALE_VARS] boolValue] ? NSOnState : NSOffState) : NSOnState];
    [autoLog setState:[[dict objectForKey:KEY_AUTOLOG] boolValue] ? NSOnState : NSOffState];
    [logDir setStringValue:[dict objectForKey:KEY_LOGDIR] ? [dict objectForKey:KEY_LOGDIR] : @""];
    [logDir setEnabled:[autoLog state] == NSOnState];
    [changeLogDir setEnabled:[autoLog state] == NSOnState];
    [self _updateLogDirWarning];
    [characterEncoding setTitle:[NSString localizedNameOfStringEncoding:[[dict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]]];
    [scrollbackLines setIntValue:[[dict objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    [unlimitedScrollback setState:[[dict objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue] ? NSOnState : NSOffState];
    [scrollbackLines setEnabled:[unlimitedScrollback state] == NSOffState];
    if ([unlimitedScrollback state] == NSOnState) {
        [scrollbackLines setStringValue:@""];
    }
    [terminalType setStringValue:[dict objectForKey:KEY_TERMINAL_TYPE]];
    [sendCodeWhenIdle setState:[[dict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue] ? NSOnState : NSOffState];
    [idleCode setIntValue:[[dict objectForKey:KEY_IDLE_CODE] intValue]];
    [useCanonicalParser setState:[[dict objectForKey:KEY_USE_CANONICAL_PARSER] boolValue] ? NSOnState : NSOffState];

    // Keyboard tab
    int rowIndex = [keyMappings selectedRow];
    if (rowIndex >= 0) {
        [removeMappingButton setEnabled:YES];
    } else {
        [removeMappingButton setEnabled:NO];
    }
    [keyMappings reloadData];
    [optionKeySends selectCellWithTag:[[dict objectForKey:KEY_OPTION_KEY_SENDS] intValue]];
    id rightOptPref = [dict objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
    if (!rightOptPref) {
        rightOptPref = [dict objectForKey:KEY_OPTION_KEY_SENDS];
    }
    [rightOptionKeySends selectCellWithTag:[rightOptPref intValue]];
    [tags setObjectValue:[dict objectForKey:KEY_TAGS]];
    // If a keymapping for the delete key was added, make sure the
    // "delete sends ^h" checkbox is correct
    BOOL sendCH = [self _deleteSendsCtrlHInBookmark:dict];
    [deleteSendsCtrlHButton setState:sendCH ? NSOnState : NSOffState];

    // Session tab
    [promptBeforeClosing_ selectCellWithTag:[[dict objectForKey:KEY_PROMPT_CLOSE] intValue]];

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

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
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

- (void)_maybeWarnAboutMeta
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NeverWarnAboutMeta"]) {
        return;
    }

    switch (NSRunAlertPanel(@"Warning",
                            @"You have chosen to have an option key act as Meta. This option is useful for backward compatibility with older systems. The \"+Esc\" option is recommended for most users.",
                            @"OK",
                            @"Never warn me again",
                            nil,
                            nil)) {
        case NSAlertDefaultReturn:
            break;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:@"NeverWarnAboutMeta"];
            break;
    }
}

- (void)_maybeWarnAboutSpaces
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"NeverWarnAboutSpaces"]) {
        return;
    }

    switch (NSRunAlertPanel(@"Notice",
                            @"To have a new window open in a specific space, make sure that Spaces is enabled in System Preferences and that it is configured to switch directly to a space with ^ Number Keys.",
                            @"OK",
                            @"Never warn me again",
                            nil,
                            nil)) {
        case NSAlertDefaultReturn:
            break;
        case NSAlertAlternateReturn:
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:@"NeverWarnAboutSpaces"];
            break;
    }
}

- (IBAction)copyToProfile:(id)sender
{
    NSString* sourceGuid = [bookmarksTableView selectedGuid];
    if (!sourceGuid) {
        return;
    }
    Profile* sourceBookmark = [dataSource bookmarkWithGuid:sourceGuid];
    NSString* profileGuid = [sourceBookmark objectForKey:KEY_ORIGINAL_GUID];
    Profile* destination = [[ProfileModel sharedInstance] bookmarkWithGuid:profileGuid];
    // TODO: changing color presets in cmd-i causes profileGuid=null.
    if (sourceBookmark && destination) {
        NSMutableDictionary* copyOfSource = [[sourceBookmark mutableCopy] autorelease];
        [copyOfSource setObject:profileGuid forKey:KEY_GUID];
        [copyOfSource removeObjectForKey:KEY_ORIGINAL_GUID];
        [copyOfSource setObject:[destination objectForKey:KEY_NAME] forKey:KEY_NAME];
        [[ProfileModel sharedInstance] setBookmark:copyOfSource withGuid:profileGuid];

        [[PreferencePanel sharedInstance] profileTableSelectionDidChange:[PreferencePanel sharedInstance]->bookmarksTableView];

        // Update existing sessions
        int n = [[iTermController sharedInstance] numberOfTerminals];
        for (int i = 0; i < n; ++i) {
            PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
            [pty reloadBookmarks];
        }

        // Update user defaults
        [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                                  forKey: @"New Bookmarks"];
    }
}

- (IBAction)browseCustomFolder:(id)sender
{
    [self choosePrefsCustomFolder];
}

- (BOOL)customFolderChanged
{
    return customFolderChanged_;
}

- (IBAction)pushToCustomFolder:(id)sender
{
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *folder = [prefs objectForKey:@"PrefsCustomFolder"] ? [[prefs objectForKey:@"PrefsCustomFolder"] stringByExpandingTildeInPath] : @"";
    NSString *filename = [self _prefsFilenameWithBaseDir:folder];
    NSFileManager *mgr = [NSFileManager defaultManager];

    // Copy fails if the destination exists.
    [mgr removeItemAtPath:filename error:nil];

    [self savePreferences];
    NSDictionary *myDict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
    BOOL isOk;
    if ([self _stringIsUrlLike:filename]) {
        [[NSAlert alertWithMessageText:@"Sorry, preferences cannot be copied to a URL by iTerm2."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"To make it available, first quit iTerm2 and then manually copy ~/Library/Preferences/com.googlecode.iterm2.plist to your hosting provider."] runModal];
        return;
    }
    isOk = [myDict writeToFile:filename atomically:YES];
    if (!isOk) {
        [[NSAlert alertWithMessageText:@"Failed to copy preferences to custom directory."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"Copy %@ to %@: %s", [self _prefsFilename], filename, strerror(errno)] runModal];
    }
}

- (IBAction)bookmarkSettingChanged:(id)sender
{
    NSString* name = [bookmarkName stringValue];
    NSString* shortcut = [self shortcutKeyForTag:[[bookmarkShortcutKey selectedItem] tag]];
    NSString* command = [bookmarkCommand stringValue];
    NSString *text = [initialText stringValue];
    if (!text) {
        text = @"";
    }
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

        case 3:
            customDir = @"Advanced";
            break;

        case 1:
        default:
            customDir = @"No";
            break;
    }
    [editAdvancedConfigButton setEnabled:[customDir isEqualToString:@"Advanced"]];

    if (sender == optionKeySends && [[optionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    } else if (sender == rightOptionKeySends && [[rightOptionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    }
    if (sender == spaceButton && [spaceButton selectedTag] > 0) {
        [self _maybeWarnAboutSpaces];
    }
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* origBookmark = [dataSource bookmarkWithGuid:guid];
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
    NSString* origGuid = [origBookmark objectForKey:KEY_ORIGINAL_GUID];
    if (origGuid) {
        [newDict setObject:origGuid forKey:KEY_ORIGINAL_GUID];
    }
    if (shortcut) {
        // If any bookmark has this shortcut, clear its shortcut.
        for (int i = 0; i < [dataSource numberOfBookmarks]; ++i) {
            Profile* temp = [dataSource profileAtIndex:i];
            NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
            if ([shortcut length] > 0 && 
                [existingShortcut isEqualToString:shortcut] &&
                temp != origBookmark) {
                [dataSource setObject:nil forKey:KEY_SHORTCUT inBookmark:temp];
            }
        }

        [newDict setObject:shortcut forKey:KEY_SHORTCUT];
    }
    [newDict setObject:command forKey:KEY_COMMAND];
    [newDict setObject:text forKey:KEY_INITIAL_TEXT];
    [newDict setObject:dir forKey:KEY_WORKING_DIRECTORY];
    [newDict setObject:customCommand forKey:KEY_CUSTOM_COMMAND];
    [newDict setObject:customDir forKey:KEY_CUSTOM_DIRECTORY];

    // Just copy over advanced working dir settings
    NSArray *valuesToCopy = [NSArray arrayWithObjects:
        KEY_AWDS_WIN_OPTION,
        KEY_AWDS_WIN_DIRECTORY,
        KEY_AWDS_TAB_OPTION,
        KEY_AWDS_TAB_DIRECTORY,
        KEY_AWDS_PANE_OPTION,
        KEY_AWDS_PANE_DIRECTORY,
        nil];
    for (NSString *key in valuesToCopy) {
        id value = [origBookmark objectForKey:key];
        if (value) {
            [newDict setObject:value forKey:key];
        }
    }

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
    [newDict setObject:[NSNumber numberWithBool:[checkColorInvertedCursor state]] forKey:KEY_SMART_CURSOR_COLOR];
    [newDict setObject:[NSNumber numberWithFloat:[minimumContrast floatValue]] forKey:KEY_MINIMUM_CONTRAST];

    [cursorColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    [cursorTextColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorTextColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

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
    [newDict setObject:[NSNumber numberWithInt:[windowTypeButton selectedTag]] forKey:KEY_WINDOW_TYPE];
    [self setScreens];
    [newDict setObject:[NSNumber numberWithInt:[screenButton selectedTag]] forKey:KEY_SCREEN];
    if ([spaceButton selectedTag]) {
        [newDict setObject:[NSNumber numberWithInt:[spaceButton selectedTag]] forKey:KEY_SPACE];
     }
    [newDict setObject:[ITAddressBookMgr descFromFont:normalFont] forKey:KEY_NORMAL_FONT];
    [newDict setObject:[ITAddressBookMgr descFromFont:nonAsciiFont] forKey:KEY_NON_ASCII_FONT];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingWidth floatValue]] forKey:KEY_HORIZONTAL_SPACING];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingHeight floatValue]] forKey:KEY_VERTICAL_SPACING];
    [newDict setObject:[NSNumber numberWithBool:([blinkingCursor state]==NSOnState)] forKey:KEY_BLINKING_CURSOR];
    [newDict setObject:[NSNumber numberWithBool:([blinkAllowed state]==NSOnState)] forKey:KEY_BLINK_ALLOWED];
    [newDict setObject:[NSNumber numberWithInt:[[cursorType selectedCell] tag]] forKey:KEY_CURSOR_TYPE];
    [newDict setObject:[NSNumber numberWithBool:([useBoldFont state]==NSOnState)] forKey:KEY_USE_BOLD_FONT];
    [newDict setObject:[NSNumber numberWithBool:([useBrightBold state]==NSOnState)] forKey:KEY_USE_BRIGHT_BOLD];
    [newDict setObject:[NSNumber numberWithBool:([useItalicFont state]==NSOnState)] forKey:KEY_USE_ITALIC_FONT];
    [newDict setObject:[NSNumber numberWithFloat:[transparency floatValue]] forKey:KEY_TRANSPARENCY];
    [newDict setObject:[NSNumber numberWithFloat:[blend floatValue]] forKey:KEY_BLEND];
    [newDict setObject:[NSNumber numberWithFloat:[blurRadius floatValue]] forKey:KEY_BLUR_RADIUS];
    [newDict setObject:[NSNumber numberWithBool:([blur state]==NSOnState)] forKey:KEY_BLUR];
    [newDict setObject:[NSNumber numberWithBool:([asciiAntiAliased state]==NSOnState)] forKey:KEY_ASCII_ANTI_ALIASED];
    [newDict setObject:[NSNumber numberWithBool:([nonasciiAntiAliased state]==NSOnState)] forKey:KEY_NONASCII_ANTI_ALIASED];
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
    [newDict setObject:[NSNumber numberWithBool:([backgroundImageTiled state]==NSOnState)] forKey:KEY_BACKGROUND_IMAGE_TILED];

    // Terminal tab
    [newDict setObject:[NSNumber numberWithBool:([disableWindowResizing state]==NSOnState)] forKey:KEY_DISABLE_WINDOW_RESIZING];
    [newDict setObject:[NSNumber numberWithBool:([hideAfterOpening state]==NSOnState)] forKey:KEY_HIDE_AFTER_OPENING];
    [newDict setObject:[NSNumber numberWithBool:([syncTitle state]==NSOnState)] forKey:KEY_SYNC_TITLE];
    [newDict setObject:[NSNumber numberWithBool:([closeSessionsOnEnd state]==NSOnState)] forKey:KEY_CLOSE_SESSIONS_ON_END];
    [newDict setObject:[NSNumber numberWithBool:([nonAsciiDoubleWidth state]==NSOnState)] forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
    [newDict setObject:[NSNumber numberWithBool:([silenceBell state]==NSOnState)] forKey:KEY_SILENCE_BELL];
    [newDict setObject:[NSNumber numberWithBool:([visualBell state]==NSOnState)] forKey:KEY_VISUAL_BELL];
    [newDict setObject:[NSNumber numberWithBool:([flashingBell state]==NSOnState)] forKey:KEY_FLASHING_BELL];
    [newDict setObject:[NSNumber numberWithBool:([xtermMouseReporting state]==NSOnState)] forKey:KEY_XTERM_MOUSE_REPORTING];
    [newDict setObject:[NSNumber numberWithBool:([disableSmcupRmcup state]==NSOnState)] forKey:KEY_DISABLE_SMCUP_RMCUP];
    [newDict setObject:[NSNumber numberWithBool:([allowTitleReporting state]==NSOnState)] forKey:KEY_ALLOW_TITLE_REPORTING];
    [newDict setObject:[NSNumber numberWithBool:([disablePrinting state]==NSOnState)] forKey:KEY_DISABLE_PRINTING];
    [newDict setObject:[NSNumber numberWithBool:([scrollbackWithStatusBar state]==NSOnState)] forKey:KEY_SCROLLBACK_WITH_STATUS_BAR];
    [newDict setObject:[NSNumber numberWithBool:([scrollbackInAlternateScreen state]==NSOnState)] forKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN];
    [newDict setObject:[NSNumber numberWithBool:([bookmarkGrowlNotifications state]==NSOnState)] forKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS];
    [newDict setObject:[NSNumber numberWithBool:([setLocaleVars state]==NSOnState)] forKey:KEY_SET_LOCALE_VARS];
    [newDict setObject:[NSNumber numberWithBool:([autoLog state]==NSOnState)] forKey:KEY_AUTOLOG];
    [newDict setObject:[logDir stringValue] forKey:KEY_LOGDIR];
    [logDir setEnabled:[autoLog state] == NSOnState];
    [changeLogDir setEnabled:[autoLog state] == NSOnState];
    [self _updateLogDirWarning];
    [self _updatePrefsDirWarning];
    [newDict setObject:[NSNumber numberWithUnsignedInt:[[characterEncoding selectedItem] tag]] forKey:KEY_CHARACTER_ENCODING];
    [newDict setObject:[NSNumber numberWithInt:[scrollbackLines intValue]] forKey:KEY_SCROLLBACK_LINES];
    [newDict setObject:[NSNumber numberWithBool:([unlimitedScrollback state]==NSOnState)] forKey:KEY_UNLIMITED_SCROLLBACK];
    [scrollbackLines setEnabled:[unlimitedScrollback state]==NSOffState];
    if ([unlimitedScrollback state] == NSOnState) {
        [scrollbackLines setStringValue:@""];
    } else if (sender == unlimitedScrollback) {
        [scrollbackLines setStringValue:@"10000"];
    }
    
    [newDict setObject:[terminalType stringValue] forKey:KEY_TERMINAL_TYPE];
    [newDict setObject:[NSNumber numberWithBool:([sendCodeWhenIdle state]==NSOnState)] forKey:KEY_SEND_CODE_WHEN_IDLE];
    [newDict setObject:[NSNumber numberWithInt:[idleCode intValue]] forKey:KEY_IDLE_CODE];
    [newDict setObject:[NSNumber numberWithBool:([useCanonicalParser state]==NSOnState)] forKey:KEY_USE_CANONICAL_PARSER];

    // Keyboard tab
    [newDict setObject:[origBookmark objectForKey:KEY_KEYBOARD_MAP] forKey:KEY_KEYBOARD_MAP];
    [newDict setObject:[NSNumber numberWithInt:[[optionKeySends selectedCell] tag]] forKey:KEY_OPTION_KEY_SENDS];
    [newDict setObject:[NSNumber numberWithInt:[[rightOptionKeySends selectedCell] tag]] forKey:KEY_RIGHT_OPTION_KEY_SENDS];
    [newDict setObject:[tags objectValue] forKey:KEY_TAGS];

    BOOL reloadKeyMappings = NO;
     if (sender == deleteSendsCtrlHButton) {
        // Resolve any conflict between key mappings and delete sends ^h by
        // modifying key mappings.
        [self _setDeleteKeyMapToCtrlH:[deleteSendsCtrlHButton state] == NSOnState
                           inBookmark:newDict];
        reloadKeyMappings = YES;
    } else {
        // If a keymapping for the delete key was added, make sure the
        // delete sends ^h checkbox is correct
        BOOL sendCH = [self _deleteSendsCtrlHInBookmark:newDict];
        [deleteSendsCtrlHButton setState:sendCH ? NSOnState : NSOffState];
    }

    // Session tab
    [newDict setObject:[NSNumber numberWithInt:[[promptBeforeClosing_ selectedCell] tag]]
                forKey:KEY_PROMPT_CLOSE];
    [newDict setObject:[origBookmark objectForKey:KEY_JOBS] ? [origBookmark objectForKey:KEY_JOBS] : [NSArray array]
                forKey:KEY_JOBS];

    // Advanced tab
    [newDict setObject:[triggerWindowController_ triggers] forKey:KEY_TRIGGERS];
    [newDict setObject:[smartSelectionWindowController_ rules] forKey:KEY_SMART_SELECTION_RULES];
    [newDict setObject:[trouterPrefController_ prefs] forKey:KEY_TROUTER];

    // Epilogue
    [dataSource setBookmark:newDict withGuid:guid];
    [bookmarksTableView reloadData];
    if (reloadKeyMappings) {
        [keyMappings reloadData];
    }

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

- (IBAction)bookmarkUrlSchemeHandlerChanged:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSString* scheme = [[bookmarkUrlSchemes selectedItem] title];
    if ([urlHandlersByGuid objectForKey:scheme]) {
        [self disconnectHandlerForScheme:scheme];
    } else {
        [self connectBookmarkWithGuid:guid toScheme:scheme];
    }
    [self _populateBookmarkUrlSchemesFromDict:[dataSource bookmarkWithGuid:guid]];
}

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent
{
    return nil;
}

- (void)profileTableFilterDidChange:(ProfileListView*)profileListView
{
    [addBookmarkButton setEnabled:![profileListView searchFieldHasText]];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        [self bookmarkSettingChanged:nil];
    }
}

- (void)profileTableSelectionDidChange:(id)profileTable
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
        if (profileTable == bookmarksTableView) {
            NSString* guid = [bookmarksTableView selectedGuid];
            triggerWindowController_.guid = guid;
            smartSelectionWindowController_.guid = guid;
            trouterPrefController_.guid = guid;
            [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];
        }
    }
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
}

- (void)profileTableRowSelected:(id)profileTable
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
    } else if ([aNotification object] == globalKeyMappings) {
        int rowIndex = [globalKeyMappings selectedRow];
        if (rowIndex >= 0) {
            [globalRemoveMappingButton setEnabled:YES];
        } else {
            [globalRemoveMappingButton setEnabled:NO];
        }
    } else if ([aNotification object] == jobsTable_) {
        [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    }
}

- (IBAction)addJob:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    NSMutableArray *augmented;
    if (jobNames) {
        augmented = [NSMutableArray arrayWithArray:jobNames];
        [augmented addObject:@"Job Name"];
    } else {
        augmented = [NSArray arrayWithObject:@"Job Name"];
    }
    [dataSource setObject:augmented forKey:KEY_JOBS inBookmark:bookmark];
    [jobsTable_ reloadData];
    [jobsTable_ selectRowIndexes:[NSIndexSet indexSetWithIndex:[augmented count] - 1]
            byExtendingSelection:NO];
    [jobsTable_ editColumn:0
                       row:[self numberOfRowsInTableView:jobsTable_] - 1
                 withEvent:nil
                    select:YES];
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    [self bookmarkSettingChanged:nil];
}

- (IBAction)removeJob:(id)sender
{
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [jobsTable_ reloadData];

    NSInteger selectedIndex = [jobsTable_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    NSMutableArray *mod = [NSMutableArray arrayWithArray:jobNames];
    [mod removeObjectAtIndex:selectedIndex];

    [dataSource setObject:mod forKey:KEY_JOBS inBookmark:bookmark];
    [jobsTable_ reloadData];
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    [self bookmarkSettingChanged:nil];
}

- (IBAction)showGlobalTabView:(id)sender
{
    [tabView selectTabViewItem:globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender
{
    [tabView selectTabViewItem:appearanceTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender
{
    [tabView selectTabViewItem:keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender
{
  [tabView selectTabViewItem:arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender
{
  [tabView selectTabViewItem:mouseTabViewItem];
}

- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme
{
    NSURL *appURL = nil;
    OSStatus err;
    BOOL set = YES;

    err = LSGetApplicationForURL(
        (CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]],
                                 kLSRolesAll, NULL, (CFURLRef *)&appURL);
    if (err != noErr) {
        set = NSRunAlertPanel([NSString stringWithFormat:@"iTerm is not the default handler for %@. Would you like to set iTerm as the default handler?",
                               scheme],
                @"There is currently no handler.",
                @"OK",
                @"Cancel",
                nil) == NSAlertDefaultReturn;
    } else if (![[[NSFileManager defaultManager] displayNameAtPath:[appURL path]] isEqualToString:@"iTerm 2"]) {
        set = NSRunAlertPanel([NSString stringWithFormat:@"iTerm is not the default handler for %@. Would you like to set iTerm as the default handler?",
                               scheme],
                              [NSString stringWithFormat:@"The current handler is: %@",
                               [[NSFileManager defaultManager] displayNameAtPath:[appURL path]]],
                @"OK",
                @"Cancel",
                nil) == NSAlertDefaultReturn;
    }

    if (set) {
        [urlHandlersByGuid setObject:guid
                              forKey:scheme];
        LSSetDefaultHandlerForURLScheme((CFStringRef)scheme,
                                        (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    }
}

- (void)disconnectHandlerForScheme:(NSString*)scheme
{
    [urlHandlersByGuid removeObjectForKey:scheme];
}

- (IBAction)closeWindow:(id)sender
{
    [[self window] close];
}

- (IBAction)selectLogDir:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSOKButton) {
        [logDir setStringValue:[panel directory]];
    }
    [self _updateLogDirWarning];
}

// Pick out the digits from s and clamp it to a range.
- (int)intForString:(NSString *)s inRange:(NSRange)range
{
    NSMutableString *i = [NSMutableString string];
    for (int j = 0; j < s.length; j++) {
        unichar c = [s characterAtIndex:j];
        if (c >= '0' && c <= '9') {
            [i appendFormat:@"%c", (char)c];
        }
    }

    int val = 0;
    if ([i length]) {
        val = [i intValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length);
    return val;
}

- (void)forceTextFieldToBeNumber:(NSTextField *)textField
				 acceptableRange:(NSRange)range
{
	// NSNumberFormatter seems to have lost its mind on Lion. See a description of the problem here:
	// http://stackoverflow.com/questions/7976951/nsnumberformatter-erasing-value-when-it-violates-constraints
	int iv = [self intForString:[textField stringValue] inRange:range];
	unichar lastChar = '0';
	int numChars = [[textField stringValue] length];
	if (numChars) {
		lastChar = [[textField stringValue] characterAtIndex:numChars - 1];
	}
	if (iv != [textField intValue] || (lastChar < '0' || lastChar > '9')) {
		// If the int values don't match up or there are terminal non-number
		// chars, then update the value.
		[textField setIntValue:iv];
	}
}

// NSTextField delegate
- (void)controlTextDidChange:(NSNotification *)aNotification
{
    id obj = [aNotification object];
    if (obj == wordChars) {
        defaultWordChars = [[wordChars stringValue] retain];
	} else if (obj == tmuxDashboardLimit) {
		[self forceTextFieldToBeNumber:tmuxDashboardLimit
					   acceptableRange:NSMakeRange(0, 1000)];
		defaultTmuxDashboardLimit = [[tmuxDashboardLimit stringValue] intValue];
    } else if (obj == scrollbackLines) {
		[self forceTextFieldToBeNumber:scrollbackLines
					   acceptableRange:NSMakeRange(0, 10 * 1000 * 1000)];
        [self bookmarkSettingChanged:nil];
    } else if (obj == columnsField ||
               obj == rowsField ||
               obj == terminalType ||
               obj == initialText ||
               obj == idleCode) {
        [self bookmarkSettingChanged:nil];
    } else if (obj == logDir) {
        [self _updateLogDirWarning];
    } else if (obj == prefsCustomFolder) {
        [self settingChanged:prefsCustomFolder];
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

    defaultHotkeyChar = keyChar;
    defaultHotkeyCode = keyCode;
    defaultHotkeyModifiers = keyMods;
    [[[PreferencePanel sharedInstance] window] makeFirstResponder:[[PreferencePanel sharedInstance] window]];
    [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", keyChar, keyMods]]];
    [self performSelector:@selector(setHotKey) withObject:self afterDelay:0.01];
}

- (void)setHotKey
{
    [[iTermController sharedInstance] registerHotkey:defaultHotkeyCode modifiers:defaultHotkeyModifiers];
}

- (void)updateValueToSend
{
    int tag = [[action selectedItem] tag];
    if (tag == KEY_ACTION_HEX_CODE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"ex: 0x7f 0x20"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_TEXT) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"Enter value to send"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_RUN_COPROCESS) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"Enter command to run"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_SELECT_MENU_ITEM) {
        [valueToSend setHidden:YES];
        [[valueToSend cell] setPlaceholderString:@"Enter name of menu item"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [menuToSelect setHidden:NO];
        [profileLabel setHidden:YES];
    } else if (tag == KEY_ACTION_ESCAPE_SEQUENCE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"characters to send"];
        [escPlus setHidden:NO];
        [escPlus setStringValue:@"Esc+"];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
               tag == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
               tag == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
               tag == KEY_ACTION_NEW_WINDOW_WITH_PROFILE) {
        [valueToSend setHidden:YES];
        [profileLabel setHidden:NO];
        [bookmarkPopupButton setHidden:NO];
        [escPlus setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_DO_NOT_REMAP_MODIFIERS ||
               tag == KEY_ACTION_REMAP_LOCALLY) {
        [valueToSend setHidden:YES];
        [valueToSend setStringValue:@""];
        [escPlus setHidden:NO];
        [escPlus setStringValue:@"Modifier remapping disabled: type the actual key combo you want to affect."];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else {
        [valueToSend setHidden:YES];
        [valueToSend setStringValue:@""];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    }
}

- (IBAction)actionChanged:(id)sender
{
    [action setTitle:[[sender selectedItem] title]];
    [PreferencePanel populatePopUpButtonWithBookmarks:bookmarkPopupButton
                                         selectedGuid:[[bookmarkPopupButton selectedItem] representedObject]];
    [PreferencePanel populatePopUpButtonWithMenuItems:menuToSelect
                                        selectedValue:[[menuToSelect selectedItem] title]];
    [self updateValueToSend];
}

- (NSWindow*)keySheet
{
    return editKeyMappingWindow;
}


- (void)_addMappingWithContextInfo:(id)info
{
    if (keyString) {
        [keyString release];
    }
    [keyPress setStringValue:@""];
    keyString = [[NSString alloc] init];
    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    for (NSMenuItem* item in [action itemArray]) {
        [item setState:NSOffState];
    }
    [action selectItemWithTag:KEY_ACTION_IGNORE];
    [valueToSend setStringValue:@""];
    [self updateValueToSend];
    newMapping = YES;

    modifyMappingOriginator = info;
    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:info];
}

- (IBAction)addNewMapping:(id)sender
{
    [self _addMappingWithContextInfo:sender];
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

- (IBAction)globalRemoveMapping:(id)sender
{
    [iTermKeyBindingMgr setGlobalKeyMap:[iTermKeyBindingMgr removeMappingAtIndex:[globalKeyMappings selectedRow]
                                                                    inDictionary:[iTermKeyBindingMgr globalKeyMap]]];
    [self settingChanged:nil];
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

- (void)setGlobalKeyMappingsToPreset:(NSString*)presetName
{
    [iTermKeyBindingMgr setGlobalKeyMappingsToPreset:presetName];
    [globalKeyMappings reloadData];
    [self settingChanged:nil];
}

- (IBAction)presetKeyMappingsItemSelected:(id)sender
{
    [self setKeyMappingsToPreset:[[sender selectedItem] title]];
}

- (IBAction)useFactoryGlobalKeyMappings:(id)sender
{
    [self setGlobalKeyMappingsToPreset:@"Factory Defaults"];
}

- (void)_loadPresetColors:(NSString*)presetName
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");

    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                        ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    NSDictionary* settings = [presetsDict objectForKey:presetName];
    if (!settings) {
        presetsDict = [[NSUserDefaults standardUserDefaults] objectForKey:CUSTOM_COLOR_PRESETS];
        settings = [presetsDict objectForKey:presetName];
    }
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

- (void)loadColorPreset:(id)sender;
{
    [self _loadPresetColors:[sender title]];
}

- (IBAction)addBookmark:(id)sender
{
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] init] autorelease];
    // Copy the default bookmark's settings in
    Profile* prototype = [dataSource defaultBookmark];
    if (!prototype) {
        [ITAddressBookMgr setDefaultsInBookmark:newDict];
    } else {
        [newDict setValuesForKeysWithDictionary:[dataSource defaultBookmark]];
    }
    [newDict setObject:@"New Profile" forKey:KEY_NAME];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    NSString* guid = [ProfileModel freshGuid];
    [newDict setObject:guid forKey:KEY_GUID];
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove depreated attribute with side effects
    [newDict setObject:[NSArray arrayWithObjects:nil] forKey:KEY_TAGS];
    if ([[ProfileModel sharedInstance] bookmark:newDict hasTag:@"bonjour"]) {
        [newDict removeObjectForKey:KEY_BONJOUR_GROUP];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE_ADDRESS];
        [newDict setObject:@"" forKey:KEY_COMMAND];
        [newDict setObject:@"" forKey:KEY_INITIAL_TEXT];
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

- (void)_removeKeyMappingsReferringToBookmarkGuid:(NSString*)badRef
{
    for (NSString* guid in [[ProfileModel sharedInstance] guids]) {
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        bookmark = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:bookmark];
        if (bookmark) {
            [[ProfileModel sharedInstance] setBookmark:bookmark withGuid:guid];
        }
    }
    for (NSString* guid in [[ProfileModel sessionsInstance] guids]) {
        Profile* bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:guid];
        bookmark = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:bookmark];
        if (bookmark) {
            [[ProfileModel sessionsInstance] setBookmark:bookmark withGuid:guid];
        }
    }
    [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:nil];
    [[PreferencePanel sharedInstance]->keyMappings reloadData];
    [[PreferencePanel sessionsInstance]->keyMappings reloadData];
}

- (BOOL)confirmProfileDeletion:(NSArray *)guids {
    NSMutableString *question = [NSMutableString stringWithString:@"Delete profile"];
    if (guids.count > 1) {
        [question appendString:@"s "];
    } else {
        [question appendString:@" "];
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *guid in guids) {
        Profile *profile = [dataSource bookmarkWithGuid:guid];
        NSString *name = [profile objectForKey:KEY_NAME];
        [names addObject:[NSString stringWithFormat:@"\"%@\"", name]];
    }
    [question appendString:[names componentsJoinedByString:@", "]];
    [question appendString:@"?"];
    static NSTimeInterval lastQuell;
    NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    if (lastQuell && (now - lastQuell) < 600) {
        return YES;
    }

    NSAlert *alert;
    alert = [NSAlert alertWithMessageText:@"Confirm Deletion"
                            defaultButton:@"Delete"
                          alternateButton:@"Cancel"
                              otherButton:nil
                informativeTextWithFormat:@"%@", question];
    [alert setShowsSuppressionButton:YES];
    [[alert suppressionButton] setTitle:@"Suppress deletion confirmations temporarily."];
    BOOL result = NO;
    if ([alert runModal] == NSAlertDefaultReturn) {
        result = YES;
    }
    if ([[alert suppressionButton] state] == NSOnState) {
        lastQuell = now;
    }
    return result;
}

- (IBAction)removeBookmark:(id)sender
{
    if ([dataSource numberOfBookmarks] == 1) {
        NSBeep();
    } else {
        if ([self confirmProfileDeletion:[[bookmarksTableView selectedGuids] allObjects]]) {
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
                [self _removeKeyMappingsReferringToBookmarkGuid:guid];
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
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    NSString* newName = [NSString stringWithFormat:@"Copy of %@", [newDict objectForKey:KEY_NAME]];

    [newDict setObject:newName forKey:KEY_NAME];
    [newDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [newDict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    [dataSource addBookmark:newDict];
    [bookmarksTableView reloadData];
    [bookmarksTableView selectRowByGuid:[newDict objectForKey:KEY_GUID]];
}

- (BOOL)remappingDisabledTemporarily
{
    return [[self keySheet] isKeyWindow] && [self keySheetIsOpen] && ([action selectedTag] == KEY_ACTION_DO_NOT_REMAP_MODIFIERS ||
                                                                      [action selectedTag] == KEY_ACTION_REMAP_LOCALLY);
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
    [setProfileBookmarkListView selectRowByGuid:nil];
    [bookmarksSettingsTabViewParent selectTabViewItem:bookmarkSettingsGeneralTab];
    [[self window] makeFirstResponder:bookmarkName];
}

- (IBAction)openCopyBookmarks:(id)sender
{
    [bulkCopyLabel setStringValue:[NSString stringWithFormat:
                                   @"Copy these settings from profile \"%@\":",
                                   [[dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]] objectForKey:KEY_NAME]]];
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
        if ([copyWindow state] == NSOnState) {
            [self copyAttributes:BulkCopyWindow fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyTerminal state] == NSOnState) {
            [self copyAttributes:BulkCopyTerminal fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyKeyboard state] == NSOnState) {
            [self copyAttributes:BulkCopyKeyboard fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copySession state] == NSOnState) {
            [self copyAttributes:BulkCopySession fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyAdvanced state] == NSOnState) {
            [self copyAttributes:BulkCopyAdvanced fromBookmark:srcGuid toBookmark:destGuid];
        }
    }
    [NSApp endSheet:copyPanel];
}

- (void)copyAttributes:(BulkCopySettings)attributes fromBookmark:(NSString*)guid toBookmark:(NSString*)destGuid
{
    Profile* dest = [dataSource bookmarkWithGuid:destGuid];
    Profile* src = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] initWithDictionary:dest] autorelease];
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
        KEY_SMART_CURSOR_COLOR,
        KEY_MINIMUM_CONTRAST,
        nil
    };
    NSString* displayKeys[] = {
        KEY_NORMAL_FONT,
        KEY_NON_ASCII_FONT,
        KEY_HORIZONTAL_SPACING,
        KEY_VERTICAL_SPACING,
        KEY_BLINKING_CURSOR,
        KEY_BLINK_ALLOWED,
        KEY_CURSOR_TYPE,
        KEY_USE_BOLD_FONT,
        KEY_USE_BRIGHT_BOLD,
        KEY_USE_ITALIC_FONT,
        KEY_ASCII_ANTI_ALIASED,
        KEY_NONASCII_ANTI_ALIASED,
        KEY_ANTI_ALIASING,
        KEY_AMBIGUOUS_DOUBLE_WIDTH,
        nil
    };
    NSString* windowKeys[] = {
        KEY_ROWS,
        KEY_COLUMNS,
        KEY_WINDOW_TYPE,
        KEY_SCREEN,
        KEY_SPACE,
        KEY_TRANSPARENCY,
        KEY_BLEND,
        KEY_BLUR_RADIUS,
        KEY_BLUR,
        KEY_BACKGROUND_IMAGE_LOCATION,
        KEY_BACKGROUND_IMAGE_TILED,
        KEY_SYNC_TITLE,
        KEY_DISABLE_WINDOW_RESIZING,
        KEY_HIDE_AFTER_OPENING,
        nil
    };
    NSString* terminalKeys[] = {
        KEY_SILENCE_BELL,
        KEY_VISUAL_BELL,
        KEY_FLASHING_BELL,
        KEY_XTERM_MOUSE_REPORTING,
        KEY_DISABLE_SMCUP_RMCUP,
        KEY_ALLOW_TITLE_REPORTING,
        KEY_DISABLE_PRINTING,
        KEY_CHARACTER_ENCODING,
        KEY_SCROLLBACK_LINES,
        KEY_SCROLLBACK_WITH_STATUS_BAR,
        KEY_SCROLLBACK_IN_ALTERNATE_SCREEN,
        KEY_UNLIMITED_SCROLLBACK,
        KEY_TERMINAL_TYPE,
        KEY_USE_CANONICAL_PARSER,
        nil
    };
    NSString *sessionKeys[] = {
        KEY_CLOSE_SESSIONS_ON_END,
        KEY_BOOKMARK_GROWL_NOTIFICATIONS,
        KEY_SET_LOCALE_VARS,
        KEY_AUTOLOG,
        KEY_LOGDIR,
        KEY_SEND_CODE_WHEN_IDLE,
        KEY_IDLE_CODE,
    };

    NSString* keyboardKeys[] = {
        KEY_KEYBOARD_MAP,
        KEY_OPTION_KEY_SENDS,
        nil
    };
    NSString *advancedKeys[] = {
        KEY_TRIGGERS,
        KEY_SMART_SELECTION_RULES,
        nil
    };
    switch (attributes) {
        case BulkCopyColors:
            keys = colorsKeys;
            break;
        case BulkCopyDisplay:
            keys = displayKeys;
            break;
        case BulkCopyWindow:
            keys = windowKeys;
            break;
        case BulkCopyTerminal:
            keys = terminalKeys;
            break;
        case BulkCopyKeyboard:
            keys = keyboardKeys;
            break;
        case BulkCopySession:
            keys = sessionKeys;
            break;
        case BulkCopyAdvanced:
            keys = advancedKeys;
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

- (BOOL)hotkeyTogglesWindow
{
    return defaultHotkeyTogglesWindow;
}

- (BOOL)dockIconTogglesWindow
{
    assert(prefs);
    return [prefs boolForKey:@"dockIconTogglesWindow"];
}

- (Profile*)hotkeyBookmark
{
    if (defaultHotKeyBookmarkGuid) {
        return [[ProfileModel sharedInstance] bookmarkWithGuid:defaultHotKeyBookmarkGuid];
    } else {
        return nil;
    }
}

- (void)triggerChanged:(TriggerController *)triggerController
{
  [self bookmarkSettingChanged:nil];
}

- (void)smartSelectionChanged:(SmartSelectionController *)smartSelectionController
{
    [self bookmarkSettingChanged:nil];
}

@end


@implementation PreferencePanel (Private)

- (void)_reloadURLHandlers:(NSNotification *)aNotification
{
    // TODO: maybe something here for the current bookmark?
    [self _populateHotKeyBookmarksMenu];
}

@end

@implementation PreferencePanel (KeyValueCoding)

// An experiment with cocoa bindings. This is bound to the "enabled" status of
// the "remove job" button.
- (BOOL)haveJobsForCurrentBookmark
{
    if ([jobsTable_ selectedRow] < 0) {
        return NO;
    }
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return NO;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    return [jobNames count] > 0;
}

- (void)setHaveJobsForCurrentBookmark:(BOOL)value
{
    // observed but has no effect because the getter does all the computation.
}

@end
