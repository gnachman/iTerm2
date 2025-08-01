//
//  iTermPasteSpecialWindowController.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "iTermPasteSpecialWindowController.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermPasteHelper.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PasteboardHistory.h"
#import "RegexKitLite.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface iTermFileReference : NSObject
@property(nonatomic, readonly) NSData *data;
- (instancetype)initWithName:(NSString *)url;
- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak;
@end

@implementation iTermFileReference {
    NSString *_name;
}

- (instancetype)initWithName:(NSString *)url {
    self = [super init];
    if (self) {
        _name = [url copy];
    }
    return self;
}

- (NSData *)data {
    return [NSData dataWithContentsOfFile:_name];
}

- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak {
    return [self.data stringWithBase64EncodingWithLineBreak:lineBreak];
}

@end

@interface iTermPasteSpecialWindowController () <iTermPasteSpecialViewControllerDelegate>

@property(nonatomic, assign) BOOL shouldPaste;
@property(nonatomic, assign) NSInteger chunkSize;
@property(nonatomic, assign) NSTimeInterval delayBetweenChunks;

@end

@implementation iTermPasteSpecialWindowController {
    // Pre-processed string
    NSString *_rawString;

    // Terminal app expects bracketed data?
    BOOL _bracketingEnabled;

    // Wait for prompt allowed?
    BOOL _canWaitForPrompt;

    // Is currently at shell prompt? Sets wait-for-prompt default value.
    BOOL _isAtShellPrompt;

    BOOL _forceEscapeSymbols;

    // String to paste before transforms.
    NSArray *_originalValues;
    NSArray *_labels;

    NSInteger _index;

    // Encoding to use.
    NSStringEncoding _encoding;

    // Outlets
    IBOutlet NSTextField *_statsLabel;
    IBOutlet NSPopUpButton *_itemList;
    IBOutlet NSTextView *_preview;
    IBOutlet NSTextField *_estimatedDuration;
    IBOutlet NSView *_terminalModeEnclosure;
    NSView *_pasteSpecialViewContainer;
    iTermPasteSpecialViewController *_pasteSpecialViewController;
    NSString *_shell;

    // Object to paste not representable as a string and is pre-base64 encoded.
    BOOL _base64only;
    ProfileType _profileType;
}

- (instancetype)initWithChunkSize:(NSInteger)chunkSize
               delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
                bracketingEnabled:(BOOL)bracketingEnabled
                 canWaitForPrompt:(BOOL)canWaitForPrompt
                  isAtShellPrompt:(BOOL)isAtShellPrompt
               forceEscapeSymbols:(BOOL)forceEscapeSymbols
                            shell:(NSString *)shell
                   encoding:(NSStringEncoding)encoding
                      profileType:(ProfileType)profileType {
    self = [super initWithWindowNibName:@"iTermPasteSpecialWindow"];
    if (self) {
        _shell = [shell lastPathComponent];
        _index = -1;
        _bracketingEnabled = bracketingEnabled;
        _canWaitForPrompt = canWaitForPrompt;
        _isAtShellPrompt = isAtShellPrompt;
        _forceEscapeSymbols = forceEscapeSymbols;
        _profileType = profileType;
        NSMutableArray *values = [NSMutableArray array];
        NSMutableArray *labels = [NSMutableArray array];

        if ([iTermAdvancedSettingsModel includePasteHistoryInAdvancedPaste]) {
            NSArray<PasteboardEntry *> *historyEntries = [[PasteboardHistory sharedInstance] entries];
            if (historyEntries.count > 1) {
                for (PasteboardEntry *entry in historyEntries) {
                    if (values.count && [values.lastObject isEqual:entry.mainValue]) {
                        // Remove consecutive duplicates, which happen if you copy and then paste.
                        continue;
                    }
                    if (entry == historyEntries.lastObject) {
                        NSString *pasteboardString = [NSString stringFromPasteboard];
                        if (pasteboardString && entry.mainValue && [pasteboardString isEqualToString:entry.mainValue]) {
                            // Include the last entry only if it differs from the current pasteboard contents.
                            continue;
                        }
                    }
                    NSString *title = entry.mainValue;
                    static const NSUInteger kMaxLength = 50;
                    if (title.length > kMaxLength) {
                        title = [[title substringToIndex:kMaxLength] stringByAppendingString:@"…"];
                    }
                    [labels addObject:[NSString stringWithFormat:@"Text: “%@”", title]];
                    [values addObject:entry.mainValue];
                }
                [labels addObject:[NSNull null]];
                [values addObject:@""];
           }
        }

        [self getLabels:labels andValues:values];
        _labels = labels;
        _originalValues = values;
        _encoding = encoding;
        self.chunkSize = chunkSize;
        self.delayBetweenChunks = delayBetweenChunks;
        _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
        _pasteSpecialViewController.delegate = self;
    }
    return self;
}

- (void)awakeFromNib {
    const CGFloat heightBefore = _pasteSpecialViewController.view.frame.size.height;
    _pasteSpecialViewController.profileType = _profileType;
    const CGFloat heightAfter = _pasteSpecialViewController.view.frame.size.height;
    if (_profileType != ProfileTypeTerminal) {
        _terminalModeEnclosure.hidden = YES;
    }
    const CGFloat shrinkage = heightBefore - heightAfter;

    NSRect frame = _statsLabel.frame;
    frame.origin.y -= shrinkage;

    frame = _preview.enclosingScrollView.frame;
    frame.origin.y -= shrinkage;
    frame.size.height += shrinkage;
    _preview.enclosingScrollView.frame = frame;


    _preview.backgroundColor = [NSColor textBackgroundColor];
    _preview.textColor = [NSColor textColor];
    _preview.automaticSpellingCorrectionEnabled = NO;
    _preview.automaticDashSubstitutionEnabled = NO;
    _preview.automaticQuoteSubstitutionEnabled = NO;
    _preview.automaticDataDetectionEnabled = NO;
    _preview.automaticLinkDetectionEnabled = NO;
    _preview.smartInsertDeleteEnabled = NO;
    _preview.richText = NO;
    _preview.font = [NSFont fontWithName:@"Menlo" size:[NSFont systemFontSize]];

    __block NSUInteger indexToSelect = 0;
    if ([iTermAdvancedSettingsModel includePasteHistoryInAdvancedPaste]) {
        [_labels enumerateObjectsUsingBlock:^(id  _Nonnull label, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([label isKindOfClass:[NSNull class]]) {
                indexToSelect = idx + 1;
                [_itemList.menu addItem:[NSMenuItem separatorItem]];
            } else {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:label
                                                              action:nil
                                                       keyEquivalent:@""];
                [_itemList.menu addItem:item];
            }
        }];
    } else {
        for (NSString *label in _labels) {
            [_itemList addItemWithTitle:label];
        }
    }

    [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;

    if ([iTermAdvancedSettingsModel includePasteHistoryInAdvancedPaste]) {
        [_itemList selectItemAtIndex:indexToSelect];
        [self selectValueAtIndex:indexToSelect];
    } else {
        [self selectValueAtIndex:0];
    }
}

- (void)getLabels:(NSMutableArray *)labels andValues:(NSMutableArray *)values {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
        NSString *string = [item stringForType:UTTypeUTF8PlainText.identifier];
        if (string && ![item stringForType:UTTypeFileURL.identifier]) {
            // Is a non-file URL string. File URLs get special handling.
            [values addObject:string];
            NSString *description = NULL;
            for (NSString *theType in item.types) {
                description = [UTType typeWithIdentifier:theType].localizedDescription;
                if (description) {
                    break;
                }
            }
            NSString *label = [NSString stringWithFormat:@"%@: “%@”",
                               [(description ?: @"Unknown Type") stringByCapitalizingFirstLetter],
                               [string ellipsizedDescriptionNoLongerThan:100]];
            [labels addObject:label];
        }
        if (!string) {
            NSString *theType = UTTypeData.identifier;
            NSString *description = NULL;
            NSData *data = [item dataForType:theType];
            if (!data) {
                for (NSString *typeName in item.types) {
                    if ([typeName hasPrefix:@"public."] &&
                        ![typeName isEqualTo:UTTypeFileURL.identifier]) {
                        data = [item dataForType:typeName];
                        description = [UTType typeWithIdentifier:typeName].localizedDescription;
                        break;
                    }
                }
            }
            if (data && description) {
                [values addObject:data];
                [labels addObject:description];
            }
        }
    }

    // Now handle file references.
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ] options:0];
    NSArray<NSString *> *filenames = [urls mapWithBlock:^id(NSURL *anObject) {
        return anObject.path;
    }];
    // Join the filenames to add an item for the names themselves.
    NSMutableArray *modifiedFilenames = [NSMutableArray array];
    if (filenames.count == 1) {
        [modifiedFilenames addObject:filenames[0]];
    } else {
        for (NSString *filename in filenames) {
            [modifiedFilenames addObject:[NSString stringWithFormat:@"\"%@\"", filename]];
        }
    }

    [values addObject:[modifiedFilenames componentsJoinedByString:@" "]];
    if (filenames.count > 1) {
        [labels addObject:@"Multiple file names"];
    } else if (filenames.count == 1) {
        [labels addObject:@"File name"];
    }

    // Add an item for each existing non-directory file.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *filename in filenames) {
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:filename isDirectory:&isDirectory] &&
            !isDirectory) {
            [values addObject:[[iTermFileReference alloc] initWithName:filename]];
            [labels addObject:[NSString stringWithFormat:@"Contents of %@", filename]];
        }
    }
}

- (void)selectValueAtIndex:(NSInteger)index {
    if (index == _index) {
        return;
    }
    NSObject *value = _originalValues[index];
    NSString *string;
    BOOL isData = ![value isKindOfClass:[NSString class]];
    _base64only = NO;
    if (isData) {
        NSData *data;
        if ([value isKindOfClass:[NSData class]]) {
            data = (NSData *)value;
        } else {
            data = [(id)value data];
        }

        // If the data happens to be valid UTF-8 data then don't insist on base64 encoding it.
        string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!string) {
            _base64only = YES;
            string = [data stringWithBase64EncodingWithLineBreak:@"\r"];
        }
    } else {
        string = (NSString *)value;
    }
    _index = index;
    _rawString = [string copy];
    _preview.string = _rawString;
    BOOL containsTabs = [string containsString:@"\t"];
    NSInteger tabTransformTag = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialTabTransform];
    NSCharacterSet *theSet =
            [NSCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    BOOL containsShellCharacters =
        [string rangeOfCharacterFromSet:theSet].location != NSNotFound;
    BOOL containsDosNewlines = [string containsString:@"\n"];
    BOOL containsNewlines = containsDosNewlines || [string containsString:@"\r"];
    BOOL containsUnicodePunctuation = ([string rangeOfRegex:kPasteSpecialViewControllerUnicodePunctuationRegularExpression].location != NSNotFound);
    BOOL convertValue = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialConvertDosNewlines];
    BOOL shouldEscape = _forceEscapeSymbols || [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash];
    BOOL convertUnicodePunctuation = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialConvertUnicodePunctuation];
    NSMutableCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];
    NSRange unsafeRange = [string rangeOfCharacterFromSet:unsafeSet];
    BOOL containsControlCodes = unsafeRange.location != NSNotFound;
    BOOL removeValue = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialRemoveControlCodes];
    BOOL shouldBracket =
        [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialBracketedPasteMode];

    _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    _pasteSpecialViewController.enableTabTransforms = containsTabs;
    _pasteSpecialViewController.selectedTabTransform = tabTransformTag;
    _pasteSpecialViewController.enableConvertNewlines = containsDosNewlines;
    _pasteSpecialViewController.shouldConvertNewlines = (containsDosNewlines && convertValue);
    _pasteSpecialViewController.enableRemoveNewlines = containsNewlines;
    _pasteSpecialViewController.shouldRemoveNewlines = NO;
    _pasteSpecialViewController.enableConvertUnicodePunctuation = containsUnicodePunctuation;
    _pasteSpecialViewController.shouldConvertUnicodePunctuation =
        (containsUnicodePunctuation && convertUnicodePunctuation);
    _pasteSpecialViewController.enableEscapeShellCharsWithBackslash = containsShellCharacters;
    _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = (containsShellCharacters && shouldEscape);
    _pasteSpecialViewController.delayBetweenChunks = _delayBetweenChunks;
    _pasteSpecialViewController.chunkSize = _chunkSize;
    _pasteSpecialViewController.enableRemoveControlCodes = containsControlCodes;
    _pasteSpecialViewController.shouldRemoveControlCodes = (containsControlCodes && removeValue);
    _pasteSpecialViewController.enableBracketedPaste = _bracketingEnabled;
    _pasteSpecialViewController.shouldUseBracketedPasteMode = (_bracketingEnabled && shouldBracket);
    _pasteSpecialViewController.enableBase64 = !_base64only;
    _pasteSpecialViewController.shouldBase64Encode = _base64only;
    _pasteSpecialViewController.enableUseRegexSubstitution = !_base64only;  // Binary data can't be regexed
    _pasteSpecialViewController.shouldUseRegexSubstitution = !_base64only && [iTermPreferences boolForKey:kPreferencesKeyPasteSpecialUseRegexSubstitution];
    _pasteSpecialViewController.regexString = [iTermPreferences stringForKey:kPreferencesKeyPasteSpecialRegex];
    _pasteSpecialViewController.substitutionString = [iTermPreferences stringForKey:kPreferencesKeyPasteSpecialSubstitution];
    _pasteSpecialViewController.enableWaitForPrompt = _canWaitForPrompt;
    _pasteSpecialViewController.shouldWaitForPrompt = _isAtShellPrompt && _canWaitForPrompt && [iTermAdvancedSettingsModel advancedPasteWaitsForPromptByDefault] && [self waitForPromptShouldWork];

    [self updatePreview];
}

// When paste bracketing is on, some shells swallow newlines    .
- (BOOL)waitForPromptShouldWork {
    if (!_pasteSpecialViewController.shouldUseBracketedPasteMode) {
        return YES;
    }
    NSSet<NSString *> *shellsThatSwallowNewlines = [NSSet setWithArray:@[ @"zsh", @"fish", @"bash" ]];
    return ![shellsThatSwallowNewlines containsObject:_shell ?: @""];
}

- (void)updatePreview {
    PasteEvent *pasteEvent = [self pasteEventWithString:_rawString forPreview:YES];
    [iTermPasteHelper sanitizePasteEvent:pasteEvent encoding:_encoding];
    _preview.string = pasteEvent.string;
    NSNumberFormatter *bytesFormatter = [[NSNumberFormatter alloc] init];
    int numBytes = _preview.string.length;
    if (numBytes < 10) {
        bytesFormatter.numberStyle = NSNumberFormatterSpellOutStyle;
    } else {
        bytesFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    }

    NSNumberFormatter *linesFormatter = [[NSNumberFormatter alloc] init];
    NSUInteger numberOfLines = _preview.string.numberOfLines;
    if (numberOfLines < 10) {
        linesFormatter.numberStyle = NSNumberFormatterSpellOutStyle;
    } else {
        linesFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    }

    _statsLabel.stringValue = [NSString stringWithFormat:@"%@ byte%@ in %@ line%@.",
                               [[bytesFormatter stringFromNumber:@(numBytes)] stringWithFirstLetterCapitalized],
                               numBytes == 1 ? @"" : @"s",
                               [linesFormatter stringFromNumber:@(numberOfLines)],
                               numberOfLines == 1 ? @"" : @"s"];
    [self updateDuration];
}

- (void)updateDuration {
    int numChunks = (_preview.string.length / [self chunkSize]);
    NSTimeInterval duration = MAX(0, numChunks - 1) * [self delayBetweenChunks];
    // This is very high (pasting locally can be quite fast), and it just here to prevent
    // absurdly low time estimates.
    static const double kAssumedBandwidthInBytesPerSecond = 2000000;
    duration += _preview.string.length / kAssumedBandwidthInBytesPerSecond;
    if (duration > 1) {
        duration = ceil(duration);
    }
    if (duration < 0.01) {
        _estimatedDuration.stringValue = @"Instant";
    } else {
        _estimatedDuration.stringValue = [_pasteSpecialViewController descriptionForDuration:duration];
    }
}

+ (void)showAsPanelInWindow:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                   encoding:(NSStringEncoding)encoding
           canWaitForPrompt:(BOOL)canWaitForPrompt
            isAtShellPrompt:(BOOL)isAtShellPrompt
         forceEscapeSymbols:(BOOL)forceEscapeSymbols
                      shell:(NSString *)shell
                profileType:(ProfileType)profileType
                 completion:(iTermPasteSpecialCompletionBlock)completion {
    iTermPasteSpecialWindowController *controller =
        [[iTermPasteSpecialWindowController alloc] initWithChunkSize:chunkSize
                                                  delayBetweenChunks:delayBetweenChunks
                                                   bracketingEnabled:bracketingEnabled
                                                    canWaitForPrompt:canWaitForPrompt
                                                     isAtShellPrompt:isAtShellPrompt
                                                  forceEscapeSymbols:forceEscapeSymbols
                                                               shell:shell
                                                            encoding:encoding
                                                         profileType:profileType];
    NSWindow *window = [controller window];
    [presentingWindow beginSheet:window completionHandler:^(NSModalResponse returnCode) {
        [NSApp stopModal];
    }];

    [NSApp runModalForWindow:window];
    [presentingWindow endSheet:window];
    [window orderOut:nil];
    [controller.window close];

    if (controller.shouldPaste) {
        completion(controller.pasteEvent);
        [controller saveUserDefaults];
    }
}

#pragma mark - Private

- (void)saveUserDefaults {
    if (_pasteSpecialViewController.areTabTransformsEnabled) {
        [iTermPreferences setInt:_pasteSpecialViewController.selectedTabTransform
                          forKey:kPreferenceKeyPasteSpecialTabTransform];
    }
    if (_pasteSpecialViewController.selectedTabTransform == kTabTransformConvertToSpaces) {
        [iTermPreferences setInt:_pasteSpecialViewController.numberOfSpacesPerTab
                          forKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    }
    if (_pasteSpecialViewController.isEscapeShellCharsWithBackslashEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldEscapeShellCharsWithBackslash
                       forKey:kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash];
    }
    if (_pasteSpecialViewController.isConvertNewlinesEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldConvertNewlines
                           forKey:kPreferenceKeyPasteSpecialConvertDosNewlines];
    }
    if (_pasteSpecialViewController.isBracketedPasteEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldUseBracketedPasteMode
                           forKey:kPreferenceKeyPasteSpecialBracketedPasteMode];
    }
    if (_pasteSpecialViewController.isRemoveControlCodesEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldRemoveControlCodes
                           forKey:kPreferenceKeyPasteSpecialRemoveControlCodes];
    }
    if (_pasteSpecialViewController.isConvertUnicodePunctuationEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldConvertUnicodePunctuation
                           forKey:kPreferenceKeyPasteSpecialConvertUnicodePunctuation];
    }
    if (_pasteSpecialViewController.isUseRegexSubstitutionEnabled) {
        [iTermPreferences setBool:_pasteSpecialViewController.shouldUseRegexSubstitution
                           forKey:kPreferencesKeyPasteSpecialUseRegexSubstitution];
        [iTermPreferences setString:_pasteSpecialViewController.regexString
                             forKey:kPreferencesKeyPasteSpecialRegex];
        [iTermPreferences setString:_pasteSpecialViewController.substitutionString
                             forKey:kPreferencesKeyPasteSpecialSubstitution];
    }
}

- (PasteEvent *)pasteEvent {
    return [self pasteEventWithString:_preview.textStorage.string forPreview:NO];
}

- (PasteEvent *)pasteEventWithString:(NSString *)string forPreview:(BOOL)forPreview {
    iTermPasteFlags flags = _pasteSpecialViewController.flags;
    if (_base64only) {
        // We already base64 encoded the data, so don't set the flag or else it gets double encoded.
        flags &= ~kPasteFlagsBase64Encode;
    }

    iTermTabTransformTags tabTransform = _pasteSpecialViewController.selectedTabTransform;
    if (forPreview) {
        // Generating the preview. Keep tabs so that changing tab options works.
        tabTransform = kTabTransformNone;
    } else {
        // Generating live data. The preview has already applied these operations.
        // Other operations are idempotent.
        flags &= ~kPasteFlagsEscapeSpecialCharacters;
        flags &= ~kPasteFlagsBase64Encode;
        flags &= ~kPasteFlagsUseRegexSubstitution;
    }
    return [PasteEvent pasteEventWithString:string
                                      flags:flags
                           defaultChunkSize:self.chunkSize
                                   chunkKey:nil
                               defaultDelay:self.delayBetweenChunks
                                   delayKey:nil
                               tabTransform:tabTransform
                               spacesPerTab:_pasteSpecialViewController.numberOfSpacesPerTab
                                      regex:_pasteSpecialViewController.regexString
                               substitution:_pasteSpecialViewController.substitutionString];
}

#pragma mark - Actions

- (IBAction)ok:(id)sender {
    _shouldPaste = YES;
    NSString *string = [[self pasteEvent] string];
    if (string.length > 0) {
        [[PasteboardHistory sharedInstance] save:string];
    }
    [NSApp stopModal];
}

- (IBAction)cancel:(id)sender {
    _shouldPaste = NO;
    [NSApp stopModal];
}

- (IBAction)selectItem:(id)sender {
    [self selectValueAtIndex:[sender indexOfSelectedItem]];
}

#pragma mark - iTermPasteSpecialViewControllerDelegate

- (void)pasteSpecialViewSpeedDidChange {
    _delayBetweenChunks = _pasteSpecialViewController.delayBetweenChunks;
    _chunkSize = _pasteSpecialViewController.chunkSize;
    [self updateDuration];
}

- (void)pasteSpecialTransformDidChange {
    [self updatePreview];
}

@end
