//
//  TrouterPrefsController.m
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "TrouterPrefsController.h"
#import "ProfileModel.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"

NSString *kTrouterActionKey = @"action";
NSString *kTrouterEditorKey = @"editor";
NSString *kTrouterTextKey = @"text";

NSString *kSublimeText2Identifier = @"com.sublimetext.2";
NSString *kSublimeText3Identifier = @"com.sublimetext.3";
NSString *kMacVimIdentifier = @"org.vim.MacVim";
NSString *kTextmateIdentifier = @"com.macromates.textmate";
NSString *kTextmate2Identifier = @"com.macromates.textmate.preview";
NSString *kBBEditIdentifier = @"com.barebones.bbedit";
NSString *kAtomIdentifier = @"com.github.atom";
NSString *kTrouterBestEditorAction = @"best editor";
NSString *kTrouterUrlAction = @"url";
NSString *kTrouterEditorAction = @"editor";
NSString *kTrouterCommandAction = @"command";
NSString *kTrouterRawCommandAction = @"raw command";
NSString *kTrouterCoprocessAction = @"coprocess";

@implementation TrouterPrefsController

enum {
    kSublimeText2Tag = 1,
    kMacVimTag,
    kTextmateTag,
    kBBEditTag,
    kSublimeText3Tag,
    kAtomTag,
    // Only append to the end of the list; never delete or change.
};

@synthesize guid = guid_;

+ (NSDictionary *)defaultPrefs
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            kTrouterBestEditorAction, kTrouterActionKey,
            nil];
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
        if ([TrouterPrefsController applicationExists:identifier]) {
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
                                  kBBEditIdentifier,
                                  kAtomIdentifier ];
    return [editorBundleIds containsObject:bundleId];
}

+ (NSDictionary *)identifierToTagMap {
    NSDictionary *tags = @{ kSublimeText3Identifier: @(kSublimeText3Tag),
                            kSublimeText2Identifier: @(kSublimeText2Tag),
                                  kMacVimIdentifier: @(kMacVimTag),
                                kTextmateIdentifier: @(kTextmateTag),
                               kTextmate2Identifier: @(kTextmateTag),
                                  kBBEditIdentifier: @(kBBEditTag),
                                    kAtomIdentifier: @(kAtomTag) };
    return tags;
}

- (void)awakeFromNib {
    NSDictionary *names = @{ kSublimeText3Identifier: @"Sublime Text 3",
                             kSublimeText2Identifier: @"Sublime Text 2",
                                   kMacVimIdentifier: @"MacVim",
                                 kTextmateIdentifier: @"Textmate",
                                kTextmate2Identifier: @"Textmate",
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
        if ([TrouterPrefsController applicationExists:identifier]) {
            [item setEnabled:YES];
        }
    }

    [self actionChanged:nil];
}

- (NSString *)actionIdentifier {
    switch ([[action_ selectedItem] tag]) {
        case 1:
            return kTrouterBestEditorAction;
            
        case 2:
            return kTrouterUrlAction;
            break;
            
        case 3:
            return kTrouterEditorAction;
            break;
            
        case 4:
            return kTrouterCommandAction;
            break;

        case 5:
            return kTrouterRawCommandAction;
            break;

        case 6:
            return kTrouterCoprocessAction;
            break;
    }
    return nil;
}

- (NSString *)editorIdentifier
{
    NSDictionary *map = @{ @(kSublimeText3Tag): kSublimeText3Identifier,
                           @(kSublimeText2Tag): kSublimeText2Identifier,
                                 @(kMacVimTag): kMacVimIdentifier,
                               @(kTextmateTag): kTextmateIdentifier,
                                 @(kBBEditTag): kBBEditIdentifier,
                                   @(kAtomTag): kAtomIdentifier };
    return map[@([[editors_ selectedItem] tag])];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [_delegate trouterPrefsControllerSettingChanged:self];
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
            NSString *stringValue = [[self prefs] objectForKey:kTrouterTextKey];
            [text_ setStringValue:stringValue ? stringValue : @""];
        }
        [_delegate trouterPrefsControllerSettingChanged:self];
    }
}

- (NSDictionary *)prefs
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [self actionIdentifier], kTrouterActionKey,
            [text_ stringValue], kTrouterTextKey,
            [self editorIdentifier], kTrouterEditorKey,
            nil];
}

- (void)setGuid:(NSString *)guid
{
    [guid_ autorelease];
    guid_ = [guid copy];
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    NSDictionary *prefs = [bookmark objectForKey:KEY_TROUTER];
    prefs = prefs ? prefs : [TrouterPrefsController defaultPrefs];
    NSString *action = [prefs objectForKey:kTrouterActionKey];
    // Uncheck all items
    for (NSMenuItem *item in [[action_ menu] itemArray]) {
        [item setState:NSOffState];
    }
    // Set selection in menu
    if ([action isEqualToString:kTrouterBestEditorAction]) {
        [action_ selectItemWithTag:1];
    }
    if ([action isEqualToString:kTrouterUrlAction]) {
        [action_ selectItemWithTag:2];
    }
    if ([action isEqualToString:kTrouterEditorAction]) {
        [action_ selectItemWithTag:3];
    }
    if ([action isEqualToString:kTrouterCommandAction]) {
        [action_ selectItemWithTag:4];
    }
    if ([action isEqualToString:kTrouterRawCommandAction]) {
        [action_ selectItemWithTag:5];
    }
    if ([action isEqualToString:kTrouterCoprocessAction]) {
        [action_ selectItemWithTag:6];
    }
    // Check selected item
    [[[action_ menu] itemWithTag:[action_ selectedTag]] setState:NSOnState];
    [self actionChanged:nil];
    NSString *text = [prefs objectForKey:kTrouterTextKey];
    if (text) {
        [text_ setStringValue:text];
    } else {
        [text_ setStringValue:@""];
    }
    NSString *editor = [prefs objectForKey:kTrouterEditorKey];
    NSDictionary *map = [[self class] identifierToTagMap];
    NSNumber *tagNumber = map[editor];
    if (tagNumber) {
        [editors_ selectItemWithTag:[tagNumber integerValue]];
    }
}

@end
