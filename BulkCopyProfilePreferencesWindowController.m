//
//  BulkCopyProfilePreferencesWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "BulkCopyProfilePreferencesWindowController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"
#import "ProfileListView.h"
#import "ProfileModel.h"

typedef enum {
    BulkCopyColors,
    BulkCopyText,
    BulkCopyWindow,
    BulkCopyTerminal,
    BulkCopyKeyboard,
    BulkCopySession,
    BulkCopyAdvanced,
} BulkCopySettings;


@implementation BulkCopyProfilePreferencesWindowController {
    // Copy Profile Settings...
    IBOutlet NSTextField *_bulkCopyLabel;
    IBOutlet NSButton *_copyColors;
    IBOutlet NSButton *_copyText;
    IBOutlet NSButton *_copyTerminal;
    IBOutlet NSButton *_copyWindow;
    IBOutlet NSButton *_copyKeyboard;
    IBOutlet NSButton *_copySession;
    IBOutlet NSButton *_copyAdvanced;
    IBOutlet ProfileListView *_copyTo;
    IBOutlet NSButton *_copyButton;
}

- (id)init {
    return [super initWithWindowNibName:@"BulkCopyProfilePreferences"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_sourceGuid release];
    [super dealloc];
}

- (void)awakeFromNib {
    [_copyTo allowMultipleSelections];
    [self updateLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileFieldsDidChange)
                                                 name:kPreferencePanelDidUpdateProfileFields
                                               object:nil];
}

- (void)setSourceGuid:(NSString *)sourceGuid {
    [_sourceGuid autorelease];
    _sourceGuid = [sourceGuid copy];
    [self updateLabel];
}

#pragma mark - Actions

- (IBAction)performBulkCopy:(id)sender {
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    if (!_sourceGuid || ![profileModel bookmarkWithGuid:_sourceGuid]) {
        NSBeep();
        return;
    }
    
    NSSet* destGuids = [_copyTo selectedGuids];
    for (NSString* destGuid in destGuids) {
        if ([destGuid isEqualToString:_sourceGuid]) {
            continue;
        }
        
        if (![profileModel bookmarkWithGuid:destGuid]) {
            NSLog(@"Selected profile %@ doesn't exist", destGuid);
            continue;
        }
        
        if ([_copyColors state] == NSOnState) {
            [self copyAttributes:BulkCopyColors fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyText state] == NSOnState) {
            [self copyAttributes:BulkCopyText fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyWindow state] == NSOnState) {
            [self copyAttributes:BulkCopyWindow fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyTerminal state] == NSOnState) {
            [self copyAttributes:BulkCopyTerminal fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyKeyboard state] == NSOnState) {
            [self copyAttributes:BulkCopyKeyboard fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copySession state] == NSOnState) {
            [self copyAttributes:BulkCopySession fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyAdvanced state] == NSOnState) {
            [self copyAttributes:BulkCopyAdvanced fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
    }
    [NSApp endSheet:self.window];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];
}

- (IBAction)cancelBulkCopy:(id)sender {
    [NSApp endSheet:self.window];
}

#pragma mark - Private

- (void)updateLabel {
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:_sourceGuid];
    [_bulkCopyLabel setStringValue:[NSString stringWithFormat:
                                    @"Copy these settings from profile “%@”:",
                                    profile[KEY_NAME]]];
}

- (void)copyAttributes:(BulkCopySettings)attributes
   fromProfileWithGuid:(NSString*)guid
     toProfileWithGuid:(NSString*)destGuid {
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    
    Profile* dest = [profileModel bookmarkWithGuid:destGuid];
    Profile* src = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] initWithDictionary:dest] autorelease];
    NSArray *keys = nil;
    
    NSArray *colorsKeys = @[
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
    ];
    NSArray *textKeys = @[
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
        KEY_USE_NONASCII_FONT,
        KEY_ANTI_ALIASING,
        KEY_AMBIGUOUS_DOUBLE_WIDTH,
    ];
    NSArray *windowKeys = @[
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
        KEY_PREVENT_TAB,
        KEY_HIDE_AFTER_OPENING,
    ];
    NSArray *terminalKeys = @[
        KEY_XTERM_MOUSE_REPORTING,
        KEY_DISABLE_SMCUP_RMCUP,
        KEY_ALLOW_TITLE_REPORTING,
        KEY_ALLOW_TITLE_SETTING,
        KEY_DISABLE_PRINTING,
        KEY_CHARACTER_ENCODING,
        KEY_SCROLLBACK_LINES,
        KEY_SCROLLBACK_WITH_STATUS_BAR,
        KEY_SCROLLBACK_IN_ALTERNATE_SCREEN,
        KEY_UNLIMITED_SCROLLBACK,
        KEY_TERMINAL_TYPE,
        KEY_USE_CANONICAL_PARSER,
        KEY_SILENCE_BELL,
        KEY_VISUAL_BELL,
        KEY_FLASHING_BELL,
        KEY_BOOKMARK_GROWL_NOTIFICATIONS,
        KEY_SET_LOCALE_VARS,
    ];
    NSArray *sessionKeys = @[
        KEY_CLOSE_SESSIONS_ON_END,
        KEY_PROMPT_CLOSE,
        KEY_JOBS,
        KEY_AUTOLOG,
        KEY_LOGDIR,
        KEY_SEND_CODE_WHEN_IDLE,
        KEY_IDLE_CODE,
    ];
    
    NSArray *keyboardKeys = @[
        KEY_KEYBOARD_MAP,
        KEY_OPTION_KEY_SENDS,
        KEY_RIGHT_OPTION_KEY_SENDS,
        KEY_APPLICATION_KEYPAD_ALLOWED,
    ];
    NSArray *advancedKeys = @[
        KEY_TRIGGERS,
        KEY_SMART_SELECTION_RULES,
    ];
    switch (attributes) {
        case BulkCopyColors:
            keys = colorsKeys;
            break;
        case BulkCopyText:
            keys = textKeys;
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
    
    for (NSString *theKey in keys) {
        id srcValue = [src objectForKey:theKey];
        if (srcValue) {
            [newDict setObject:srcValue forKey:theKey];
        } else {
            [newDict removeObjectForKey:theKey];
        }
    }
    
    [profileModel setBookmark:newDict withGuid:[dest objectForKey:KEY_GUID]];
}


#pragma mark - Notifications

- (void)profileFieldsDidChange {
    [_copyTo reloadData];
}

@end
