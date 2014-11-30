//
//  iTermPasteSpecialWindowController.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "iTermPasteSpecialWindowController.h"
#import "iTermPasteHelper.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"

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

static const NSInteger kDefaultTabTransform = kTabTransformNone;
static NSString *const kSpacesPerTab = @"NumberOfSpacesPerTab";
static NSString *const kTabTransform = @"TabTransform";
static NSString *const kEscapeShellCharsWithBackslash = @"EscapeShellCharsWithBackslash";
static NSString *const kConvertDosNewlines = @"ConvertDosNewlines";
static NSString *const kRemoveControlCodes = @"RemoveControlCodes";
static NSString *const kBracketedPasteMode = @"BracketedPasteMode";
static const NSInteger kDefaultSpacesPerTab = 4;

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
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

        for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
            NSString *string = [item stringForType:(NSString *)kUTTypeUTF8PlainText];
            if (string && ![item stringForType:(NSString *)kUTTypeFileURL]) {
                // Is a non-file URL string. File URLs get special handling.
                [values addObject:string];
                CFStringRef description = UTTypeCopyDescription((CFStringRef)item.types[0]);
                [labels addObject:(NSString *)description];
                CFRelease(description);
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
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    BOOL containsTabs = [string containsString:@"\t"];

    _spacesPerTab.enabled = containsTabs;
    _spacesPerTab.integerValue = [userDefaults integerForKey:kSpacesPerTab] ?: kDefaultSpacesPerTab;
    _stepper.integerValue = _spacesPerTab.integerValue;
    _stepper.enabled = _spacesPerTab.enabled;

    _tabTransform.enabled = containsTabs;
    NSInteger tabTransformTag;
    if ([userDefaults objectForKey:kTabTransform]) {
        tabTransformTag = [userDefaults integerForKey:kTabTransform];
    } else {
        tabTransformTag = kDefaultTabTransform;
    }
    [_tabTransform selectCellWithTag:tabTransformTag];

    NSCharacterSet *theSet =
            [NSCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    BOOL containsShellCharacters =
    [string rangeOfCharacterFromSet:theSet].location != NSNotFound;

    BOOL containsDosNewlines = [string containsString:@"\r\n"];
    _convertNewlines.enabled = containsDosNewlines;
    NSNumber *convertValue = [userDefaults objectForKey:kConvertDosNewlines];
    if (!convertValue) {
        convertValue = @YES;
    }
    _convertNewlines.state = (containsDosNewlines && [convertValue boolValue]) ? NSOnState : NSOffState;

    _escapeShellCharsWithBackslash.enabled = containsShellCharacters;
    _escapeShellCharsWithBackslash.state =
            (containsShellCharacters && [userDefaults boolForKey:kEscapeShellCharsWithBackslash]) ? NSOnState : NSOffState;

    _delayBetweenChunksSlider.minValue = log(kDelayRange.min);
    _delayBetweenChunksSlider.maxValue = log(kDelayRange.max);
    _delayBetweenChunksSlider.floatValue = [self floatValueForDelayBetweenChunks];
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];

    _chunkSizeSlider.minValue = log(kChunkSizeRange.min);
    _chunkSizeSlider.maxValue = log(kChunkSizeRange.max);
    _chunkSizeSlider.floatValue = [self floatValueForChunkSize];
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];

    NSCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];
    NSRange unsafeRange = [string rangeOfCharacterFromSet:unsafeSet];
    BOOL containsControlCodes = unsafeRange.location != NSNotFound;
    _removeControlCodes.enabled = containsControlCodes;
    NSNumber *removeValue = [userDefaults objectForKey:kRemoveControlCodes];
    if (!removeValue) {
        removeValue = @YES;
    }
    _removeControlCodes.state = (containsControlCodes && [removeValue boolValue]) ? NSOnState : NSOffState;

    _bracketedPasteMode.enabled = _bracketingEnabled;
    _bracketedPasteMode.state =
        (_bracketingEnabled && [userDefaults boolForKey:kBracketedPasteMode]) ? NSOnState : NSOffState;

    _base64Encode.state = base64Only ? NSOnState : NSOffState;
    _base64Encode.enabled = !base64Only;

    [self updatePreview];
}

- (void)updatePreview {
    _preview.string = [[self stringToPaste] stringByReplacingOccurrencesOfString:@"\x16\t"
                                                                      withString:@"^V\t"];
    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];

    NSUInteger numberOfLines = _preview.string.numberOfLines;
    _statsLabel.stringValue = [NSString stringWithFormat:@"%@ bytes in %@ line%@.",
                               [formatter stringFromNumber:@(_preview.string.length)],
                               [formatter stringFromNumber:@(numberOfLines)],
                               numberOfLines == 1 ? @"" : @"s"];
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
    } else {
        units = @"sec";
        multiplier = 1;
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
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (_tabTransform.enabled) {
        [userDefaults setInteger:_tabTransform.selectedCell forKey:kTabTransform];
    }
    if (_spacesPerTab.enabled) {
        [userDefaults setInteger:_spacesPerTab.integerValue forKey:kSpacesPerTab];
    }
    if (_escapeShellCharsWithBackslash.enabled) {
        [userDefaults setBool:_escapeShellCharsWithBackslash.state == NSOnState
                       forKey:kEscapeShellCharsWithBackslash];
    }
    if (_convertNewlines.enabled) {
        [userDefaults setBool:_convertNewlines.state == NSOnState forKey:kConvertDosNewlines];
    }
    if (_bracketingEnabled) {
        [userDefaults setBool:_bracketedPasteMode.state == NSOnState forKey:kBracketedPasteMode];
    }
}

- (NSString *)stringToPaste {
    return [self stringByProcessingString:_rawString];
}

- (NSMutableString *)stringByProcessingString:(NSString *)inputString {
    NSMutableString *string = [[inputString mutableCopy] autorelease];
    if (_convertNewlines.enabled && _convertNewlines.state == NSOnState) {
        [string replaceOccurrencesOfString:@"\r\n"
                                withString:@"\n"
                                   options:0
                                     range:NSMakeRange(0, string.length)];
    }

    if (_escapeShellCharsWithBackslash.enabled && _escapeShellCharsWithBackslash.state == NSOnState) {
        [string escapeShellCharacters];
    }

    NSMutableCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];
    if (_tabTransform.enabled) {
        switch (_tabTransform.selectedTag) {
            case kTabTransformNone:
                break;

            case kTabTransformConvertToSpaces: {
                [string replaceOccurrencesOfString:@"\t"
                                        withString:[@" " stringRepeatedTimes:_spacesPerTab.integerValue]
                                           options:0
                                             range:NSMakeRange(0, string.length)];
                break;
            }

            case kTabTransformEscapeWithCtrlZ:
                if (_removeControlCodes.state == NSOnState) {
                    // First remove ^Vs if we're stripping unsafe codes.
                    [string replaceOccurrencesOfString:@"\x16"
                                            withString:@""
                                               options:0
                                                 range:NSMakeRange(0, string.length)];
                    // Remove ^V from the unsafe set so the ones added next can survive.
                    [unsafeSet removeCharactersInRange:NSMakeRange(22, 1)];
                }
                // Add ^Vs before each tab
                [string replaceOccurrencesOfString:@"\t"
                                        withString:@"\x16\t"
                                           options:0
                                             range:NSMakeRange(0, string.length)];
                break;
        }
    }

    if (_removeControlCodes.state == NSOnState) {
        [[string componentsSeparatedByCharactersInSet:unsafeSet] componentsJoinedByString:@""];
    }

    if (_bracketedPasteMode.state == NSOnState) {
        NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
        NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
        [string insertString:startBracket atIndex:0];
        [string appendString:endBracket];
    }

    if (_base64Encode.state == NSOnState) {
        [string setString:[[string dataUsingEncoding:_encoding] stringWithBase64EncodingWithLineBreak:@"\r"]];
    }

    return string;
}

#pragma mark - Actions

- (IBAction)chunkSizeDidChange:(id)sender {
    _chunkSize = exp([sender floatValue]);
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];
}

- (IBAction)delayBetweenChunksDidChange:(id)sender {
    _delayBetweenChunks = exp([sender floatValue]);
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];
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
