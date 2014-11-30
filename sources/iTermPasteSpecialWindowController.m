//
//  iTermPasteSpecialWindowController.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "iTermPasteSpecialWindowController.h"
#import "iTermPasteHelper.h"
#import "iTermPreferences.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"

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

typedef struct {
    double min;
    double max;
    double visualCenter;
} iTermFloatingRange;

static iTermFloatingRange kChunkSizeRange = { 1, 1024 * 1024, 1024 };
static iTermFloatingRange kDelayRange = { 0.001, 10, .01 };

// These values correspond to cell tags on the matrix.
NS_ENUM(NSInteger, iTermTabTransformTags) {
    kTabTransformNone = 0,
    kTabTransformConvertToSpaces = 1,
    kTabTransformEscapeWithCtrlZ = 2
};

@interface iTermPasteSpecialWindowController ()

@property(nonatomic, readonly) NSString *stringToPaste;
@property(nonatomic, assign) BOOL shouldPaste;
@property(nonatomic, assign) NSInteger chunkSize;
@property(nonatomic, assign) NSTimeInterval delayBetweenChunks;

@end

@implementation iTermPasteSpecialWindowController {
    // Pre-processed string
    NSString *_rawString;

    // Terminal app expects bracketed data?
    BOOL _bracketingEnabled;

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
    IBOutlet NSTextField *_spacesPerTab;
    IBOutlet NSButton *_escapeShellCharsWithBackslash;
    IBOutlet NSButton *_removeControlCodes;
    IBOutlet NSButton *_bracketedPasteMode;
    IBOutlet NSMatrix *_tabTransform;
    IBOutlet NSButton *_convertNewlines;
    IBOutlet NSButton *_base64Encode;
    IBOutlet NSSlider *_chunkSizeSlider;
    IBOutlet NSSlider *_delayBetweenChunksSlider;
    IBOutlet NSTextField *_chunkSizeLabel;
    IBOutlet NSTextField *_delayBetweenChunksLabel;
    IBOutlet NSStepper *_stepper;
    IBOutlet NSTextField *_estimatedDuration;
}

- (instancetype)initWithChunkSize:(NSInteger)chunkSize
               delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
                bracketingEnabled:(BOOL)bracketingEnabled
                   encoding:(NSStringEncoding)encoding {
    self = [super initWithWindowNibName:@"iTermPasteSpecialWindow"];
    if (self) {
        _index = -1;
        _bracketingEnabled = bracketingEnabled;

        NSMutableArray *values = [NSMutableArray array];
        NSMutableArray *labels = [NSMutableArray array];
        [self getLabels:labels andValues:values];
        _labels = [labels retain];
        _originalValues = [values retain];
        _encoding = encoding;
        self.chunkSize = chunkSize;
        self.delayBetweenChunks = delayBetweenChunks;
    }
    return self;
}

- (void)dealloc {
    [_originalValues release];
    [_labels release];
    [_rawString release];
    [super dealloc];
}

- (void)awakeFromNib {
    for (NSString *label in _labels) {
        [_itemList addItemWithTitle:label];
    }
    [self selectValueAtIndex:0];
}

- (void)getLabels:(NSMutableArray *)labels andValues:(NSMutableArray *)values {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
        NSString *string = [item stringForType:(NSString *)kUTTypeUTF8PlainText];
        if (string && ![item stringForType:(NSString *)kUTTypeFileURL]) {
            // Is a non-file URL string. File URLs get special handling.
            [values addObject:string];
            CFStringRef description = UTTypeCopyDescription((CFStringRef)item.types[0]);
            NSString *label = [NSString stringWithFormat:@"%@: %@",
                               (NSString *)description,
                               [string ellipsizedDescriptionNoLongerThan:100]];
            CFRelease(description);
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
            if (data) {
                [values addObject:data];
                [labels addObject:(NSString *)description];
                if (description) {
                    CFRelease(description);
                }
            }
        }
    }

    // Now handle file references.
    NSArray *filenames = [pasteboard propertyListForType:NSFilenamesPboardType];

    // Escape and join the filenames to add an item for the names themselves.
    NSMutableArray *escapedFilenames = [NSMutableArray array];
    for (NSString *filename in filenames) {
        [escapedFilenames addObject:[filename stringWithEscapedShellCharacters]];
    }
    [values addObject:[escapedFilenames componentsJoinedByString:@" "]];
    if (filenames.count > 1) {
        [labels addObject:@"Filenames joined by spaces"];
    } else if (filenames.count == 1) {
        [labels addObject:@"Filename"];
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
    BOOL base64Only = NO;
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
            base64Only = YES;
            string = [data stringWithBase64EncodingWithLineBreak:@"\r"];
        }
    } else {
        string = (NSString *)value;
    }
    _index = index;
    [_rawString autorelease];
    _rawString = [string copy];
    BOOL containsTabs = [string containsString:@"\t"];

    _spacesPerTab.enabled = containsTabs;
    _spacesPerTab.integerValue = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    _stepper.integerValue = _spacesPerTab.integerValue;
    _stepper.enabled = _spacesPerTab.enabled;

    _tabTransform.enabled = containsTabs;
    NSInteger tabTransformTag = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialTabTransform];
    [_tabTransform selectCellWithTag:tabTransformTag];

    NSCharacterSet *theSet =
            [NSCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    BOOL containsShellCharacters =
    [string rangeOfCharacterFromSet:theSet].location != NSNotFound;

    BOOL containsDosNewlines = [string containsString:@"\n"];
    _convertNewlines.enabled = containsDosNewlines;
    BOOL convertValue = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialConvertDosNewlines];
    _convertNewlines.state = (containsDosNewlines && convertValue) ? NSOnState : NSOffState;

    _escapeShellCharsWithBackslash.enabled = containsShellCharacters;
    BOOL shouldEscape = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash];
    _escapeShellCharsWithBackslash.state =
            (containsShellCharacters && shouldEscape) ? NSOnState : NSOffState;

    _delayBetweenChunksSlider.minValue = log(kDelayRange.min);
    _delayBetweenChunksSlider.maxValue = log(kDelayRange.max);
    _delayBetweenChunksSlider.floatValue = [self floatValueForDelayBetweenChunks];
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];

    _chunkSizeSlider.minValue = log(kChunkSizeRange.min);
    _chunkSizeSlider.maxValue = log(kChunkSizeRange.max);
    _chunkSizeSlider.floatValue = [self floatValueForChunkSize];
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];

    NSMutableCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];
    NSRange unsafeRange = [string rangeOfCharacterFromSet:unsafeSet];
    BOOL containsControlCodes = unsafeRange.location != NSNotFound;
    _removeControlCodes.enabled = containsControlCodes;
    BOOL removeValue = [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialRemoveControlCodes];
    _removeControlCodes.state = (containsControlCodes && removeValue) ? NSOnState : NSOffState;

    _bracketedPasteMode.enabled = _bracketingEnabled;
    NSNumber *bracketSetting =
        [iTermPreferences boolForKey:kPreferenceKeyPasteSpecialBracketedPasteMode];
    BOOL shouldBracket = YES;
    if (bracketSetting && ![bracketSetting boolValue]) {
        shouldBracket = NO;
    }
    _bracketedPasteMode.state = (_bracketingEnabled && shouldBracket) ? NSOnState : NSOffState;

    _base64Encode.state = base64Only ? NSOnState : NSOffState;
    _base64Encode.enabled = !base64Only;

    [self updatePreview];
}

- (void)updatePreview {
    BOOL spacesPerTabEnabled = _tabTransform.enabled && _tabTransform.selectedTag == kTabTransformConvertToSpaces;
    _spacesPerTab.enabled = spacesPerTabEnabled;

    _preview.string = [self stringByProcessingString:_rawString];
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
        _estimatedDuration.stringValue = [self descriptionForDuration:duration];
    }
}

+ (void)showAsPanelInWindow:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                   encoding:(NSStringEncoding)encoding
                 completion:(iTermPasteSpecialCompletionBlock)completion {
    iTermPasteSpecialWindowController *controller =
        [[[iTermPasteSpecialWindowController alloc] initWithChunkSize:chunkSize
                                                   delayBetweenChunks:delayBetweenChunks
                                                    bracketingEnabled:bracketingEnabled
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
        completion(controller.stringToPaste,
                   controller.chunkSize,
                   controller.delayBetweenChunks);
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

// TODO: When 10.7 support is dropped use NSByteCountFormatter
- (NSString *)descriptionForByteSize:(double)chunkSize {
    NSArray *units = @[ @"", @"k", @"M", @"G", @"T" , @"P", @"E", @"Z", @"Y" ];
    int multiplier = 1024;
    int exponent = 0;

    while (chunkSize >= multiplier && exponent < units.count) {
        chunkSize /= multiplier;
        exponent++;
    }
    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
    [formatter setMaximumFractionDigits:2];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    NSString *description = [NSString stringWithFormat:@"%@ %@B",
                             [formatter stringFromNumber:@(chunkSize)],
                             units[exponent]];
    return description;
}

- (NSString *)descriptionForDuration:(NSTimeInterval)duration {
    NSString *units;
    double multiplier;
    if (duration < 0.00001) {
        units = @"µs";
        multiplier = 0.00001;
    } else if (duration < 1) {
        units = @"ms";
        multiplier = 0.001;
    } else if (duration < 60) {
        units = @"sec";
        multiplier = 1;
    } else {
        units = @"min";
        multiplier = 60;
    }

    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
    [formatter setMaximumFractionDigits:2];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    NSString *description = [NSString stringWithFormat:@"%@ %@",
                             [formatter stringFromNumber:@(duration / multiplier)],
                             units];
    return description;
}

- (float)floatValueForChunkSize {
    return log(_chunkSize);
}

- (float)floatValueForDelayBetweenChunks {
    return log(_delayBetweenChunks);
}

- (void)saveUserDefaults {
    if (_tabTransform.enabled) {
        [iTermPreferences setInt:_tabTransform.selectedTag
                          forKey:kPreferenceKeyPasteSpecialTabTransform];
    }
    if (_spacesPerTab.enabled) {
        [iTermPreferences setInt:_spacesPerTab.integerValue
                          forKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    }
    if (_escapeShellCharsWithBackslash.enabled) {
        [iTermPreferences setBool:_escapeShellCharsWithBackslash.state == NSOnState
                       forKey:kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash];
    }
    if (_convertNewlines.enabled) {
        [iTermPreferences setBool:_convertNewlines.state == NSOnState
                           forKey:kPreferenceKeyPasteSpecialConvertDosNewlines];
    }
    if (_bracketingEnabled) {
        [iTermPreferences setBool:_bracketedPasteMode.state == NSOnState
                           forKey:kPreferenceKeyPasteSpecialBracketedPasteMode];
    }
}

- (NSString *)stringToPaste {
    NSString *unbracketed = [self stringByProcessingString:_rawString];
    if (_bracketedPasteMode.state == NSOnState) {
        return [iTermPasteHelper sanitizeString:unbracketed withFlags:kPasteFlagsBracket];
    } else {
        return unbracketed;
    }
}

- (NSString *)stringByProcessingString:(NSString *)string {
    NSUInteger flags = 0;
    if (_convertNewlines.enabled && _convertNewlines.state == NSOnState) {
        flags |= kPasteFlagsSanitizingNewlines;
    }
    if (_escapeShellCharsWithBackslash.enabled && _escapeShellCharsWithBackslash.state == NSOnState) {
        flags |= kPasteFlagsEscapeSpecialCharacters;
    }
    if (_tabTransform.enabled) {
        switch (_tabTransform.selectedTag) {
            case kTabTransformNone:
                break;

            case kTabTransformConvertToSpaces:
                string = [string stringByReplacingOccurrencesOfString:@"\t"
                                                           withString:[@" " stringRepeatedTimes:_spacesPerTab.integerValue]];
                break;

            case kTabTransformEscapeWithCtrlZ:
                flags |= kPasteFlagsWithShellEscapedTabs;
                break;
        }
    }
    if (_removeControlCodes.state == NSOnState) {
        flags |= kPasteFlagsRemovingUnsafeControlCodes;
    }

    string = [iTermPasteHelper sanitizeString:string withFlags:flags];

    if (_base64Encode.state == NSOnState) {
        string = [[string dataUsingEncoding:_encoding] stringWithBase64EncodingWithLineBreak:@"\r"];
    }

    return string;
}

#pragma mark - Actions

- (IBAction)chunkSizeDidChange:(id)sender {
    _chunkSize = exp([sender floatValue]);
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];
    [self updateDuration];
}

- (IBAction)delayBetweenChunksDidChange:(id)sender {
    _delayBetweenChunks = exp([sender floatValue]);
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];
    [self updateDuration];
}

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

- (IBAction)settingChanged:(id)sender {
    [self updatePreview];
}

- (IBAction)stepperDidChange:(id)sender {
    NSStepper *stepper = sender;
    _spacesPerTab.integerValue = stepper.integerValue;
    [self updatePreview];
}

#pragma mark - NSTextField Delegate

- (void)controlTextDidChange:(NSNotification *)obj {
    _spacesPerTab.integerValue = MAX(0, MIN(100, _spacesPerTab.integerValue));
    _stepper.integerValue = _spacesPerTab.integerValue;
}

@end
