//
//  iTermSemanticHistoryPrefsController.m
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "iTermSemanticHistoryPrefsController.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"

NSString *kSemanticHistoryActionKey = @"action";
NSString *kSemanticHistoryEditorKey = @"editor";
NSString *kSemanticHistoryTextKey = @"text";

NSString *kSublimeText2Identifier = @"com.sublimetext.2";
NSString *kSublimeText3Identifier = @"com.sublimetext.3";
NSString *kMacVimIdentifier = @"org.vim.MacVim";
NSString *kTextmateIdentifier = @"com.macromates.textmate";
NSString *kTextmate2Identifier = @"com.macromates.TextMate.preview";
NSString *kBBEditIdentifier = @"com.barebones.bbedit";
NSString *kAtomIdentifier = @"com.github.atom";
NSString *kSemanticHistoryBestEditorAction = @"best editor";
NSString *kSemanticHistoryUrlAction = @"url";
NSString *kSemanticHistoryEditorAction = @"editor";
NSString *kSemanticHistoryCommandAction = @"command";
NSString *kSemanticHistoryRawCommandAction = @"raw command";
NSString *kSemanticHistoryCoprocessAction = @"coprocess";

@implementation iTermSemanticHistoryPrefsController {
    NSString *guid_;
    IBOutlet NSPopUpButton *action_;
    IBOutlet NSTextField *text_;
    IBOutlet NSPopUpButton *editors_;
    IBOutlet NSTextField *caveat_;
}

enum {
    kSublimeText2Tag = 1,
    kMacVimTag,
    kTextmateTag,
    kBBEditTag,
    kSublimeText3Tag,
    kAtomTag,
    kTextmate2Tag,
    // Only append to the end of the list; never delete or change.
};

@synthesize guid = guid_;

+ (NSDictionary *)defaultPrefs {
    return @{ kSemanticHistoryActionKey: kSemanticHistoryBestEditorAction };
}

- (void)dealloc
{
    [guid_ release];
    [super dealloc];
}

+ (BOOL)applicationExists:(NSString *)bundle_id
{
    CFURLRef appURL = nil;
    OSStatus result = LSFindApplicationForInfo(kLSUnknownCreator,
                                               (CFStringRef)bundle_id,
                                               NULL,
                                               NULL,
                                               &appURL);
    
    if (appURL) {
        CFRelease(appURL);
    }
    
    switch (result) {
        case noErr:
            if ([bundle_id isEqualToString:kSublimeText2Identifier] ||
                [bundle_id isEqualToString:kSublimeText3Identifier]) {
                // Extra check for sublime text.
                if (![[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundle_id]) {
                    return NO;
                } else {
                    return YES;
                }
            } else {
                return YES;
            }
        case kLSApplicationNotFoundErr:
            return NO;
        default:
            return NO;
    }
}

+ (NSString *)schemeForEditor:(NSString *)editor {
    NSDictionary *schemes = @{ kSublimeText2Identifier: @"subl",
                               kSublimeText3Identifier: @"subl",
                               kMacVimIdentifier: @"mvim",
                               kTextmateIdentifier: @"txmt",
                               kTextmate2Identifier: @"txmt",
                               kBBEditIdentifier: @"txmt",
                               kAtomIdentifier: @"atom" };
    return schemes[editor];
}

+ (NSArray *)editorsInPreferenceOrder {
    // Editors from most to least preferred.
    return @[ kSublimeText3Identifier,
              kSublimeText2Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier,
              kAtomIdentifier ];
}

+ (NSString *)bestEditor {
    NSDictionary *overrides = @{ kTextmate2Identifier: kTextmateIdentifier };

    for (NSString *identifier in [self editorsInPreferenceOrder]) {
        if ([iTermSemanticHistoryPrefsController applicationExists:identifier]) {
            return overrides[identifier] ?: identifier;
        }
    }
    return nil;
}

+ (BOOL)bundleIdIsEditor:(NSString *)bundleId {
    NSArray *editorBundleIds = @[ kSublimeText2Identifier,
                                  kSublimeText3Identifier,
                                  kMacVimIdentifier,
                                  kTextmateIdentifier,
                                  kTextmate2Identifier,
                                  kBBEditIdentifier,
                                  kAtomIdentifier ];
    return [editorBundleIds containsObject:bundleId];
}

+ (NSDictionary *)identifierToTagMap {
    NSDictionary *tags = @{ kSublimeText3Identifier: @(kSublimeText3Tag),
                            kSublimeText2Identifier: @(kSublimeText2Tag),
                                  kMacVimIdentifier: @(kMacVimTag),
                                kTextmateIdentifier: @(kTextmateTag),
                               kTextmate2Identifier: @(kTextmate2Tag),
                                  kBBEditIdentifier: @(kBBEditTag),
                                    kAtomIdentifier: @(kAtomTag) };
    return tags;
}

- (void)awakeFromNib {
    NSDictionary *names = @{ kSublimeText3Identifier: @"Sublime Text 3",
                             kSublimeText2Identifier: @"Sublime Text 2",
                                   kMacVimIdentifier: @"MacVim",
                                 kTextmateIdentifier: @"Textmate",
                                kTextmate2Identifier: @"Textmate 2",
                                   kBBEditIdentifier: @"BBEdit",
                                     kAtomIdentifier: @"Atom" };

    NSDictionary *tags = [[self class] identifierToTagMap];

    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    [editors_ setAutoenablesItems:NO];
    for (NSString *identifier in [[self class] editorsInPreferenceOrder]) {
        NSMenuItem *item = items[names[identifier]];
        if (!item) {
            [editors_ addItemWithTitle:names[identifier]];
            item = (NSMenuItem *)[[[editors_ menu] itemArray] lastObject];
            int tag = [tags[identifier] integerValue];
            [item setTag:tag];
            [item setEnabled:NO];
            items[names[identifier]] = item;
        }
        if ([iTermSemanticHistoryPrefsController applicationExists:identifier]) {
            [item setEnabled:YES];
        }
    }

    [self actionChanged:nil];
}

+ (NSDictionary *)actionToTagMap {
    NSDictionary *tagToActionMap = [self tagToActionMap];
    NSArray *keys = [tagToActionMap allKeys];
    NSArray *values = [tagToActionMap allValues];
    return [NSDictionary dictionaryWithObjects:keys forKeys:values];
}

+ (NSDictionary *)tagToActionMap {
    return @{ @1: kSemanticHistoryBestEditorAction,
              @2: kSemanticHistoryUrlAction,
              @3: kSemanticHistoryEditorAction,
              @4: kSemanticHistoryCommandAction,
              @5: kSemanticHistoryRawCommandAction,
              @6: kSemanticHistoryCoprocessAction };
}

- (NSString *)actionIdentifier {
    // Maps a tag number to an action string.
    NSDictionary *actions = [[self class] tagToActionMap];
    NSInteger tag = [[action_ selectedItem] tag];
    return actions[@(tag)];
}

- (NSString *)editorIdentifier
{
    NSDictionary *map = @{ @(kSublimeText3Tag): kSublimeText3Identifier,
                           @(kSublimeText2Tag): kSublimeText2Identifier,
                                 @(kMacVimTag): kMacVimIdentifier,
                               @(kTextmateTag): kTextmateIdentifier,
                              @(kTextmate2Tag): kTextmate2Identifier,
                                 @(kBBEditTag): kBBEditIdentifier,
                                   @(kAtomTag): kAtomIdentifier };
    return map[@([[editors_ selectedItem] tag])];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [_delegate semanticHistoryPrefsControllerSettingChanged:self];
}

- (IBAction)actionChanged:(id)sender
{
    BOOL hideText = YES;
    BOOL hideEditors = YES;
    BOOL hideCaveat = caveat_.isHidden;
    switch ([[action_ selectedItem] tag]) {
        case 1:
            [caveat_ setStringValue:@"When you activate Semantic History on a filename, the associated app loads the file."];
            hideCaveat = NO;
            break;
            
        case 2:
            [[text_ cell] setPlaceholderString:@"Enter URL."];
            [caveat_ setStringValue:@"When you activate Semantic History on a filename, the browser opens a URL.\nUse \\1 for the filename you clicked on and \\2 for the line number."];
            hideCaveat = NO;
            hideText = NO;
            break;
            
        case 3:
            hideEditors = NO;
            [caveat_ setStringValue:@"When you activate Semantic History on a text file, the specified editor opens it.\nOther kinds of files will be opened with their default apps."];
            hideCaveat = NO;
            break;

        case 4:
            [[text_ cell] setPlaceholderString:@"Enter command"];
            [caveat_ setStringValue:@"Command runs when you activate Semantic History on any filename. Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd."];
            hideCaveat = NO;
            hideText = NO;
            break;

        case 5:
            [[text_ cell] setPlaceholderString:@"Enter command"];
            [caveat_ setStringValue:@"Command runs when you activate Semantic History on any text (even if it's not a valid filename). Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd."];
            hideCaveat = NO;
            hideText = NO;
            break;

        case 6:
            [[text_ cell] setPlaceholderString:@"Enter command"];
            [caveat_ setStringValue:@"Coprocess runs when you activate Semantic History on any filename. Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd."];
            hideCaveat = NO;
            hideText = NO;
            break;
    }
    if (caveat_.isHidden != hideCaveat) {
        [caveat_ setHidden:hideCaveat];
    }
    if (text_.isHidden != hideText) {
        [text_ setHidden:hideText];
    }
    if (editors_.isHidden != hideEditors) {
        [editors_ setHidden:hideEditors];
    }
    if (sender) {
        if (![text_ isHidden]) {
            NSString *stringValue = self.prefs[kSemanticHistoryTextKey];
            [text_ setStringValue:stringValue ? stringValue : @""];
        }
        [_delegate semanticHistoryPrefsControllerSettingChanged:self];
    }
}

- (NSDictionary *)prefs {
    return @{ kSemanticHistoryActionKey: [self actionIdentifier],
              kSemanticHistoryTextKey: [text_ stringValue],
              kSemanticHistoryEditorKey: [self editorIdentifier] };
}

- (void)setGuid:(NSString *)guid
{
    [guid_ autorelease];
    guid_ = [guid copy];
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    NSDictionary *prefs = bookmark[KEY_SEMANTIC_HISTORY];
    prefs = prefs ? prefs : [iTermSemanticHistoryPrefsController defaultPrefs];
    NSString *action = prefs[kSemanticHistoryActionKey];
    // Uncheck all items
    for (NSMenuItem *item in [[action_ menu] itemArray]) {
        [item setState:NSOffState];
    }
    // Set selection in menu
    NSDictionary *actionToTagMap = [[self class] actionToTagMap];
    NSNumber *tag = actionToTagMap[action];
    if (tag) {
        [action_ selectItemWithTag:[tag integerValue]];
    }

    // Check selected item
    [[[action_ menu] itemWithTag:[action_ selectedTag]] setState:NSOnState];
    [self actionChanged:nil];
    NSString *text = prefs[kSemanticHistoryTextKey];
    if (text) {
        [text_ setStringValue:text];
    } else {
        [text_ setStringValue:@""];
    }
    NSString *editor = [prefs objectForKey:kSemanticHistoryEditorKey];
    NSDictionary *map = [[self class] identifierToTagMap];
    NSNumber *tagNumber = map[editor];
    if (tagNumber) {
        [editors_ selectItemWithTag:[tagNumber integerValue]];
    }
}

- (void)setEnabled:(BOOL)enabled {
    action_.enabled = enabled;
    text_.enabled = enabled;
    editors_.enabled = enabled;
    caveat_.enabled = enabled;
}

@end
