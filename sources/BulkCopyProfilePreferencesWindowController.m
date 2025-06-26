//
//  BulkCopyProfilePreferencesWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "BulkCopyProfilePreferencesWindowController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
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
    BulkCopyWeb
} BulkCopySettings;

// These match labels in the profiles tab view. I guess it should be identifiers but I would probably forget to set them.
NSString *const iTermBulkCopyIdentifierColors = @"Colors";
NSString *const iTermBulkCopyIdentifierText = @"Text";
NSString *const iTermBulkCopyIdentifierWeb = @"Web";
NSString *const iTermBulkCopyIdentifierWindow = @"Window";
NSString *const iTermBulkCopyIdentifierTerminal = @"Terminal";
NSString *const iTermBulkCopyIdentifierSession = @"Session";
NSString *const iTermBulkCopyIdentifierKeys = @"Keys";
NSString *const iTermBulkCopyIdentifierAdvanced = @"Advanced";

@implementation BulkCopyProfilePreferencesWindowController {
    // Copy Profile Settings...
    IBOutlet NSTextField *_bulkCopyLabel;
    IBOutlet NSButton *_copyColors;
    IBOutlet NSButton *_copyText;
    IBOutlet NSButton *_copyWeb;
    IBOutlet NSButton *_copyTerminal;
    IBOutlet NSButton *_copyWindow;
    IBOutlet NSButton *_copyKeyboard;
    IBOutlet NSButton *_copySession;
    IBOutlet NSButton *_copyAdvanced;
    IBOutlet ProfileListView *_copyTo;
    IBOutlet NSButton *_copyButton;
    NSArray<NSString *> *_identifiersToKeep;
    ProfileType _profileTypes;
}

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                       profileTypes:(ProfileType)profileTypes {
    self = [super initWithWindowNibName:@"BulkCopyProfilePreferences"];
    if (self) {
        _profileTypes = profileTypes;
        _identifiersToKeep = [identifiers copy];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    _copyTo.profileTypes = _profileTypes;
    NSDictionary *map = @{
        iTermBulkCopyIdentifierColors: _copyColors,
        iTermBulkCopyIdentifierText: _copyText,
        iTermBulkCopyIdentifierWeb: _copyWeb,
        iTermBulkCopyIdentifierWindow: _copyWindow,
        iTermBulkCopyIdentifierTerminal: _copyTerminal,
        iTermBulkCopyIdentifierSession: _copySession,
        iTermBulkCopyIdentifierKeys: _copyKeyboard,
        iTermBulkCopyIdentifierAdvanced: _copyAdvanced,
    };
    [map enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSView *view, BOOL * _Nonnull stop) {
        if (![_identifiersToKeep containsObject:key]) {
            view.hidden = YES;
        }
    }];
    NSArray<NSView *> *views = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(NSView *lhs, NSView *rhs) {
        return [@(lhs.frame.origin.x) compare:@(rhs.frame.origin.x)];
    }];

    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];
    for (NSUInteger i = 1; i < views.count; i++) {
        [offsets addObject:@(views[i].frame.origin.x - views[i - 1].frame.origin.x)];
    }
    CGFloat x = views.firstObject.frame.origin.x;
    NSUInteger i = 0;

    for (NSView *view in views) {
        NSRect frame = view.frame;
        if (!view.hidden) {
            frame.origin.x = x;
            view.frame = frame;
            if (i < offsets.count) {
                x += offsets[i].doubleValue;
            }
        }
        i += 1;
    }

    [_copyTo allowMultipleSelections];
    [self updateLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileFieldsDidChange)
                                                 name:kPreferencePanelDidUpdateProfileFields
                                               object:nil];
}

- (void)setSourceGuid:(NSString *)sourceGuid {
    _sourceGuid = [sourceGuid copy];
    [self updateLabel];
}

#pragma mark - Actions

- (IBAction)performBulkCopy:(id)sender {
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    if (!_sourceGuid || ![profileModel bookmarkWithGuid:_sourceGuid]) {
        DLog(@"Beep: bulk copy failed");
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

        if ([_copyColors state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyColors fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyText state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyText fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyWeb state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyWeb fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyWindow state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyWindow fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyTerminal state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyTerminal fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyKeyboard state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopyKeyboard fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copySession state] == NSControlStateValueOn) {
            [self copyAttributes:BulkCopySession fromProfileWithGuid:_sourceGuid toProfileWithGuid:destGuid];
        }
        if ([_copyAdvanced state] == NSControlStateValueOn) {
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
    NSMutableDictionary* newDict = [dest mutableCopy];
    NSArray *keys = nil;

    switch (attributes) {
        case BulkCopyColors:
            keys = _keysForColors;
            break;
        case BulkCopyText:
            keys = _keysForText;
            break;
        case BulkCopyWeb:
            keys = _keysForWeb;
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
