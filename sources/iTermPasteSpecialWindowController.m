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
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PasteboardHistory.h"
#import "RegexKitLite.h"

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

- (void)dealloc {
    [_name release];
    [super dealloc];
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
    IBOutlet NSView *_pasteSpecialViewContainer;

    iTermPasteSpecialViewController *_pasteSpecialViewController;

    // Object to paste not representable as a string and is pre-base64 encoded.
    BOOL _base64only;
}

- (instancetype)initWithChunkSize:(NSInteger)chunkSize
               delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
                bracketingEnabled:(BOOL)bracketingEnabled
                 canWaitForPrompt:(BOOL)canWaitForPrompt
                  isAtShellPrompt:(BOOL)isAtShellPrompt
                   encoding:(NSStringEncoding)encoding {
    self = [super initWithWindowNibName:@"iTermPasteSpecialWindow"];
    if (self) {
        _index = -1;
        _bracketingEnabled = bracketingEnabled;
        _canWaitForPrompt = canWaitForPrompt;
        _isAtShellPrompt = isAtShellPrompt;
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
                        // This is better handled by examining the pasteboard.
                        continue;
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
        _labels = [labels retain];
        _originalValues = [values retain];
        _encoding = encoding;
        self.chunkSize = chunkSize;
        self.delayBetweenChunks = delayBetweenChunks;
        _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
        _pasteSpecialViewController.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_originalValues release];
    [_labels release];
    [_rawString release];
    [_pasteSpecialViewController release];
    [super dealloc];
}

- (void)awakeFromNib {
    _preview.automaticSpellingCorrectionEnabled = NO;
    _preview.automaticDashSubstitutionEnabled = NO;
    _preview.automaticQuoteSubstitutionEnabled = NO;
    _preview.automaticDataDetectionEnabled = NO;
    _preview.automaticLinkDetectionEnabled = NO;
    _preview.smartInsertDeleteEnabled = NO;

    __block NSUInteger indexToSelect = 0;
    if ([iTermAdvancedSettingsModel includePasteHistoryInAdvancedPaste]) {
        [_labels enumerateObjectsUsingBlock:^(id  _Nonnull label, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([label isKindOfClass:[NSNull class]]) {
                indexToSelect = idx + 1;
                [_itemList.menu addItem:[NSMenuItem separatorItem]];
            } else {
                NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:label
                                                               action:nil
                                                        keyEquivalent:@""] autorelease];
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
        NSString *string = [item stringForType:(NSString *)kUTTypeUTF8PlainText];
        if (string && ![item stringForType:(NSString *)kUTTypeFileURL]) {
            // Is a non-file URL string. File URLs get special handling.
            [values addObject:string];
            CFStringRef description = NULL;
            for (NSString *theType in item.types) {
                description = UTTypeCopyDescription((CFStringRef)theType);
                if (description) {
                    break;
                }
            }
            NSString *label = [NSString stringWithFormat:@"%@: “%@”",
                               [((NSString *)description ?: @"Unknown Type") stringByCapitalizingFirstLetter],
                               [string ellipsizedDescriptionNoLongerThan:100]];
            if (description) {
                CFRelease(description);
            }
            [labels addObject:label];
        }
        if (!string) {
            NSString *theType = (NSString *)kUTTypeData;
            CFStringRef description = NULL;
            NSData *data = [item dataForType:theType];
            if (!data) {
                for (NSString *typeName in item.types) {
                    if ([typeName hasPrefix:@"public."] &&
                        ![typeName isEqualTo:(NSString *)kUTTypeFileURL]) {
                        data = [item dataForType:typeName];
                        description = UTTypeCopyDescription((CFStringRef)typeName);
                        break;
                    }
                }
            }
            if (data && description) {
                [values addObject:data];
                [labels addObject:(NSString *)description];
            }
            if (description) {
                CFRelease(description);
            }
        }
    }

    // Now handle file references.
    NSArray *filenames = [pasteboard propertyListForType:NSFilenamesPboardType];

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
        [labels addObject:@"Multile file names"];
    } else if (filenames.count == 1) {
        [labels addObject:@"File name"];
    }

    // Add an item for each existing non-directory file.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *filename in filenames) {
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:filename isDirectory:&isDirectory] &&
            !isDirectory) {
            [values addObject:[[[iTermFileReference alloc] initWithName:filename] autorelease]];
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
        string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        if (!string) {
            _base64only = YES;
            string = [data stringWithBase64EncodingWithLineBreak:@"\r"];
        }
    } else {
        string = (NSString *)value;
    }
    _index = index;
    [_rawString autorelease];
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
    BOOL shouldEscape = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash];
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
    _pasteSpecialViewController.shouldWaitForPrompt = _isAtShellPrompt;

    [self updatePreview];
}

- (void)updatePreview {
    PasteEvent *pasteEvent = [self pasteEventWithString:_rawString forPreview:YES];
    [iTermPasteHelper sanitizePasteEvent:pasteEvent encoding:_encoding];
    _preview.string = pasteEvent.string;
    NSNumberFormatter *bytesFormatter = [[[NSNumberFormatter alloc] init] autorelease];
    int numBytes = _preview.string.length;
    if (numBytes < 10) {
        bytesFormatter.numberStyle = NSNumberFormatterSpellOutStyle;
    } else {
        bytesFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    }

    NSNumberFormatter *linesFormatter = [[[NSNumberFormatter alloc] init] autorelease];
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
                 completion:(iTermPasteSpecialCompletionBlock)completion {
    iTermPasteSpecialWindowController *controller =
        [[[iTermPasteSpecialWindowController alloc] initWithChunkSize:chunkSize
                                                   delayBetweenChunks:delayBetweenChunks
                                                    bracketingEnabled:bracketingEnabled
                                                     canWaitForPrompt:canWaitForPrompt
                                                      isAtShellPrompt:isAtShellPrompt
                                                             encoding:encoding] autorelease];
    NSWindow *window = [controller window];
    [NSApp beginSheet:window
       modalForWindow:presentingWindow
        modalDelegate:self
       didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
          contextInfo:nil];

    [NSApp runModalForWindow:window];
    [NSApp endSheet:window];
    [window orderOut:nil];
    [window close];

    if (controller.shouldPaste) {
        completion(controller.pasteEvent);
        [controller saveUserDefaults];
    }
}

#pragma mark - Sheet Delegate

+ (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)returnCode
        contextInfo:(void *)contextInfo {
    [NSApp stopModal];
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
