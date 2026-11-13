//
//  iTermPasteSpecialViewController.m
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import "iTermPasteSpecialViewController.h"
#import "iTerm2SharedARC-Swift.h"
#import "NSTextField+iTerm.h"
#import "PasteEvent.h"

typedef struct {
    double min;
    double max;
    double visualCenter;
} iTermFloatingRange;

#define DASHES @"\u2010-\u2015\u207b\u208b\u2212\u2e3a\u2e3b\ufe58\ufe63\uff0d\u00ad"
#define DOUBLE_QUOTES @"\u201c-\u201f\u301d-\u301f\uff02"
#define SINGLE_QUOTES @"\u2018-\u201b\uff07"

NSString *const kPasteSpecialViewControllerUnicodePunctuationRegularExpression =
    @"[" DASHES DOUBLE_QUOTES SINGLE_QUOTES @"]";
NSString *const kPasteSpecialViewControllerUnicodeDashesRegularExpression =
    @"[" DASHES @"]";
NSString *const kPasteSpecialViewControllerUnicodeDoubleQuotesRegularExpression =
    @"[" DOUBLE_QUOTES @"]";
NSString *const kPasteSpecialViewControllerUnicodeSingleQuotesRegularExpression =
    @"[" SINGLE_QUOTES @"]";


static iTermFloatingRange kChunkSizeRange = { 1, 1024 * 1024, 1024 };
static iTermFloatingRange kDelayRange = { 0.001, 10, .01 };

// Keys for string encoding
static NSString *const kChunkSize = @"ChunkSize";
static NSString *const kDelayBetweenChunks = @"Delay";
static NSString *const kNumberOfSpacesPerTab = @"TabStopSize";
static NSString *const kSelectedTabTransform = @"TabTransform";
static NSString *const kShouldConvertNewlines = @"ConvertNewlines";
static NSString *const kShouldRemoveNewlines = @"RemoveNewlines";
static NSString *const kShouldEscapeShellCharsWithBackslash = @"EscapeForShell";
static NSString *const kShouldRemoveControlCodes = @"RemoveControls";
static NSString *const kShouldUseBracketedPasteMode = @"BracketAllowed";
static NSString *const kShouldBase64Encode = @"Base64";
static NSString *const kShouldConvertUnicodePunctuation = @"ConvertUnicodePunctuation";
static NSString *const kShouldWaitForPrompts = @"WaitForPrompts";
static NSString *const kShouldUseRegexSubstitution = @"UseRegexSubstitution";
static NSString *const kRegularExpression = @"Regex";
static NSString *const kSubstitution = @"Substitution";

@interface iTermPasteSpecialViewController()<NSControlTextEditingDelegate>
@end

@implementation iTermPasteSpecialViewController {
    IBOutlet NSTextField *_spacesPerTab;
    IBOutlet NSButton *_escapeShellCharsWithBackslash;
    IBOutlet NSButton *_removeControlCodes;
    IBOutlet NSButton *_bracketedPasteMode;
    IBOutlet NSMatrix *_tabTransform;
    IBOutlet NSButton *_convertNewlines;
    IBOutlet NSButton *_removeNewlines;
    IBOutlet NSButton *_base64Encode;
    IBOutlet NSButton *_useRegexSubstitution;
    IBOutlet NSTextField *_regex;
    IBOutlet NSTextField *_substitution;
    IBOutlet NSButton *_waitForPrompts;
    IBOutlet NSButton *_convertUnicodePunctuation;
    IBOutlet NSSlider *_chunkSizeSlider;
    IBOutlet NSSlider *_delayBetweenChunksSlider;
    IBOutlet NSTextField *_chunkSizeLabel;
    IBOutlet NSTextField *_delayBetweenChunksLabel;
    IBOutlet NSTextField *_chunkSizeTitle;
    IBOutlet NSTextField *_delayBetweenChunksTitle;
    IBOutlet NSStepper *_stepper;
    IBOutlet NSTextField *_icuRegexHelpLabel;  // Warning: this gets removed from superview in awakeFromNib.
}

- (instancetype)init {
    self = [super initWithNibName:@"iTermPasteSpecialViewController" bundle:[NSBundle bundleForClass:self.class]];
    return self;
}

- (void)awakeFromNib {
    _delayBetweenChunksSlider.minValue = log(kDelayRange.min);
    _delayBetweenChunksSlider.maxValue = log(kDelayRange.max);

    _chunkSizeSlider.minValue = log(kChunkSizeRange.min);
    _chunkSizeSlider.maxValue = log(kChunkSizeRange.max);

    self.delayBetweenChunks = kDelayRange.visualCenter;
    self.chunkSize = kChunkSizeRange.visualCenter;

    [self layoutForTranslations];

    [_icuRegexHelpLabel replaceWithHyperlinkTo:[NSURL URLWithString:@"https://iterm2.com/regex"]];
    _icuRegexHelpLabel = nil;
}

static CGFloat iTermPasteSpecialWidthNeeded(NSCell *cell) {
    return ceil(cell.cellSize.width);
}

// How much wider `button` must be to show its title.
static CGFloat iTermPasteSpecialShortfall(NSButton *button) {
    return MAX(0, iTermPasteSpecialWidthNeeded(button.cell) - NSWidth(button.frame));
}

// The nib is laid out for English in two columns of checkboxes. Translated
// titles can be wider, so widen the left column, the right column, or both to
// fit the widest title in each, and widen the view to match. English is
// unchanged. Hosts size themselves from the view's frame afterward. This runs
// from -awakeFromNib, before anyone sets profileType, so the terminal-mode
// enclosures save these frames as their original layout. Safe to call again
// after a title changes.
- (void)layoutForTranslations {
    NSView *view = self.view;
    NSArray<NSButton *> *leftCheckboxes = @[ _convertNewlines, _removeNewlines, _base64Encode, _bracketedPasteMode ];
    NSArray<NSButton *> *rightCheckboxes = @[ _escapeShellCharsWithBackslash, _convertUnicodePunctuation, _removeControlCodes ];

    // The Replace checkbox grows into the regex field beside it.
    const CGFloat replaceExtra = iTermPasteSpecialShortfall(_useRegexSubstitution);
    CGFloat leftExtra = replaceExtra;
    for (NSButton *checkbox in leftCheckboxes) {
        leftExtra = MAX(leftExtra, iTermPasteSpecialShortfall(checkbox));
    }
    // The tab radio buttons share one cell width. The row with the spaces field
    // ends where the field begins (the matrix overlaps it by a few points in the
    // nib, and must not overlap it more, since the matrix is in front of the
    // field and would take its clicks).
    const CGFloat matrixOverlap = MAX(0, NSMaxX(_tabTransform.frame) - NSMinX(_spacesPerTab.frame));
    for (NSInteger row = 0; row < _tabTransform.numberOfRows; row++) {
        NSCell *cell = [_tabTransform cellAtRow:row column:0];
        const NSRect rowFrame = [_tabTransform convertRect:[_tabTransform cellFrameAtRow:row column:0]
                                                    toView:_tabTransform.superview];
        CGFloat room = NSWidth(rowFrame);
        if (NSMaxY(_spacesPerTab.frame) > NSMinY(rowFrame) && NSMinY(_spacesPerTab.frame) < NSMaxY(rowFrame)) {
            room = MIN(room, NSMinX(_spacesPerTab.frame) - NSMinX(rowFrame));
        }
        leftExtra = MAX(leftExtra, iTermPasteSpecialWidthNeeded(cell) - room);
    }
    CGFloat rightExtra = 0;
    for (NSButton *checkbox in rightCheckboxes) {
        rightExtra = MAX(rightExtra, iTermPasteSpecialShortfall(checkbox));
    }
    const CGFloat extra = MAX(leftExtra + rightExtra, iTermPasteSpecialShortfall(_waitForPrompts));
    if (extra > 0) {
        // Everything from the “with” label after the regex field rightward is in
        // the right column.
        const CGFloat rightColumnX = NSMaxX(_regex.frame);
        const CGFloat oldWidth = NSWidth(view.bounds);
        [self shiftSubviewsOf:view
                 rightColumnX:rightColumnX
                     oldWidth:oldWidth
                    leftExtra:leftExtra
                   rightExtra:rightExtra
                        extra:extra
                 replaceExtra:replaceExtra
               leftCheckboxes:leftCheckboxes
              rightCheckboxes:rightCheckboxes];
        // Keep the matrix's overlap with the spaces field what the nib had.
        NSRect matrixFrame = _tabTransform.frame;
        matrixFrame.size.width = NSMinX(_spacesPerTab.frame) + matrixOverlap - NSMinX(matrixFrame);
        _tabTransform.frame = matrixFrame;
        _tabTransform.cellSize = NSMakeSize(NSWidth(matrixFrame), _tabTransform.cellSize.height);

        NSRect frame = view.frame;
        frame.size.width += extra;
        view.frame = frame;
    }
    [self layoutSpeedLabels];
}

// Moves the subviews of `container` (the view or a terminal-mode enclosure in
// it, which share its coordinates) for -layoutForTranslations.
- (void)shiftSubviewsOf:(NSView *)container
           rightColumnX:(CGFloat)rightColumnX
               oldWidth:(CGFloat)oldWidth
              leftExtra:(CGFloat)leftExtra
             rightExtra:(CGFloat)rightExtra
                  extra:(CGFloat)extra
           replaceExtra:(CGFloat)replaceExtra
         leftCheckboxes:(NSArray<NSButton *> *)leftCheckboxes
        rightCheckboxes:(NSArray<NSButton *> *)rightCheckboxes {
    for (NSView *subview in container.subviews) {
        NSRect frame = subview.frame;
        if (subview.subviews.count > 0 && ![subview isKindOfClass:NSControl.class]) {
            // An enclosure: the full-width ones grow with the view; the one
            // holding the tab radio buttons grows with the left column.
            [self shiftSubviewsOf:subview
                     rightColumnX:rightColumnX
                         oldWidth:oldWidth
                        leftExtra:leftExtra
                       rightExtra:rightExtra
                            extra:extra
                     replaceExtra:replaceExtra
                   leftCheckboxes:leftCheckboxes
                  rightCheckboxes:rightCheckboxes];
            frame.size.width += (NSMaxX(frame) >= oldWidth - 4) ? extra : leftExtra;
        } else if (subview == _waitForPrompts) {
            frame.size.width += extra;
        } else if (subview == _spacesPerTab) {
            frame.origin.x += leftExtra;
        } else if (subview == _useRegexSubstitution) {
            frame.size.width += replaceExtra;
        } else if (subview == _regex) {
            frame.origin.x += replaceExtra;
            frame.size.width += leftExtra - replaceExtra;
        } else if ([leftCheckboxes containsObject:(NSButton *)subview]) {
            frame.size.width += leftExtra;
        } else if (NSMinX(frame) >= rightColumnX) {
            frame.origin.x += leftExtra;
            if ([rightCheckboxes containsObject:(NSButton *)subview] ||
                subview == _substitution ||
                NSMaxX(subview.frame) >= oldWidth - 0.5) {
                frame.size.width += rightExtra;
            }
        }
        subview.frame = frame;
    }
}

// Translated titles can be wider than the room the nib leaves before the
// value next to them.
- (void)layoutSpeedLabels {
    [_chunkSizeLabel it_moveToFollowTitle:_chunkSizeTitle gap:4];
    [_delayBetweenChunksLabel it_moveToFollowTitle:_delayBetweenChunksTitle gap:4];
}

- (void)setProfileType:(ProfileType)profileType {
    _profileType = profileType;
    NSSize shrinkage;
    (void)[self.view setVisibilityForTerminalEnclosures:!!(profileType & ProfileTypeTerminal)
                                      browserEnclosures:!!(profileType & ProfileTypeBrowser)
                                   hiddenModeEnclosures:[iTermAdvancedSettingsModel browserProfiles]
                               sharedProfilesEnclosures:false
                                           stateStorage:[NSMutableDictionary dictionary]
                                              shrinkage:&shrinkage];
    NSRect frame = self.view.frame;
    frame.size.height -= shrinkage.height;
    frame.size.width -= shrinkage.width;
    self.view.frame = frame;
}

- (NSString *)descriptionForByteSize:(double)chunkSize {
    return [iTermLocalizedUnitFormatter chunkSizeDescription:chunkSize
                                                    language:iTermLocalizedUnitFormatter.nonEnglishUILanguage];
}

- (NSString *)descriptionForDuration:(NSTimeInterval)duration {
    return [iTermLocalizedUnitFormatter durationDescription:duration
                                                   language:iTermLocalizedUnitFormatter.nonEnglishUILanguage];
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

- (BOOL)controlIsTransform:(NSControl *)control {
    return (control != _bracketedPasteMode &&
            control != _waitForPrompts &&
            control != _chunkSizeSlider &&
            control != _delayBetweenChunksSlider);
}

- (IBAction)settingChanged:(id)sender {
    _spacesPerTab.enabled = (_tabTransform.enabled &&
                             _tabTransform.selectedTag == kTabTransformConvertToSpaces);
    _convertNewlines.enabled = (_removeNewlines.state != NSControlStateValueOn);
    _regex.enabled = self.shouldUseRegexSubstitution;
    _substitution.enabled = self.shouldUseRegexSubstitution;
    if ([self controlIsTransform:sender]) {
        [_delegate pasteSpecialTransformDidChange];
    }
}

- (IBAction)stepperDidChange:(id)sender {
    NSStepper *stepper = sender;
    _spacesPerTab.integerValue = stepper.integerValue;
    [_delegate pasteSpecialTransformDidChange];
}

#pragma mark - NSTextField Delegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if ([notification object] == _regex || [notification object] == _substitution) {
        [_delegate pasteSpecialTransformDidChange];
    } else {
        _spacesPerTab.integerValue = MAX(0, MIN(100, _spacesPerTab.integerValue));
        _stepper.integerValue = _spacesPerTab.integerValue;
    }
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

- (void)setEnableRemoveNewlines:(BOOL)enableRemoveNewlines {
    _removeNewlines.enabled = enableRemoveNewlines;
}

- (BOOL)isRemoveNewlinesEnabled {
    return _removeNewlines.enabled;
}

- (void)setEnableConvertUnicodePunctuation:(BOOL)enableConvertUnicodePunctuation {
    _convertUnicodePunctuation.enabled = enableConvertUnicodePunctuation;
}

- (BOOL)isConvertUnicodePunctuationEnabled {
    return _convertUnicodePunctuation.enabled;
}

- (void)setShouldConvertUnicodePunctuation:(BOOL)shouldConvertUnicodePunctuation {
    _convertUnicodePunctuation.state = shouldConvertUnicodePunctuation ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldConvertUnicodePunctuation {
    return _convertUnicodePunctuation.state == NSControlStateValueOn;
}

- (void)setShouldConvertNewlines:(BOOL)shouldConvertNewlines {
    _convertNewlines.state = shouldConvertNewlines ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldConvertNewlines {
    return _convertNewlines.state == NSControlStateValueOn;
}

- (void)setShouldRemoveNewlines:(BOOL)shouldRemoveNewlines {
    _removeNewlines.state = shouldRemoveNewlines ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldRemoveNewlines {
    return _removeNewlines.state == NSControlStateValueOn;
}

- (void)setEnableEscapeShellCharsWithBackslash:(BOOL)enableEscapeShellCharsWithBackslash {
    _escapeShellCharsWithBackslash.enabled = enableEscapeShellCharsWithBackslash;
}

- (BOOL)isEscapeShellCharsWithBackslashEnabled {
    return _escapeShellCharsWithBackslash.enabled;
}

- (void)setShouldEscapeShellCharsWithBackslash:(BOOL)shouldEscapeShellCharsWithBackslash {
    _escapeShellCharsWithBackslash.state = shouldEscapeShellCharsWithBackslash ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldEscapeShellCharsWithBackslash {
    return _escapeShellCharsWithBackslash.state == NSControlStateValueOn;
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
    _removeControlCodes.state = shouldRemoveControlCodes ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldRemoveControlCodes {
    return _removeControlCodes.state == NSControlStateValueOn;
}

- (void)setEnableBracketedPaste:(BOOL)enableBracketedPaste {
    _bracketedPasteMode.enabled = enableBracketedPaste;
}

- (BOOL)isBracketedPasteEnabled {
    return _bracketedPasteMode.enabled;
}

- (void)setShouldUseBracketedPasteMode:(BOOL)shouldUseBracketedPasteMode {
    _bracketedPasteMode.state = shouldUseBracketedPasteMode ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldUseBracketedPasteMode {
    return _bracketedPasteMode.state == NSControlStateValueOn;
}

- (void)setEnableBase64:(BOOL)enableBase64 {
    _base64Encode.enabled = enableBase64;
}

- (BOOL)isBase64Enabled {
    return _base64Encode.enabled;
}

- (void)setShouldBase64Encode:(BOOL)shouldBase64Encode {
    _base64Encode.state = shouldBase64Encode ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)shouldBase64Encode {
    return _base64Encode.state == NSControlStateValueOn;
}

- (void)setEnableUseRegexSubstitution:(BOOL)enableRegexSubstitution {
    _useRegexSubstitution.enabled = enableRegexSubstitution;
}

- (BOOL)isUseRegexSubstitutionEnabled {
    return _useRegexSubstitution.enabled;
}

- (void)setShouldUseRegexSubstitution:(BOOL)shouldUseRegexSubstitution {
    _useRegexSubstitution.state = shouldUseRegexSubstitution ? NSControlStateValueOn : NSControlStateValueOff;
    _regex.enabled = shouldUseRegexSubstitution;
    _substitution.enabled = shouldUseRegexSubstitution;
}

- (BOOL)shouldUseRegexSubstitution {
    return _useRegexSubstitution.state == NSControlStateValueOn;
}

- (void)setEnableWaitForPrompt:(BOOL)enableWaitForPrompt {
    _waitForPrompts.enabled = enableWaitForPrompt;
}

- (BOOL)isWaitForPromptEnabled {
    return _waitForPrompts.enabled;
}

- (BOOL)shouldWaitForPrompt {
    return _waitForPrompts.state == NSControlStateValueOn;
}

- (void)setShouldWaitForPrompt:(BOOL)shouldWaitForPrompt {
    _waitForPrompts.state = shouldWaitForPrompt ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setSubstitutionString:(NSString *)substitutionString {
    _substitution.stringValue = substitutionString;
}

- (NSString *)substitutionString {
    return _substitution.stringValue;
}

- (void)setRegexString:(NSString *)regexString {
    _regex.stringValue = regexString;
}

- (NSString *)regexString {
    return _regex.stringValue;
}

- (NSString *)stringEncodedSettings {
    NSDictionary *dict =
        @{ kChunkSize: @(self.chunkSize),
           kDelayBetweenChunks: @(self.delayBetweenChunks),
           kNumberOfSpacesPerTab: @(self.numberOfSpacesPerTab),
           kSelectedTabTransform: @(self.selectedTabTransform),
           kShouldConvertNewlines: @(self.shouldConvertNewlines),
           kShouldRemoveNewlines: @(self.shouldRemoveNewlines),
           kShouldConvertUnicodePunctuation: @(self.shouldConvertUnicodePunctuation),
           kShouldEscapeShellCharsWithBackslash: @(self.shouldEscapeShellCharsWithBackslash),
           kShouldRemoveControlCodes: @(self.shouldRemoveControlCodes),
           kShouldUseBracketedPasteMode: @(self.shouldUseBracketedPasteMode),
           kShouldBase64Encode: @(self.shouldBase64Encode),
           kShouldUseRegexSubstitution: @(self.shouldUseRegexSubstitution),
           kRegularExpression: self.regexString ?: @"",
           kSubstitution: self.substitutionString ?: @"",
           kShouldWaitForPrompts: @(self.shouldWaitForPrompt)
         };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:0
                                                         error:nil];
    return [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
}

+ (NSString *)descriptionForCodedSettings:(NSString *)jsonString {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    iTermTabTransformTags tabTransform = [dict[kSelectedTabTransform] integerValue];
    NSMutableArray *components = [NSMutableArray array];

    if ([dict[kShouldBase64Encode] boolValue]) {
        [components addObject:@"Base64"];
    }
    if ([dict[kShouldWaitForPrompts] boolValue]) {
        [components addObject:@"WaitForPrompts"];
    }

    if (tabTransform == kTabTransformConvertToSpaces) {
        [components addObject:[NSString stringWithFormat:@"Tabs->%@ spcs", dict[kNumberOfSpacesPerTab]]];
    } else if (tabTransform == kTabTransformEscapeWithCtrlV) {
        [components addObject:@"^V+Tab"];
    }

    double delay = [dict[kDelayBetweenChunks] doubleValue];
    if (delay > 1) {
        [components addObject:@"V.Slow"];
    } else if (delay > 0.25) {
        [components addObject:@"Slow"];
    } else if ([dict[kChunkSize] integerValue] > 100000) {
        [components addObject:@"HugeChunks"];
    }

    if ([dict[kShouldEscapeShellCharsWithBackslash] boolValue]) {
        [components addObject:@"\\Escape"];
    }

    if (![dict[kShouldRemoveControlCodes] boolValue]) {
        [components addObject:@"UnsafeControls"];
    }

    if (![dict[kShouldUseBracketedPasteMode] boolValue]) {
        [components addObject:@"BracketingOff"];
    }

    if (![dict[kShouldConvertNewlines] boolValue]) {
        [components addObject:@"NoCRLFConversion"];
    }

    if ([dict[kShouldRemoveNewlines] boolValue]) {
        [components addObject:@"RemoveNewlines"];
    }

    if ([dict[kShouldConvertUnicodePunctuation] boolValue]) {
        [components addObject:@"ConvertPunctuation"];
    }

    if ([dict[kShouldUseRegexSubstitution] boolValue]) {
        [components addObject:[NSString stringWithFormat:@"s/%@/%@/g",
                               dict[kRegularExpression] ?: @"",
                               dict[kSubstitution] ?: @""]];
    }
    return [components componentsJoinedByString:@", "];
}

- (void)loadSettingsFromString:(NSString *)jsonString {
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];
    self.chunkSize = [dict[kChunkSize] integerValue];
    self.delayBetweenChunks = [dict[kDelayBetweenChunks] doubleValue];
    self.numberOfSpacesPerTab = [dict[kNumberOfSpacesPerTab] integerValue];
    self.selectedTabTransform = [dict[kSelectedTabTransform] integerValue];
    self.shouldConvertNewlines = [dict[kShouldConvertNewlines] boolValue];
    self.shouldRemoveNewlines = [dict[kShouldRemoveNewlines] boolValue];
    self.shouldConvertUnicodePunctuation = [dict[kShouldConvertUnicodePunctuation] boolValue];
    self.shouldEscapeShellCharsWithBackslash = [dict[kShouldEscapeShellCharsWithBackslash] boolValue];
    self.shouldRemoveControlCodes = [dict[kShouldRemoveControlCodes] boolValue];
    self.shouldUseBracketedPasteMode = [dict[kShouldUseBracketedPasteMode] boolValue];
    self.shouldBase64Encode = [dict[kShouldBase64Encode] boolValue];
    self.shouldUseRegexSubstitution = [dict[kShouldUseRegexSubstitution] boolValue];
    if (self.shouldUseRegexSubstitution) {
        self.regexString = dict[kRegularExpression] ?: @"";
        self.substitutionString = dict[kSubstitution] ?: @"";
    }
    self.shouldWaitForPrompt = [dict[kShouldWaitForPrompts] boolValue];
}

+ (PasteEvent *)pasteEventForConfig:(NSString *)jsonConfig string:(NSString *)string {
    NSData *jsonData = [jsonConfig dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL];

    int chunkSize = [dict[kChunkSize] integerValue];
    NSTimeInterval delayBetweenChunks = [dict[kDelayBetweenChunks] doubleValue];
    int numberOfSpacesPerTab = [dict[kNumberOfSpacesPerTab] integerValue];
    iTermTabTransformTags selectedTabTransform = [dict[kSelectedTabTransform] integerValue];
    BOOL shouldConvertNewlines = [dict[kShouldConvertNewlines] boolValue];
    BOOL shouldRemoveNewlines = [dict[kShouldRemoveNewlines] boolValue];
    BOOL shouldEscapeShellCharsWithBackslash = [dict[kShouldEscapeShellCharsWithBackslash] boolValue];
    BOOL shouldRemoveControlCodes = [dict[kShouldRemoveControlCodes] boolValue];
    BOOL shouldUseBracketedPasteMode = [dict[kShouldUseBracketedPasteMode] boolValue];
    BOOL shouldBase64Encode = [dict[kShouldBase64Encode] boolValue];
    BOOL shouldUseRegexSubstitution = [dict[kShouldUseRegexSubstitution] boolValue];
    BOOL shouldWaitForPrompt = [dict[kShouldWaitForPrompts] boolValue];
    BOOL shouldConvertUnicodePunctuation = [dict[kShouldConvertUnicodePunctuation] boolValue];

    NSUInteger flags = 0;
    if (shouldConvertNewlines) {
        flags |= kPasteFlagsSanitizingNewlines;
    }
    if (shouldRemoveNewlines) {
        flags |= kPasteFlagsRemovingNewlines;
    }
    if (shouldEscapeShellCharsWithBackslash) {
        flags |= kPasteFlagsEscapeSpecialCharacters;
    }
    if (shouldRemoveControlCodes) {
        flags |= kPasteFlagsRemovingUnsafeControlCodes;
    }
    if (shouldUseBracketedPasteMode) {
        flags |= kPasteFlagsBracket;
    }
    if (shouldBase64Encode) {
        flags |= kPasteFlagsBase64Encode;
    }
    if (shouldWaitForPrompt) {
        flags |= kPasteFlagsCommands;
    }
    if (shouldConvertUnicodePunctuation) {
        flags |= kPasteFlagsConvertUnicodePunctuation;
    }
    if (shouldUseRegexSubstitution) {
        flags |= kPasteFlagsUseRegexSubstitution;
    }
    PasteEvent *pasteEvent = [PasteEvent pasteEventWithString:string
                                                        flags:flags
                                             defaultChunkSize:chunkSize
                                                     chunkKey:nil
                                                 defaultDelay:delayBetweenChunks
                                                     delayKey:nil
                                                 tabTransform:selectedTabTransform
                                                 spacesPerTab:numberOfSpacesPerTab
                                                        regex:dict[kRegularExpression] ?: @""
                                                 substitution:dict[kSubstitution] ?: @""
                           shouldPasteNewlinesOutsideBrackets:NO];
    return pasteEvent;
}

- (iTermPasteFlags)flags {
    NSUInteger flags = 0;
    if (self.shouldConvertNewlines) {
        flags |= kPasteFlagsSanitizingNewlines;
    }
    if (self.shouldRemoveNewlines) {
        flags |= kPasteFlagsRemovingNewlines;
    }
    if (self.shouldEscapeShellCharsWithBackslash) {
        flags |= kPasteFlagsEscapeSpecialCharacters;
    }
    if (self.shouldRemoveControlCodes) {
        flags |= kPasteFlagsRemovingUnsafeControlCodes;
    }
    if (self.shouldUseBracketedPasteMode) {
        flags |= kPasteFlagsBracket;
    }
    if (self.shouldBase64Encode) {
        flags |= kPasteFlagsBase64Encode;
    }
    if (self.shouldWaitForPrompt) {
        flags |= kPasteFlagsCommands;
    }
    if (self.shouldConvertUnicodePunctuation) {
        flags |= kPasteFlagsConvertUnicodePunctuation;
    }
    if (self.shouldUseRegexSubstitution) {
        flags |= kPasteFlagsUseRegexSubstitution;
    }
    return flags;
}

@end
