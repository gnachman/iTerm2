//
//  iTermStatusBarRPCProvidedTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/18.
//

#import "iTermStatusBarRPCProvidedTextComponent.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermExpressionParser.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermObject.h"
#import "iTermScriptFunctionCall.h"
#import "iTermScriptHistory.h"
#import "iTermScriptsMenuController.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermStatusBarRPCProvidedComponentHelper.h"
#import "iTermVariableScope.h"
#import "iTermVariableReference.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat iTermStatusBarRPCProvidedLineGraphComponentMinimumWidth = 120;

@implementation iTermStatusBarRPCComponentFactory {
    ITMRPCRegistrationRequest *_savedRegistrationRequest;
    // NOTE: If mutable state is added, change copyWithZone:
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest {
    self = [super init];
    if (self) {
        _savedRegistrationRequest = registrationRequest;
   }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        NSData *data = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"registrationRequest"];
        if (!data) {
            return nil;
        }
        _savedRegistrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data error:nil];
        if (!_savedRegistrationRequest) {
            return nil;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_savedRegistrationRequest.data forKey:@"registrationRequest"];
}

- (NSString *)componentDescription {
    return _savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.shortDescription;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (NSDictionary *)defaultKnobs {
    NSMutableDictionary *knobs = [NSMutableDictionary dictionary];
    [_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.knobsArray enumerateObjectsUsingBlock:^(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id value = [NSJSONSerialization it_objectForJsonString:obj.jsonDefaultValue];
        if (value) {
            knobs[obj.key] = value;
        }
    }];
    return [knobs copy];
}

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs
                                     layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                               scope:(iTermVariableScope *)scope {
    Class theClass = nil;
    switch (_savedRegistrationRequest.latestStatusBarRequest.statusBarComponentAttributes.type) {
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Type_LineGraph:
            theClass = [iTermStatusBarRPCProvidedLineGraphComponent class];
            break;
        case ITMRPCRegistrationRequest_StatusBarComponentAttributes_Type_Text:
            theClass = [iTermStatusBarRPCProvidedTextComponent class];
            break;
    }
    return [[theClass alloc] initWithRegistrationRequest:_savedRegistrationRequest.latestStatusBarRequest
                                                   scope:scope
                                                   knobs:knobs];
}

@end


@implementation iTermStatusBarRPCProvidedTextComponent {
    NSArray<NSString *> *_variants;
    iTermStatusBarRPCProvidedComponentHelper *_helper;
}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    NSDictionary *configuration = @{ iTermStatusBarRPCRegistrationRequestKey: registrationRequest.data,
                                     iTermStatusBarComponentConfigurationKeyKnobValues: knobs };
    return [self initWithConfiguration:configuration scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey];
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    __weak __typeof(self) weakSelf = self;
    iTermStatusBarRPCProvidedComponentHelper *helper =
    [[iTermStatusBarRPCProvidedComponentHelper alloc] initWithConfiguration:configuration
                                                                      scope:scope
                                                                updateBlock:^{
                                                                    [weakSelf rpcUpdate];
                                                                }
                                                                reloadBlock:^{
                                                                    [weakSelf statusBarComponentUpdate];
                                                                }
                                                                  evalBlock:^(id _Nullable value,
                                                                              NSError * _Nullable error,
                                                                              NSSet<NSString *> * _Nullable missingFunctions) {
                                                                      [weakSelf didEvaluate:value
                                                                                      error:error
                                                                           missingFunctions:missingFunctions];
                                                                  }
                                                             windowProvider:^NSWindow * _Nonnull {
                                                                 return weakSelf.textField.window;
                                                             }];
    if (!helper) {
        return nil;
    }
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _helper = helper;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rpcUpdate {
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (NSString *)statusBarComponentIdentifier {
    // Old (prerelease) ones did not have a unique identifier so assign one to prevent disaster.
    return _helper.identifier;
}

- (NSTextField *)newTextField {
    NSTextField *textField = [super newTextField];
    NSClickGestureRecognizer *recognizer = [[NSClickGestureRecognizer alloc] init];
    recognizer.buttonMask = 1;
    recognizer.numberOfClicksRequired = 1;
    recognizer.target = self;
    recognizer.action = @selector(onClick:);
    [textField addGestureRecognizer:recognizer];
    return textField;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return _helper.factory;
}

- (NSString *)statusBarComponentShortDescription {
    return _helper.shortDescription;
}

- (NSString *)statusBarComponentDetailedDescription {
    return _helper.detailedDescriptor;
}

- (void)statusBarComponentUpdate {
    [self updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (nullable NSImage *)statusBarComponentIcon {
    return _helper.icon;
}

- (iTermStatusBarComponentKnobType)knobTypeFromDescriptorType:(ITMRPCRegistrationRequest_StatusBarComponentAttributes_Knob_Type)type {
    return [_helper knobTypeFromDescriptorType:type];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [_helper knobsWith:[super statusBarComponentKnobs]];
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return [_helper exemplarWithBackgroundColor:backgroundColor
                                      textColor:textColor];
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return _variants ?: @[ @"" ];
}

- (void)updateWithKnobValues:(NSDictionary<NSString *, id> *)knobValues {
    [_helper updateWithKnobValues:knobValues];
}

- (void)didEvaluate:(id)value
              error:(NSError *)error
   missingFunctions:(NSSet<NSString *> *)missingFunctions {
    if (value) {
        [self handleSuccessfulEvaluation:value];
        return;
    }
    if (error) {
        [self handleEvaluationError:error missingFunctions:missingFunctions];
    }
}

- (void)handleSuccessfulEvaluation:(id)value {
    NSString *stringValue = [NSString castFrom:value];
    NSArray *arrayValue = [NSArray castFrom:value];
    _helper.errorMessage = nil;
    if (stringValue) {
        _variants = @[ stringValue ];
    } else if ([arrayValue allWithBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[NSString class]];
    }]) {
        _variants = arrayValue;
    } else {
        [_helper logInvalidValue:[NSString stringWithFormat:@"Return value from %@ invalid.\n\nIt should have returned a string or a list of strings.\n\nInstead, it returned:\n\n%@", _helper.invocation, value]];
        _variants = @[ @"🐞" ];
    }
    [self updateTextFieldIfNeeded];
}

- (void)handleEvaluationError:(NSError *)error
             missingFunctions:(NSSet<NSString *> *)missingFunctions {
    _variants = @[ @"🐞" ];
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    [self updateWithKnobValues:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return _helper.cadence;
}

- (nullable NSString *)fullPathOfScript {
    return _helper.fullPathOfScript;
}

- (void)onClick:(id)sender {
    [_helper onClick:sender];
}

@end

@implementation iTermStatusBarRPCProvidedLineGraphComponent {
    NSArray *_values;
    iTermStatusBarRPCProvidedComponentHelper *_helper;
    NSString *_leftText;
    NSString *_rightText;
    NSString *_longestLeftText;

    NSInteger _maximumNumberOfValues;
    NSInteger _numberOfTimeSeries;
    NSArray<NSColor *> *_lineColors;

}

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs {
    NSDictionary *configuration = @{ iTermStatusBarRPCRegistrationRequestKey: registrationRequest.data,
                                     iTermStatusBarComponentConfigurationKeyKnobValues: knobs };
    return [self initWithConfiguration:configuration scope:scope];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    NSData *data = configuration[iTermStatusBarRPCRegistrationRequestKey];
    ITMRPCRegistrationRequest *registrationRequest = [[ITMRPCRegistrationRequest alloc] initWithData:data
                                                                                               error:nil];
    if (!registrationRequest) {
        return nil;
    }
    __weak __typeof(self) weakSelf = self;
    iTermStatusBarRPCProvidedComponentHelper *helper =
    [[iTermStatusBarRPCProvidedComponentHelper alloc] initWithConfiguration:configuration
                                                                      scope:scope
                                                                updateBlock:^{
                                                                    [weakSelf rpcUpdate];
                                                                }
                                                                reloadBlock:^{
                                                                    [weakSelf statusBarComponentUpdate];
                                                                }
                                                                  evalBlock:^(id _Nullable value,
                                                                              NSError * _Nullable error,
                                                                              NSSet<NSString *> * _Nullable missingFunctions) {
                                                                      [weakSelf didEvaluate:value
                                                                                      error:error
                                                                           missingFunctions:missingFunctions];
                                                                  }
                                                             windowProvider:^NSWindow * _Nonnull {
                                                                 return weakSelf.view.window;
                                                             }];
    if (!helper) {
        return nil;
    }
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        _helper = helper;
        _maximumNumberOfValues = registrationRequest.statusBarComponentAttributes.lineGraphSetting.maximumNumberOfValues;
        _numberOfTimeSeries = registrationRequest.statusBarComponentAttributes.lineGraphSetting.numberOfSeries;
        _lineColors = [registrationRequest.statusBarComponentAttributes.lineGraphSetting.lineConfigsArray mapWithBlock:^id(ITMRPCRegistrationRequest_StatusBarComponentAttributes_LineGraphSetting_Config *anObject) {
            NSColorSpace *colorSpace = nil;
            if ([anObject.color.colorSpace isEqualToString:@"sRGB"]) {
                colorSpace = [NSColorSpace sRGBColorSpace];
            } else if ([anObject.color.colorSpace isEqualToString:@"Calibrated"]) {
                colorSpace = [NSColorSpace deviceRGBColorSpace];
            }
            if (colorSpace) {
                CGFloat components[] = {
                    anObject.color.red,
                    anObject.color.green,
                    anObject.color.blue,
                    anObject.color.alpha
                };
                return [NSColor colorWithColorSpace:colorSpace components:components count:sizeof(components) / sizeof(*components)];
            } else {
                return nil;
            }
        }];
    }
    return self;
}

- (NSInteger)maximumNumberOfValues {
    return _maximumNumberOfValues;
}

- (NSInteger)numberOfTimeSeries {
    return _numberOfTimeSeries;
}

- (NSArray<NSColor *> *)lineColors {
    return _lineColors;
}

- (void)rpcUpdate {
    [_helper updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (void)didEvaluate:(id)value
              error:(NSError *)error
   missingFunctions:(NSSet<NSString *> *)missingFunctions {
    if (value) {
        [self handleSuccessfulEvaluation:value];
        return;
    }
    if (error) {
        [self handleEvaluationError:error missingFunctions:missingFunctions];
    }
}

- (void)handleSuccessfulEvaluation:(id)value {
    NSDictionary *dictionaryValue = [NSDictionary castFrom:value];
    _helper.errorMessage = nil;
    if (dictionaryValue) {
        NSArray<NSArray<NSNumber *> *> *values = dictionaryValue[@"values"];
        _leftText = [dictionaryValue[@"leftText"] nilIfNull];
        _longestLeftText = [dictionaryValue[@"longestLeftText"] nilIfNull];
        _rightText = [dictionaryValue[@"rightText"] nilIfNull];
        const NSInteger numberOfSeries = self.numberOfTimeSeries;
        _values = [values filteredArrayUsingBlock:^BOOL(NSArray<NSNumber *> *tuple) {
            if (tuple.count != numberOfSeries) {
                return NO;
            }
            return [tuple allWithBlock:^BOOL(NSNumber *value) {
                return [value isKindOfClass:[NSNumber class]];
            }];
        }];
    } else {
        [_helper logInvalidValue:[NSString stringWithFormat:@"Return value from %@ invalid.\n\nIt should have returned a dictionary.\n\nInstead, it returned:\n\n%@", _helper.invocation, value]];
        _values = nil;
    }
    [self invalidate];
}

- (void)handleEvaluationError:(NSError *)error
             missingFunctions:(NSSet<NSString *> *)missingFunctions {
    _values = nil;
}

- (NSImage *)statusBarComponentIcon {
    return _helper.icon;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return _helper.factory;
}

- (NSString *)statusBarComponentShortDescription {
    return _helper.shortDescription;
}

- (NSString *)statusBarComponentDetailedDescription {
    return _helper.detailedDescriptor;
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return [_helper exemplarWithBackgroundColor:backgroundColor
                                      textColor:textColor];
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (void)statusBarComponentUpdate {
    [_helper updateWithKnobValues:self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return _helper.cadence;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return iTermStatusBarRPCProvidedLineGraphComponentMinimumWidth;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return iTermStatusBarRPCProvidedLineGraphComponentMinimumWidth;
}

- (NSArray<NSArray<NSNumber *> *> *)values {
    return _values;
}

- (void)drawTextWithRect:(NSRect)rect
                    left:(NSString *)left
                   right:(NSString *)right
               rightSize:(CGSize)rightSize {
    NSRect textRect = rect;
    textRect.size.height = rightSize.height;
    textRect.origin.y = [self textOffset];
    [left drawInRect:textRect withAttributes:[self.leftAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
    [right drawInRect:textRect withAttributes:[self.rightAttributes it_attributesDictionaryWithAppearance:self.view.effectiveAppearance]];
}

- (NSRect)graphRectForRect:(NSRect)rect
                  leftSize:(CGSize)leftSize
                 rightSize:(CGSize)rightSize {
    NSRect graphRect = rect;
    const CGFloat margin = 4;
    CGFloat rightWidth = rightSize.width + margin;
    CGFloat leftWidth = leftSize.width + margin;
    graphRect.origin.x += leftWidth;
    graphRect.size.width -= (leftWidth + rightWidth);
    graphRect = NSInsetRect(graphRect, 0, [self.view retinaRound:-self.font.descender] + self.statusBarComponentVerticalOffset);

    return graphRect;
}

- (NSFont *)font {
    return self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
}

- (NSDictionary *)leftAttributes {
    NSMutableParagraphStyle *leftAlignStyle =
    [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [leftAlignStyle setAlignment:NSTextAlignmentLeft];
    [leftAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];

    return @{ NSParagraphStyleAttributeName: leftAlignStyle,
              NSFontAttributeName: self.font,
              NSForegroundColorAttributeName: self.textColor };
}

- (NSDictionary *)rightAttributes {
    NSMutableParagraphStyle *rightAlignStyle =
    [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [rightAlignStyle setAlignment:NSTextAlignmentRight];
    [rightAlignStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    return @{ NSParagraphStyleAttributeName: rightAlignStyle,
              NSFontAttributeName: self.font,
              NSForegroundColorAttributeName: self.textColor };
}

- (CGFloat)textOffset {
    NSFont *font = self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    const CGFloat containerHeight = self.view.superview.bounds.size.height;
    const CGFloat capHeight = font.capHeight;
    const CGFloat descender = font.descender - font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - self.view.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    return origin;
}

- (NSSize)leftSize {
    NSString *longestPercentage = _longestLeftText;
    return [longestPercentage sizeWithAttributes:self.leftAttributes];
}

- (CGSize)rightSize {
    return [_rightText sizeWithAttributes:self.rightAttributes];
}

- (NSString *)leftText {
    return _leftText;
}

- (NSString *)rightText {
    return _rightText;
}

- (void)drawRect:(NSRect)rect {
    CGSize rightSize = self.rightSize;

    [self drawTextWithRect:rect
                      left:self.leftText
                     right:self.rightText
                 rightSize:rightSize];

    NSRect graphRect = [self graphRectForRect:rect leftSize:self.leftSize rightSize:rightSize];

    [super drawRect:graphRect];
}

#pragma mark - Private

- (void)update:(double)value {
    [self invalidate];
}

@end

NS_ASSUME_NONNULL_END
