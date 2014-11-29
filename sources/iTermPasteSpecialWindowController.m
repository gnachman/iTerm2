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
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"

typedef struct {
    double min;
    double max;
} iTermFloatingRange;

static iTermFloatingRange kChunkSizeRange = { 1, 1024 * 1024 };
static iTermFloatingRange kDelayRange = { 0.001, 10 };

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

@property(nonatomic, readonly) NSData *dataToPaste;
@property(nonatomic, assign) BOOL shouldPaste;
@property(nonatomic, assign) NSInteger chunkSize;
@property(nonatomic, assign) NSTimeInterval delayBetweenChunks;

@end

@implementation iTermPasteSpecialWindowController {
    // Terminal app expects bracketed data?
    BOOL _bracketingEnabled;

    // If this came from a string then it is UTF-8 encoded. It could also be a binary file with no
    // string encoding.
    NSData *_originalPasteboardData;

    // Outlets
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
}

- (instancetype)initWithChunkSize:(NSInteger)chunkSize
               delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
                bracketingEnabled:(BOOL)bracketingEnabled {
    self = [super initWithWindowNibName:@"iTermPasteSpecialWindow"];
    if (self) {
        _bracketingEnabled = bracketingEnabled;
        _originalPasteboardData =
                [[[NSString stringFromPasteboard] dataUsingEncoding:NSUTF8StringEncoding] retain];
        self.chunkSize = chunkSize;
        self.delayBetweenChunks = delayBetweenChunks;
    }
    return self;
}

- (void)dealloc {
    [_originalPasteboardData release];
    [super dealloc];
}

- (void)awakeFromNib {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSData *tabData = [NSData dataWithBytes:"\t" length:1];
    BOOL containsTabs = [_originalPasteboardData rangeOfData:tabData
                                                     options:0
                                                       range:NSMakeRange(0, _originalPasteboardData.length)].location != NSNotFound;

    _spacesPerTab.enabled = containsTabs;
    _spacesPerTab.integerValue = [userDefaults integerForKey:kSpacesPerTab] ?: kDefaultSpacesPerTab;

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
            [_originalPasteboardData containsAsciiCharacterInSet:theSet];

    NSData *crlfData = [NSData dataWithBytes:"\r\n" length:2];
    BOOL containsDosNewlines =
        [_originalPasteboardData rangeOfData:crlfData
                                     options:0
                                       range:NSMakeRange(0, _originalPasteboardData.length)].location != NSNotFound;
    _convertNewlines.enabled = containsDosNewlines;
    NSNumber *convertValue = [userDefaults objectForKey:kConvertDosNewlines];
    if (!convertValue) {
        convertValue = @YES;
    }
    _convertNewlines.state = [convertValue boolValue] ? NSOnState : NSOffState;

    _escapeShellCharsWithBackslash.enabled = containsShellCharacters;
    _escapeShellCharsWithBackslash.state =
            [userDefaults boolForKey:kEscapeShellCharsWithBackslash] ? NSOnState : NSOffState;

    _delayBetweenChunksSlider.floatValue = [self floatValueForDelayBetweenChunks];
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];

    _chunkSizeSlider.floatValue = [self floatValueForChunkSize];
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];

    NSCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];
    BOOL containsControlCodes = [_originalPasteboardData containsAsciiCharacterInSet:unsafeSet];
    _removeControlCodes.enabled = containsControlCodes;
    NSNumber *removeValue = [userDefaults objectForKey:kRemoveControlCodes];
    if (!removeValue) {
        removeValue = @YES;
    }
    _removeControlCodes.state = [removeValue boolValue] ? NSOnState : NSOffState;

    _bracketedPasteMode.enabled = _bracketingEnabled;
    _bracketedPasteMode.state =
        (_bracketingEnabled && [userDefaults boolForKey:kBracketedPasteMode]) ? NSOnState : NSOffState;

    _base64Encode.state = NSOffState;
}

+ (void)showAsPanelInWindow:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                 completion:(iTermPasteSpecialCompletionBlock)completion {
    iTermPasteSpecialWindowController *controller =
        [[[iTermPasteSpecialWindowController alloc] initWithChunkSize:chunkSize
                                                   delayBetweenChunks:delayBetweenChunks
                                                    bracketingEnabled:bracketingEnabled] autorelease];
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
        completion(controller.dataToPaste,
                   controller.chunkSize,
                   controller.delayBetweenChunks);
        [controller saveUserDefaults];
    }
}

#pragma mark - Sheet Delegate

- (void)sheetDidEnd:(NSWindow *)sheet
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
    if (duration < 1) {
        units = @"µs";
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

// Returns a value in |range|. Takes a value in [0, 1].
- (NSInteger)floatValue:(float)floatValue mappedLogarithmicallyIntoRange:(iTermFloatingRange)range {
    // f(0)=range.min
    // f(1)=range.max;
    // f(x)=range.min + (10^x - 1) / 9 * (range.max - range.min);
    const double base = 10;
    // factor scales exponentially from 0 to 1
    double factor = (pow(base, floatValue) - 1) / (base - 1);
    return range.min + factor * (range.max - range.min);
}

// Returns a value from 0 to 1. Takes a |value| in range.
- (float)value:(NSInteger)value mappedLogarithmicallyFromRange:(iTermFloatingRange)range {
    // This is the inverse of:
    // f'(x)=range.min + (10^x - 1) / 9 * (range.max - range.min);
    // Which is:
    // f(y) = log10(1 + 9 * (y - range.min) / (range.max - range.min))

    const double base = 10;
    return log10(1 + (base - 1) * (value - range.min) / (range.max - range.min));
}

- (float)floatValueForDelayBetweenChunks {
    return [self value:_chunkSize mappedLogarithmicallyFromRange:kChunkSizeRange];
}

- (float)floatValueForChunkSize {
    return [self value:_delayBetweenChunks mappedLogarithmicallyFromRange:kDelayRange];
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

- (NSData *)dataToPaste {
    NSMutableCharacterSet *unsafeSet = [iTermPasteHelper unsafeControlCodeSet];

    NSMutableData *data = [_originalPasteboardData mutableCopy];
    if (_convertNewlines.enabled && _convertNewlines.state == NSOnState) {
        [data replaceOccurrencesOfBytes:"\r\n" length:2 withBytes:"\n" length:1];
    }

    if (_escapeShellCharsWithBackslash.enabled && _escapeShellCharsWithBackslash.state == NSOnState) {
        [data escapeShellCharacters];
    }

    if (_tabTransform.enabled) {
        switch (_tabTransform.selectedTag) {
            case kTabTransformNone:
                break;

            case kTabTransformConvertToSpaces: {
                NSString *spaces = [@" " stringRepeatedTimes:_spacesPerTab.integerValue];
                [data replaceOccurrencesOfBytes:"\t"
                                         length:1
                                      withBytes:[spaces UTF8String]
                                         length:spaces.length];
                break;
            }

            case kTabTransformEscapeWithCtrlZ:
                if (_removeControlCodes.state == NSOnState) {
                    // First remove ^Vs if we're stripping unsafe codes.
                    [data replaceOccurrencesOfBytes:"\x16"
                                             length:1
                                          withBytes:""
                                             length:0];
                    // Remove ^V from the unsafe set so the ones added next can survive.
                    [unsafeSet removeCharactersInRange:NSMakeRange(22, 1)];
                }
                // Add ^Vs before each tab
                [data replaceOccurrencesOfBytes:"t"
                                         length:1
                                      withBytes:"\x16\t"
                                         length:2];
                break;
        }
    }

    if (_removeControlCodes.state == NSOnState) {
        [data removeAsciiCharactersInSet:unsafeSet];
    }

    if (_bracketedPasteMode.state == NSOnState) {
        NSString *startBracket = [NSString stringWithFormat:@"%c[200~", 27];
        NSString *endBracket = [NSString stringWithFormat:@"%c[201~", 27];
        [data replaceBytesInRange:NSMakeRange(0, 0) withBytes:[startBracket UTF8String]];
        [data appendBytes:[endBracket UTF8String] length:endBracket.length];
    }

    if (_base64Encode.state == NSOnState) {
        NSString *encoded = [data stringWithBase64Encoding];
        [data setData:[encoded dataUsingEncoding:NSUTF8StringEncoding]];
    }

    return data;
}

#pragma mark - Actions

- (IBAction)chunkSizeDidChange:(id)sender {
    _chunkSize = [self floatValue:[sender floatValue] mappedLogarithmicallyIntoRange:kChunkSizeRange];
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];
}

- (IBAction)delayBetweenChunksDidChange:(id)sender {
    _delayBetweenChunks = [self floatValue:[sender floatValue] mappedLogarithmicallyIntoRange:kDelayRange];
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];
}

- (void)ok:(id)sender {
    _shouldPaste = YES;
    [NSApp stopModal];
}

- (void)cancel:(id)sender {
    _shouldPaste = NO;
    [NSApp stopModal];
}

@end
