//
//  VT100ScreenConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenConfiguration.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"

@interface VT100ScreenConfiguration()
@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readwrite) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readwrite) BOOL isDirty;
@property (nonatomic, readwrite) BOOL isTmuxClient;
@property (nonatomic, readwrite) BOOL printingAllowed;
@property (nonatomic, readwrite) BOOL clipboardAccessAllowed;
@property (nonatomic, readwrite) BOOL miniaturized;
@property (nonatomic, readwrite) NSRect windowFrame;
@property (nonatomic, readwrite) VT100GridSize theoreticalGridSize;
@property (nonatomic, copy, readwrite) NSString *iconTitle;
@property (nonatomic, copy, readwrite) NSString *windowTitle;
@property (nonatomic, readwrite) BOOL clearScrollbackAllowed;
@property (nonatomic, copy, readwrite) NSString *profileName;
@property (nonatomic, readwrite) NSSize cellSize;
@property (nonatomic, readwrite) CGFloat backingScaleFactor;
@property (nonatomic, readwrite) int maximumTheoreticalImageDimension;
@property (nonatomic, readwrite) BOOL dimOnlyText;
@property (nonatomic, readwrite) BOOL darkMode;
@property (nonatomic, readwrite) BOOL useSeparateColorsForLightAndDarkMode;
@property (nonatomic, readwrite) float minimumContrast;
@property (nonatomic, readwrite) float faintTextAlpha;
@property (nonatomic, readwrite) double mutingAmount;
@property (nonatomic, readwrite) iTermUnicodeNormalization normalization;
@property (nonatomic, readwrite) BOOL appendToScrollbackWithStatusBar;
@property (nonatomic, readwrite) BOOL saveToScrollbackInAlternateScreen;
@property (nonatomic, readwrite) BOOL unlimitedScrollback;
@property (nonatomic, readwrite) BOOL reduceFlicker;
@property (nonatomic, readwrite) int maxScrollbackLines;
@property (nonatomic, readwrite) BOOL loggingEnabled;
@property (nonatomic, copy, readwrite) NSDictionary<NSNumber *, id> *stringForKeypress;
@property (nonatomic, readwrite) BOOL alertOnNextMark;
@property (nonatomic, readwrite) double dimmingAmount;
@property (nonatomic, readwrite) BOOL publishing;
@property (nonatomic, readwrite) BOOL terminalCanChangeBlink;
@property (nonatomic, strong, readwrite, nullable) NSNumber *desiredComposerRows;
@property (nonatomic, readwrite) BOOL autoComposerEnabled;
@property (nonatomic, readwrite) BOOL useLineStyleMarks;
@end

@implementation VT100ScreenConfiguration

@synthesize shouldPlacePromptAtFirstColumn = _shouldPlacePromptAtFirstColumn;
@synthesize sessionGuid = _sessionGuid;
@synthesize treatAmbiguousCharsAsDoubleWidth = _treatAmbiguousCharsAsDoubleWidth;
@synthesize unicodeVersion = _unicodeVersion;
@synthesize enableTriggersInInteractiveApps = _enableTriggersInInteractiveApps;
@synthesize triggerParametersUseInterpolatedStrings = _triggerParametersUseInterpolatedStrings;
@synthesize triggerProfileDicts = _triggerProfileDicts;
@synthesize isTmuxClient = _isTmuxClient;
@synthesize printingAllowed = _printingAllowed;
@synthesize clipboardAccessAllowed = _clipboardAccessAllowed;
@synthesize miniaturized = _miniaturized;
@synthesize windowFrame = _windowFrame;
@synthesize theoreticalGridSize = _theoreticalGridSize;
@synthesize iconTitle = _iconTitle;
@synthesize windowTitle = _windowTitle;
@synthesize clearScrollbackAllowed = _clearScrollbackAllowed;
@synthesize profileName = _profileName;
@synthesize cellSize = _cellSize;
@synthesize backingScaleFactor = _backingScaleFactor;
@synthesize maximumTheoreticalImageDimension = _maximumTheoreticalImageDimension;
@synthesize dimOnlyText = _dimOnlyText;
@synthesize darkMode = _darkMode;
@synthesize useSeparateColorsForLightAndDarkMode = _useSeparateColorsForLightAndDarkMode;
@synthesize minimumContrast = _minimumContrast;
@synthesize faintTextAlpha = _faintTextAlpha;
@synthesize mutingAmount = _mutingAmount;
@synthesize normalization = _normalization;
@synthesize appendToScrollbackWithStatusBar = _appendToScrollbackWithStatusBar;
@synthesize saveToScrollbackInAlternateScreen = _saveToScrollbackInAlternateScreen;
@synthesize unlimitedScrollback = _unlimitedScrollback;
@synthesize reduceFlicker = _reduceFlicker;
@synthesize maxScrollbackLines = _maxScrollbackLines;
@synthesize loggingEnabled = _loggingEnabled;
@synthesize alertOnNextMark = _alertOnNextMark;
@synthesize dimmingAmount = _dimmingAmount;
@synthesize publishing = _publishing;
@synthesize terminalCanChangeBlink = _terminalCanChangeBlink;
@synthesize desiredComposerRows = _desiredComposerRows;
@synthesize autoComposerEnabled = _autoComposerEnabled;
@synthesize useLineStyleMarks = _useLineStyleMarks;

@synthesize isDirty = _isDirty;
@synthesize stringForKeypress = _stringForKeypress;

- (instancetype)initFrom:(VT100ScreenConfiguration *)other {
    self = [super init];
    if (self) {
        _shouldPlacePromptAtFirstColumn = other.shouldPlacePromptAtFirstColumn;
        _sessionGuid = other.sessionGuid;
        _treatAmbiguousCharsAsDoubleWidth = other.treatAmbiguousCharsAsDoubleWidth;
        _unicodeVersion = other.unicodeVersion;
        _enableTriggersInInteractiveApps = other.enableTriggersInInteractiveApps;
        _triggerParametersUseInterpolatedStrings = other.triggerParametersUseInterpolatedStrings;
        _triggerProfileDicts = [other.triggerProfileDicts copy];
        _isTmuxClient = other.isTmuxClient;
        _printingAllowed = other.printingAllowed;
        _clipboardAccessAllowed = other.clipboardAccessAllowed;
        _miniaturized = other.miniaturized;
        _windowFrame = other.windowFrame;
        _theoreticalGridSize = other.theoreticalGridSize;
        _iconTitle = other.iconTitle;
        _windowTitle = other.windowTitle;
        _clearScrollbackAllowed = other.clearScrollbackAllowed;
        _profileName = other.profileName;
        _cellSize = other.cellSize;
        _backingScaleFactor = other.backingScaleFactor;
        _maximumTheoreticalImageDimension = other.maximumTheoreticalImageDimension;
        _dimOnlyText = other.dimOnlyText;
        _darkMode = other.darkMode;
        _useSeparateColorsForLightAndDarkMode = other.useSeparateColorsForLightAndDarkMode;
        _minimumContrast = other.minimumContrast;
        _faintTextAlpha = other.faintTextAlpha;
        _mutingAmount = other.mutingAmount;
        _normalization = other.normalization;
        _appendToScrollbackWithStatusBar = other.appendToScrollbackWithStatusBar;
        _saveToScrollbackInAlternateScreen = other.saveToScrollbackInAlternateScreen;
        _unlimitedScrollback = other.unlimitedScrollback;
        _reduceFlicker = other.reduceFlicker;
        _maxScrollbackLines = other.maxScrollbackLines;
        _loggingEnabled = other.loggingEnabled;
        _stringForKeypress = other.stringForKeypress;
        _alertOnNextMark = other.alertOnNextMark;
        _dimmingAmount = other.dimmingAmount;
        _publishing = other.publishing;
        _terminalCanChangeBlink = other.terminalCanChangeBlink;
        _desiredComposerRows = other.desiredComposerRows;
        _autoComposerEnabled = other.autoComposerEnabled;
        _useLineStyleMarks = other.useLineStyleMarks;

        _isDirty = other.isDirty;
    }
    return self;
}

- (id)copy {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    NSDictionary *dict = @{ @"shouldPlacePromptAtFirstColumn": @(_shouldPlacePromptAtFirstColumn),
                            @"sessionGuid": _sessionGuid ?: @"(nil)",
                            @"treatAmbiguousCharsAsDoubleWidth": @(_treatAmbiguousCharsAsDoubleWidth),
                            @"unicodeVersion": @(_unicodeVersion),
                            @"enableTriggersInInteractiveApps": @(_enableTriggersInInteractiveApps),
                            @"triggerParametersUseInterpolatedStrings": @(_triggerParametersUseInterpolatedStrings),
                            @"triggerProfileDicts (count)": @(_triggerProfileDicts.count),
                            @"isTmuxClient": @(_isTmuxClient),
                            @"printingAllowed": @(_printingAllowed),
                            @"clipboardAccessAllowed": @(_clipboardAccessAllowed),
                            @"miniaturized": @(_miniaturized),
                            @"windowFrame": @(_windowFrame),
                            @"theoreticalGridSize": VT100GridSizeDescription(_theoreticalGridSize),
                            @"iconTitle": _iconTitle ?: @"",
                            @"windowTitle": _windowTitle ?: @"",
                            @"clearScrollbackAllowed": @(_clearScrollbackAllowed),
                            @"profileName": _profileName ?: @"",
                            @"cellSize": NSStringFromSize(_cellSize),
                            @"backingScaleFactor": @(_backingScaleFactor),
                            @"maximumTheoreticalImageDimension": @(_maximumTheoreticalImageDimension),
                            @"dimOnlyText": @(_dimOnlyText),
                            @"darkMode": @(_darkMode),
                            @"useSeparateColorsForLightAndDarkMode": @(_useSeparateColorsForLightAndDarkMode),
                            @"minimumContrast": @(_minimumContrast),
                            @"faintTextAlpha": @(_faintTextAlpha),
                            @"mutingAmount": @(_mutingAmount),
                            @"normalization": @(_normalization),
                            @"appendToScrollbackWithStatusBar": @(_appendToScrollbackWithStatusBar),
                            @"saveToScrollbackInAlternateScreen": @(_saveToScrollbackInAlternateScreen),
                            @"unlimitedScrollback": @(_unlimitedScrollback),
                            @"reduceFlicker": @(_reduceFlicker),
                            @"maxScrollbackLines": @(_maxScrollbackLines),
                            @"loggingEnabled": @(_loggingEnabled),
                            @"stringForKeypress": _stringForKeypress ?: @"",
                            @"alertOnNextMark": @(_alertOnNextMark),
                            @"dimmingAmount": @(_dimmingAmount),
                            @"publishing": @(_publishing),
                            @"terminalCanChangeBlink": @(_terminalCanChangeBlink),
                            @"desiredComposerRows": _desiredComposerRows ?: [NSNull null],
                            @"autoComposerEnabled": @(_autoComposerEnabled),
                            @"useLineStyleMarks": @(_useLineStyleMarks),

                            @"isDirty": @(_isDirty),
    };
    dict = [dict dictionaryByRemovingNullValues];

    NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *kvps = [keys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"    %@=%@", key, dict[key]];
    }];
    NSString *values = [kvps componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"<%@: %p\n%@>", NSStringFromClass([self class]), self, values];
}
@end

@implementation VT100MutableScreenConfiguration {
    NSMutableSet<NSString *> *_dirtyKeyPaths;
}

@dynamic shouldPlacePromptAtFirstColumn;
@dynamic sessionGuid;
@dynamic treatAmbiguousCharsAsDoubleWidth;
@dynamic unicodeVersion;
@dynamic enableTriggersInInteractiveApps;
@dynamic triggerParametersUseInterpolatedStrings;
@dynamic triggerProfileDicts;
@dynamic isTmuxClient;
@dynamic printingAllowed;
@dynamic clipboardAccessAllowed;
@dynamic miniaturized;
@dynamic windowFrame;
@dynamic theoreticalGridSize;
@dynamic iconTitle;
@dynamic windowTitle;
@dynamic clearScrollbackAllowed;
@dynamic profileName;
@dynamic cellSize;
@dynamic backingScaleFactor;
@dynamic maximumTheoreticalImageDimension;
@dynamic dimOnlyText;
@dynamic darkMode;
@dynamic useSeparateColorsForLightAndDarkMode;
@dynamic minimumContrast;
@dynamic faintTextAlpha;
@dynamic mutingAmount;
@dynamic normalization;
@dynamic appendToScrollbackWithStatusBar;
@dynamic saveToScrollbackInAlternateScreen;
@dynamic unlimitedScrollback;
@dynamic reduceFlicker;
@dynamic maxScrollbackLines;
@dynamic loggingEnabled;
@dynamic stringForKeypress;
@dynamic alertOnNextMark;
@dynamic dimmingAmount;
@dynamic publishing;
@dynamic terminalCanChangeBlink;
@dynamic desiredComposerRows;
@dynamic autoComposerEnabled;
@dynamic useLineStyleMarks;

@dynamic isDirty;

static char VT100MutableScreenConfigurationKVOKey;

- (instancetype)init {
    self = [super init];
    if (self) {
        _dirtyKeyPaths = [NSMutableSet set];
        [VT100MutableScreenConfiguration it_enumerateDynamicProperties:^(NSString * _Nonnull name) {
            [self addObserver:self
                   forKeyPath:name
                      options:NSKeyValueObservingOptionNew
                      context:&VT100MutableScreenConfigurationKVOKey];
        }];
    }
    return self;
}

- (void)dealloc {
    [VT100MutableScreenConfiguration it_enumerateDynamicProperties:^(NSString * _Nonnull selectorString) {
        [self removeObserver:self
                  forKeyPath:selectorString];
    }];
}

- (id)copy {
    return [self copyWithZone:nil];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenConfiguration alloc] initFrom:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &VT100MutableScreenConfigurationKVOKey) {
        [_dirtyKeyPaths addObject:keyPath];
    }
}

- (NSSet<NSString *> *)dirtyKeyPaths {
    NSSet<NSString *> *result = [_dirtyKeyPaths copy];
    [_dirtyKeyPaths removeAllObjects];
    return result;
}

@end


NSDictionary *VT100ScreenConfigKeypressIdentifier(unsigned short keyCode,
                                                  NSEventModifierFlags flags,
                                                  NSString *characters,
                                                  NSString *charactersIgnoringModifiers) {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagCommand |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagFunction |
                                       NSEventModifierFlagNumericPad);
    return @{ @"keyCode": @(keyCode),
              @"flags": @(flags & mask),
              @"characters": characters ?: @"",
              @"charactersIgnoringModifiers": charactersIgnoringModifiers ?: @""
    };
}
