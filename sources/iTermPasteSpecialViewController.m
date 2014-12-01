//
//  iTermPasteSpecialViewController.m
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import "iTermPasteSpecialViewController.h"

typedef struct {
    double min;
    double max;
    double visualCenter;
} iTermFloatingRange;

static iTermFloatingRange kChunkSizeRange = { 1, 1024 * 1024, 1024 };
static iTermFloatingRange kDelayRange = { 0.001, 10, .01 };

@implementation iTermPasteSpecialViewController {
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

- (instancetype)init {
    self = [super initWithNibName:@"iTermPasteSpecialViewController" bundle:nil];
    return self;
}

- (void)awakeFromNib {
    _delayBetweenChunksSlider.minValue = log(kDelayRange.min);
    _delayBetweenChunksSlider.maxValue = log(kDelayRange.max);

    _chunkSizeSlider.minValue = log(kChunkSizeRange.min);
    _chunkSizeSlider.maxValue = log(kChunkSizeRange.max);

    self.delayBetweenChunks = kDelayRange.visualCenter;
    self.chunkSize = kChunkSizeRange.visualCenter;
}

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

#pragma mark - Actions

- (IBAction)chunkSizeDidChange:(id)sender {
    _chunkSize = exp([sender floatValue]);
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];
    [_delegate pasteSpecialViewSpeedDidChange];
}

- (IBAction)delayBetweenChunksDidChange:(id)sender {
    _delayBetweenChunks = exp([sender floatValue]);
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];
    [_delegate pasteSpecialViewSpeedDidChange];
}

- (IBAction)settingChanged:(id)sender {
    _spacesPerTab.enabled = (_tabTransform.enabled &&
                             _tabTransform.selectedTag == kTabTransformConvertToSpaces);
    [_delegate pasteSpecialTransformDidChange];
}

- (IBAction)stepperDidChange:(id)sender {
    NSStepper *stepper = sender;
    _spacesPerTab.integerValue = stepper.integerValue;
    [_delegate pasteSpecialTransformDidChange];
}

#pragma mark - NSTextField Delegate

- (void)controlTextDidChange:(NSNotification *)obj {
    _spacesPerTab.integerValue = MAX(0, MIN(100, _spacesPerTab.integerValue));
    _stepper.integerValue = _spacesPerTab.integerValue;
}

#pragma mark - Properties

- (int)numberOfSpacesPerTab {
    return _spacesPerTab.integerValue;
}

- (void)setNumberOfSpacesPerTab:(int)numberOfSpacesPerTab {
    _spacesPerTab.integerValue = numberOfSpacesPerTab;
    _stepper.integerValue = numberOfSpacesPerTab;
}

- (void)setEnableTabTransforms:(BOOL)enableTabTransforms {
    _tabTransform.enabled = enableTabTransforms;
    _spacesPerTab.enabled = enableTabTransforms;
    _stepper.enabled = enableTabTransforms;
}

- (BOOL)areTabTransformsEnabled {
    return _tabTransform.enabled;
}

- (void)setSelectedTabTransform:(NSInteger)selectedTabTransform {
    [_tabTransform selectCellWithTag:selectedTabTransform];
}

- (NSInteger)selectedTabTransform {
    return _tabTransform.selectedTag;
}

- (void)setEnableConvertNewlines:(BOOL)enableConvertNewlines {
    _convertNewlines.enabled = enableConvertNewlines;
}

- (BOOL)isConvertNewlinesEnabled {
    return _convertNewlines.enabled;
}

- (void)setShouldConvertNewlines:(BOOL)shouldConvertNewlines {
    _convertNewlines.state = shouldConvertNewlines ? NSOnState : NSOffState;
}

- (BOOL)shouldConvertNewlines {
    return _convertNewlines.state == NSOnState;
}

- (void)setEnableEscapeShellCharsWithBackslash:(BOOL)enableEscapeShellCharsWithBackslash {
    _escapeShellCharsWithBackslash.enabled = enableEscapeShellCharsWithBackslash;
}

- (BOOL)isEscapeShellCharsWithBackslashEnabled {
    return _escapeShellCharsWithBackslash.enabled;
}

- (void)setShouldEscapeShellCharsWithBackslash:(BOOL)shouldEscapeShellCharsWithBackslash {
    _escapeShellCharsWithBackslash.state = shouldEscapeShellCharsWithBackslash ? NSOnState : NSOffState;
}

- (BOOL)shouldEscapeShellCharsWithBackslash {
    return _escapeShellCharsWithBackslash.state == NSOnState;
}

- (void)setDelayBetweenChunks:(NSTimeInterval)delayBetweenChunks {
    _delayBetweenChunks = delayBetweenChunks;
    _delayBetweenChunksLabel.stringValue = [self descriptionForDuration:_delayBetweenChunks];
    _delayBetweenChunksSlider.floatValue = log(_delayBetweenChunks);
}

- (void)setChunkSize:(int)chunkSize {
    _chunkSize = chunkSize;
    _chunkSizeLabel.stringValue = [self descriptionForByteSize:_chunkSize];
    _chunkSizeSlider.floatValue = log(_chunkSize);
}

- (void)setEnableRemoveControlCodes:(BOOL)enableRemoveControlCodes {
    _removeControlCodes.enabled = enableRemoveControlCodes;
}

- (BOOL)isRemoveControlCodesEnabled {
    return _removeControlCodes.enabled;
}

- (void)setShouldRemoveControlCodes:(BOOL)shouldRemoveControlCodes {
    _removeControlCodes.state = shouldRemoveControlCodes ? NSOnState : NSOffState;
}

- (BOOL)shouldRemoveControlCodes {
    return _removeControlCodes.state == NSOnState;
}

- (void)setEnableBracketedPaste:(BOOL)enableBracketedPaste {
    _bracketedPasteMode.enabled = enableBracketedPaste;
}

- (BOOL)isBracketedPasteEnabled {
    return _bracketedPasteMode.enabled;
}

- (void)setShouldUseBracketedPasteMode:(BOOL)shouldUseBracketedPasteMode {
    _bracketedPasteMode.state = shouldUseBracketedPasteMode ? NSOnState : NSOffState;
}

- (BOOL)shouldUseBracketedPasteMode {
    return _bracketedPasteMode.state == NSOnState;
}

- (void)setEnableBase64:(BOOL)enableBase64 {
    _base64Encode.enabled = enableBase64;
}

- (BOOL)isBase64Enabled {
    return _base64Encode.enabled;
}

- (void)setShouldBase64Encode:(BOOL)shouldBase64Encode {
    _base64Encode.state = shouldBase64Encode ? NSOnState : NSOffState;
}

- (BOOL)shouldBase64Encode {
    return _base64Encode.state == NSOnState;
}

@end
