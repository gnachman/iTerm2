//
//  iTermSemanticHistoryPrefsController.m
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "iTermSemanticHistoryPrefsController.h"
#import "ITAddressBookMgr.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextPopoverViewController.h"
#import "iTermVariableHistory.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"

NSString *kSemanticHistoryActionKey = @"action";
NSString *kSemanticHistoryEditorKey = @"editor";
NSString *kSemanticHistoryTextKey = @"text";

NSString *kSublimeText2Identifier = @"com.sublimetext.2";
NSString *kSublimeText3Identifier = @"com.sublimetext.3";
NSString *kSublimeText4Identifier = @"com.sublimetext.4";
NSString *kMacVimIdentifier = @"org.vim.MacVim";
NSString *kTextmateIdentifier = @"com.macromates.TextMate";
NSString *kTextmate2Identifier = @"com.macromates.TextMate.preview";
NSString *kBBEditIdentifier = @"com.barebones.bbedit";
NSString *kAtomIdentifier = @"com.github.atom";
NSString *kVSCodeIdentifier = @"com.microsoft.VSCode";
NSString *kVSCodiumIdentifier = @"com.visualstudio.code.oss";
NSString *kVSCodeInsidersIdentifier = @"com.microsoft.VSCodeInsiders";
NSString *kEmacsAppIdentifier = @"org.gnu.Emacs";
NSString *kIntelliJIDEAIdentifier = @"com.jetbrains.intellij.ce";

NSString *kSemanticHistoryBestEditorAction = @"best editor";
NSString *kSemanticHistoryUrlAction = @"url";
NSString *kSemanticHistoryEditorAction = @"editor";
NSString *kSemanticHistoryCommandAction = @"command";
NSString *kSemanticHistoryRawCommandAction = @"raw command";
NSString *kSemanticHistoryCoprocessAction = @"coprocess";

static NSString *const iTermSemanticHistoryPrefsControllerCaveatTextFieldDidClickOnLink = @"iTermSemanticHistoryPrefsControllerCaveatTextFieldDidClickOnLink";

@interface iTermSemanticHistoryPrefsControllerCaveatTextField : NSTextField
@end

@implementation iTermSemanticHistoryPrefsControllerCaveatTextField
- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSemanticHistoryPrefsControllerCaveatTextFieldDidClickOnLink
                                                        object:link];
    return YES;
}
@end

@interface iTermSemanticHistoryPrefsController()
@end

@implementation iTermSemanticHistoryPrefsController {
    NSString *guid_;
    IBOutlet NSPopUpButton *action_;
    IBOutlet NSTextField *text_;
    IBOutlet NSPopUpButton *editors_;
    IBOutlet NSTextField *caveat_;
    IBOutlet iTermFunctionCallTextFieldDelegate *_textFieldDelegate;

    iTermTextPopoverViewController *_popoverVC;
}

enum {
    kSublimeText2Tag = 1,
    kMacVimTag,
    kTextmateTag,
    kBBEditTag,
    kSublimeText3Tag,
    kSublimeText4Tag,
    kAtomTag,
    kTextmate2Tag,
    kVSCodeTag,
    kVSCodeInsidersTag,
    kEmacsAppTag,
    kVSCodiumTag,
    kIntelliJTag
    // Only append to the end of the list; never delete or change.
};

@synthesize guid = guid_;

+ (NSDictionary *)defaultPrefs {
    return @{ kSemanticHistoryActionKey: kSemanticHistoryBestEditorAction };
}

+ (BOOL)applicationExists:(NSString *)bundleId {
    CFArrayRef appURLs = LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef)bundleId, nil);
    NSInteger count = appURLs ? CFArrayGetCount(appURLs) : 0;
    if (appURLs) {
        CFRelease(appURLs);
    }

    if (count > 0) {
        if ([bundleId isEqualToString:kSublimeText2Identifier] ||
            [bundleId isEqualToString:kSublimeText3Identifier] ||
            [bundleId isEqualToString:kSublimeText4Identifier]) {
            // Extra check for sublime text.
            if (![[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId]) {
                return NO;
            } else {
                return YES;
            }
        } else {
            return YES;
        }
    } else {
        return NO;
    }
}

+ (NSString *)schemeForEditor:(NSString *)editor {
    NSDictionary *schemes = @{ kSublimeText2Identifier: @"subl",
                               kSublimeText3Identifier: @"subl",
                               kSublimeText4Identifier: @"subl",
                               kMacVimIdentifier: @"mvim",
                               kTextmateIdentifier: @"txmt",
                               kTextmate2Identifier: @"txmt",
                               kBBEditIdentifier: @"txmt",
                               kAtomIdentifier: @"atom",
                               kVSCodeIdentifier: @"vscode",
                               kVSCodiumIdentifier: @"vscodium",
                               kVSCodeInsidersIdentifier: @"vscode",
                               kEmacsAppIdentifier: @"",
                               kIntelliJIDEAIdentifier: @"" };
    return schemes[editor];
}

+ (NSArray *)editorsInPreferenceOrder {
    // Editors from most to least preferred.
    return @[ kSublimeText4Identifier,
              kSublimeText3Identifier,
              kSublimeText2Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier,
              kAtomIdentifier,
              kVSCodeIdentifier,
              kVSCodiumIdentifier,
              kVSCodeInsidersIdentifier,
              kEmacsAppIdentifier,
              kIntelliJIDEAIdentifier ];
}

+ (NSString *)bestEditor {
    for (NSString *identifier in [self editorsInPreferenceOrder]) {
        if ([iTermSemanticHistoryPrefsController applicationExists:identifier]) {
            return identifier;
        }
    }
    return nil;
}

+ (BOOL)bundleIdIsEditor:(NSString *)bundleId {
    NSArray *editorBundleIds = @[ kSublimeText2Identifier,
                                  kSublimeText3Identifier,
                                  kSublimeText4Identifier,
                                  kMacVimIdentifier,
                                  kTextmateIdentifier,
                                  kTextmate2Identifier,
                                  kBBEditIdentifier,
                                  kAtomIdentifier,
                                  kVSCodeIdentifier,
                                  kVSCodiumIdentifier,
                                  kVSCodeInsidersIdentifier,
                                  kEmacsAppIdentifier,
                                  kIntelliJIDEAIdentifier ];
    return [editorBundleIds containsObject:bundleId];
}

+ (NSDictionary *)identifierToTagMap {
    NSDictionary *tags = @{ kSublimeText4Identifier: @(kSublimeText4Tag),
                            kSublimeText3Identifier: @(kSublimeText3Tag),
                            kSublimeText2Identifier: @(kSublimeText2Tag),
                                  kMacVimIdentifier: @(kMacVimTag),
                                kTextmateIdentifier: @(kTextmateTag),
                               kTextmate2Identifier: @(kTextmate2Tag),
                                  kBBEditIdentifier: @(kBBEditTag),
                                    kAtomIdentifier: @(kAtomTag),
                                  kVSCodeIdentifier: @(kVSCodeTag),
                                kVSCodiumIdentifier: @(kVSCodiumTag),
                          kVSCodeInsidersIdentifier: @(kVSCodeInsidersTag),
                                kEmacsAppIdentifier: @(kEmacsAppTag),
                            kIntelliJIDEAIdentifier: @(kIntelliJTag) };
    return tags;
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showPopover)
                                                 name:iTermSemanticHistoryPrefsControllerCaveatTextFieldDidClickOnLink
                                               object:nil];
    NSSet<NSString *>* (^fallbackSource)(NSString *) = [iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession];
    NSArray *mine = @[kSemanticHistoryPathSubstitutionKey,
                      kSemanticHistoryPrefixSubstitutionKey,
                      kSemanticHistorySuffixSubstitutionKey,
                      kSemanticHistoryWorkingDirectorySubstitutionKey,
                      kSemanticHistoryLineNumberKey,
                      kSemanticHistoryColumnNumberKey];
    _textFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:^NSSet<NSString *> *(NSString *prefix) {
        NSArray *filtered = [mine filteredArrayUsingBlock:^BOOL(NSString *path) {
            return [path it_hasPrefix:prefix];
        }];
        NSMutableSet *result = [NSMutableSet setWithArray:filtered];
        [result unionSet:fallbackSource(prefix)];
        return result;
    }
                                                                            passthrough:self
                                                                          functionsOnly:NO];
    text_.delegate = _textFieldDelegate;

    NSDictionary *names = @{ kSublimeText4Identifier: @"Sublime Text 4",
                             kSublimeText3Identifier: @"Sublime Text 3",
                             kSublimeText2Identifier: @"Sublime Text 2",
                                   kMacVimIdentifier: @"MacVim",
                                 kTextmateIdentifier: @"Textmate",
                                kTextmate2Identifier: @"Textmate Preview",
                                   kBBEditIdentifier: @"BBEdit",
                                     kAtomIdentifier: @"Atom",
                                   kVSCodeIdentifier: @"VS Code",
                                 kVSCodiumIdentifier: @"VS Codium",
                           kVSCodeInsidersIdentifier: @"VS Code Insiders",
                                 kEmacsAppIdentifier: @"Emacs.app",
                             kIntelliJIDEAIdentifier: @"IntelliJ IDEA" };

    NSDictionary *tags = [[self class] identifierToTagMap];

    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    [editors_ setAutoenablesItems:NO];
    for (NSString *identifier in [[self class] editorsInPreferenceOrder]) {
        NSMenuItem *item = items[names[identifier]];
        if (!item) {
            item = [[NSMenuItem alloc] initWithTitle:names[identifier] action:nil keyEquivalent:@""];
            int tag = [tags[identifier] integerValue];
            [item setTag:tag];
            [item setEnabled:NO];
            items[names[identifier]] = item;
        }
        if ([iTermSemanticHistoryPrefsController applicationExists:identifier]) {
            [item setEnabled:YES];
        }
    }
    NSArray *sortedNames = [items.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in sortedNames) {
        NSMenuItem *item = items[name];
        [editors_.menu addItem:item];
    }

    // Necessary to make links work
    caveat_.allowsEditingTextAttributes = YES;

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
    NSDictionary *map = @{ @(kSublimeText4Tag): kSublimeText4Identifier,
                           @(kSublimeText3Tag): kSublimeText3Identifier,
                           @(kSublimeText2Tag): kSublimeText2Identifier,
                                 @(kMacVimTag): kMacVimIdentifier,
                               @(kTextmateTag): kTextmateIdentifier,
                              @(kTextmate2Tag): kTextmate2Identifier,
                                 @(kBBEditTag): kBBEditIdentifier,
                                   @(kAtomTag): kAtomIdentifier,
                                 @(kVSCodeTag): kVSCodeIdentifier,
                               @(kVSCodiumTag): kVSCodiumIdentifier,
                         @(kVSCodeInsidersTag): kVSCodeInsidersIdentifier,
                               @(kEmacsAppTag): kEmacsAppIdentifier,
                           @(kIntelliJTag): kIntelliJIDEAIdentifier };
    return map[@([[editors_ selectedItem] tag])];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    [_delegate semanticHistoryPrefsControllerSettingChanged:self];
}

- (NSAttributedString *)attributedStringWithLearnMoreLinkAfterText:(NSString *)text {
    NSDictionary *attributes = @{ NSFontAttributeName: caveat_.font ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] };
    NSAttributedString *legacy = [NSAttributedString attributedStringWithString:text
                                                                     attributes:attributes];
    NSAttributedString *learnMore = [NSAttributedString attributedStringWithLinkToURL:@"iterm2-private://semantic-history-learn-more/" string:@"Learn more"];
    NSArray<NSAttributedString *> *parts = @[ legacy, learnMore ];
    return [NSAttributedString attributedStringWithAttributedStrings:parts];
}

- (NSString *)detailTextForCurrentMode {
    NSString *subs =
    @"You can provide substitutions as follows:\n"
    @"  \\1 will be replaced with the filename.\n"
    @"  \\2 will be replaced with the line number.\n"
    @"  \\3 will be replaced with the text before the click.\n"
    @"  \\4 will be replaced with the text after the click.\n"
    @"  \\5 will be replaced with the working directory.\n"
    @"\n"
    @"This is also an interpolated string evaluated in the context of the current session. In addition to the usual variables, the following substitutions are available:\n"
    @"  \\(semanticHistory.path) will be replaced with the filename.\n"
    @"  \\(semanticHistory.lineNumber) will be replaced with the line number.\n"
    @"  \\(semanticHistory.columnNumber) will be replaced with the column number.\n"
    @"  \\(semanticHistory.prefix) will be replaced with the text before the click.\n"
    @"  \\(semanticHistory.suffix) will be replaced with the text after the click.\n"
    @"  \\(semanticHistory.workingDirectory) will be replaced with the working directory.\n";

    switch ([[action_ selectedItem] tag]) {
        case 1:
        case 3:
            break;

        case 5:
            return [@"In this mode semantic history will be activated on any click, even if you click on something that is not an existing file.\n"
                    stringByAppendingString:subs];

        case 2:
        case 4:
        case 6:
            return [@"In this mode semantic history will only be activated when you click on an existing file name.\n"
                    stringByAppendingString:subs];
    }
    return @"";
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

        case 2: {
            [[text_ cell] setPlaceholderString:@"Enter URL."];
            NSString *text =
            @"When you activate Semantic History on a filename, the browser opens a URL.\n"
            @"Use \\1 for the filename you clicked on and \\2 for the line number. ";
            caveat_.attributedStringValue = [self attributedStringWithLearnMoreLinkAfterText:text];
            hideCaveat = NO;
            hideText = NO;
            break;
        }

        case 3:
            hideEditors = NO;
            [caveat_ setStringValue:@"When you activate Semantic History on a text file, the specified editor opens it.\nOther kinds of files will be opened with their default apps."];
            hideCaveat = NO;
            break;

        case 4: {
            [[text_ cell] setPlaceholderString:@"Enter command"];
            NSString *text =
            @"Command runs when you activate Semantic History on any filename. "
            @"Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd. "
            @"You can also use interpolated string syntax. ";

            caveat_.attributedStringValue = [self attributedStringWithLearnMoreLinkAfterText:text];
            hideCaveat = NO;
            hideText = NO;
            break;
        }

        case 5: {
            [[text_ cell] setPlaceholderString:@"Enter command"];

            NSString *text =
            @"Command runs when you activate Semantic History on any text, even if it's not a valid filename. "
            @"Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd. ";

            caveat_.attributedStringValue = [self attributedStringWithLearnMoreLinkAfterText:text];
            hideCaveat = NO;
            hideText = NO;
            break;
        }

        case 6: {
            [[text_ cell] setPlaceholderString:@"Enter command"];
            NSString *text =
            @"Coprocess runs when you activate Semantic History on any filename. "
            @"Use \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd. ";
            caveat_.attributedStringValue = [self attributedStringWithLearnMoreLinkAfterText:text];
            hideCaveat = NO;
            hideText = NO;
            break;
        }
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
        [item setState:NSControlStateValueOff];
    }
    // Set selection in menu
    NSDictionary *actionToTagMap = [[self class] actionToTagMap];
    NSNumber *tag = actionToTagMap[action];
    if (tag) {
        [action_ selectItemWithTag:[tag integerValue]];
    }

    // Check selected item
    [[[action_ menu] itemWithTag:[action_ selectedTag]] setState:NSControlStateValueOn];
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

- (void)showPopover {
    if (!text_.window) {
        return;
    }
    [_popoverVC.popover close];
    _popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [_popoverVC view];
    _popoverVC.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _popoverVC.textView.drawsBackground = NO;
    [_popoverVC appendString:[self detailTextForCurrentMode]];
    NSRect frame = _popoverVC.view.frame;
    frame.size.width = 550;
    _popoverVC.view.frame = frame;
    [_popoverVC.popover showRelativeToRect:text_.bounds
                                    ofView:text_
                             preferredEdge:NSRectEdgeMaxY];
}

@end
