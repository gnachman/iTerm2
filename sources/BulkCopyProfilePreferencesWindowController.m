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

- (instancetype)init {
    return [super initWithWindowNibName:@"BulkCopyProfilePreferences"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_sourceGuid release];
    [_keysForColors release];
    [_keysForText release];
    [_keysForWindow release];
    [_keysForTerminal release];
    [_keysForSession release];
    [_keysForKeyboard release];
    [_keysForAdvanced release];
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
    [self.window.sheetParent endSheet:self.window];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];
}

- (IBAction)cancelBulkCopy:(id)sender {
    [self.window.sheetParent endSheet:self.window];
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

    switch (attributes) {
        case BulkCopyColors:
            keys = _keysForColors;
            break;
        case BulkCopyText:
            keys = _keysForText;
            break;
        case BulkCopyWindow:
            keys = _keysForWindow;
            break;
        case BulkCopyTerminal:
            keys = _keysForTerminal;
            break;
        case BulkCopyKeyboard:
            keys = _keysForKeyboard;
            break;
        case BulkCopySession:
            keys = _keysForSession;
            break;
        case BulkCopyAdvanced:
            keys = _keysForAdvanced;
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
