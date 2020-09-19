//
//  iTermStatusBarBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarBaseComponent.h"

#import "DebugLogging.h"
#import "iTermAPIHelper.h"
#import "iTermPreferences.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarSetupKnobsViewController.h"
#import "iTermWebViewWrapperViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarCompressionResistanceKey = @"base: compression resistance";
NSString *const iTermStatusBarPriorityKey = @"base: priority";
NSString *const iTermStatusBarMaximumWidthKey = @"maxwidth";
NSString *const iTermStatusBarMinimumWidthKey = @"minwidth";
const double iTermStatusBarBaseComponentDefaultPriority = 5;

@implementation iTermStatusBarBuiltInComponentFactory {
    Class _class;
    // NOTE: If mutable state is added update copyWithZone:
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithClass:(Class)theClass {
    self = [super init];
    if (self) {
        _class = theClass;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        NSString *className = [aDecoder decodeObjectOfClass:[NSString class]
                                                     forKey:@"class"] ?: @"";
        _class = NSClassFromString(className);
        if (!_class) {
            return nil;
        }
    }
    return self;
}

- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs
                                     layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                               scope:(iTermVariableScope *)scope {
    iTermStatusBarAdvancedConfiguration *advancedConfiguration = [[iTermStatusBarAdvancedConfiguration alloc] init];
    advancedConfiguration.layoutAlgorithm = layoutAlgorithm;
    return [[_class alloc] initWithConfiguration:@{iTermStatusBarComponentConfigurationKeyKnobValues: knobs,
                                                   iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue: advancedConfiguration.dictionaryValue }
                                           scope:scope];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:NSStringFromClass(_class) ?: @"" forKey:@"class"];
}

- (NSString *)componentDescription {
    return NSStringFromClass(_class);
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return self;
}

- (NSDictionary *)defaultKnobs {
    return [_class statusBarComponentDefaultKnobs];
}

@end

@interface iTermStatusBarBaseComponent()<iTermWebViewDelegate, NSPopoverDelegate>
@end

@implementation iTermStatusBarBaseComponent

@synthesize configuration = _configuration;
@synthesize delegate = _delegate;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _scope = scope;
        _configuration = [configuration copy];
        _advancedConfiguration = [iTermStatusBarAdvancedConfiguration advancedConfigurationFromDictionary:configuration[iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue]];
        _defaultTextColor = _advancedConfiguration.defaultTextColor;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSDictionary<iTermStatusBarComponentConfigurationKey,id> *configuration = [aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                                                     forKey:@"configuration"];
    if (!configuration) {
        return nil;
    }
    return [self initWithConfiguration:configuration
                                 scope:nil];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p priority=%@>",
            NSStringFromClass([self class]), self, @(self.statusBarComponentPriority)];
}

- (BOOL)statusBarComponentIsInternal {
    return NO;
}

+ (NSString *)statusBarComponentIdentifier {
    return [NSString stringWithFormat:@"com.iterm2.%@", NSStringFromClass(self.class)];
}

- (NSString *)statusBarComponentIdentifier {
    return [self.class statusBarComponentIdentifier];
}

- (nullable NSImage *)statusBarComponentIcon {
    return nil;
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [[iTermStatusBarBuiltInComponentFactory alloc] initWithClass:self.class];
}

- (CGFloat)statusBarComponentMinimumWidth {
    return self.statusBarComponentView.frame.size.width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self statusBarComponentMinimumWidth];
}

- (BOOL)statusBarComponentCanStretch {
    return NO;
}

- (BOOL)isEqualToComponent:(id<iTermStatusBarComponent>)other {
    if (other.class != self.class) {
        return NO;
    }
    iTermStatusBarBaseComponent *otherBase = [iTermStatusBarBaseComponent castFrom:other];
    return [self.configuration isEqual:otherBase.configuration];
}

- (nullable NSColor *)statusBarTextColor {
    return nil;
}

- (NSColor *)statusBarBackgroundColor {
    return _advancedConfiguration.backgroundColor;
}

- (CGFloat)defaultMinimumWidth {
    return 0;
}

- (NSArray<iTermStatusBarComponentKnob *> *)minMaxWidthKnobs {
    iTermStatusBarComponentKnob *maxWidthKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Maximum Width:"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:@""
                                              defaultValue:@(INFINITY)
                                                       key:iTermStatusBarMaximumWidthKey];
    iTermStatusBarComponentKnob *minWidthKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Minimum Width:"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:@""
                                              defaultValue:[@(self.defaultMinimumWidth) stringValue]
                                                       key:iTermStatusBarMinimumWidthKey];
    return @[minWidthKnob, maxWidthKnob];
}

- (CGFloat)clampedWidth:(CGFloat)width {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    CGFloat max = [knobValues[iTermStatusBarMaximumWidthKey] ?: @(INFINITY) doubleValue];
    CGFloat min = [knobValues[iTermStatusBarMinimumWidthKey] ?: @(self.defaultMinimumWidth) doubleValue];
    return MIN(max,
               MAX(min,
                   width));
}

+ (NSDictionary *)defaultMinMaxWidthKnobValues {
    return @{ iTermStatusBarMaximumWidthKey: @(INFINITY),
              iTermStatusBarMinimumWidthKey: @0 };
}

#pragma mark - iTermStatusBarComponent

- (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

- (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

- (iTermStatusBarComponentKnob *)newPriorityKnob {
    return [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Priority:"
                                                             type:iTermStatusBarComponentKnobTypeDouble
                                                      placeholder:@""
                                                     defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarPriorityKey]
                                                              key:iTermStatusBarPriorityKey];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *compressionResistanceKnob = nil;
    if ([self statusBarComponentCanStretch]) {
        NSString *title;
        switch (self.advancedConfiguration.layoutAlgorithm) {
            case iTermStatusBarLayoutAlgorithmSettingTightlyPacked:
                title = @"Compression Resistance:";
                break;
            case iTermStatusBarLayoutAlgorithmSettingStable:
                title = @"Size Multiple:";
                break;
        }
        compressionResistanceKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:title
                                                          type:iTermStatusBarComponentKnobTypeDouble
                                                   placeholder:@""
                                                  defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarCompressionResistanceKey]
                                                           key:iTermStatusBarCompressionResistanceKey];
    }
    iTermStatusBarComponentKnob *priorityKnob = [self newPriorityKnob];
    if (compressionResistanceKnob) {
        return @[ compressionResistanceKnob, priorityKnob ];
    } else {
        return @[ priorityKnob ];
    }
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    return @{ iTermStatusBarCompressionResistanceKey: @1,
              iTermStatusBarPriorityKey: @(iTermStatusBarBaseComponentDefaultPriority) };
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    [self doesNotRecognizeSelector:_cmd];
    return @"BUG";
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:[knobValues allKeys]];
    for (NSString *key in _configuration.allKeys) {
        [keys addObject:key];
    }
    NSDictionary *replacement = [_configuration dictionaryBySettingObject:knobValues
                                                                   forKey:iTermStatusBarComponentConfigurationKeyKnobValues];
    NSMutableSet<NSString *> *updatedKeys = [NSMutableSet set];
    NSDictionary *replacementKnobs = replacement[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSDictionary *originalKnobs = _configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    for (NSString *key in keys) {
        // The color picker tends to slightly perturb values during colorspace conversion so use
        // a fuzzy comparison for floating point values.
        if (![NSObject object:originalKnobs[key] isApproximatelyEqualToObject:replacementKnobs[key] epsilon:0.0001]) {
            [updatedKeys addObject:key];
        }
    }
    if ([_configuration isEqualToDictionary:replacement]) {
        DLog(@"Configuration remains unchanged.");
        return;
    }
    _configuration = replacement;
    [self statusBarComponentUpdate];
    [self.delegate statusBarComponentKnobsDidChange:self
                                        updatedKeys:updatedKeys];
}

- (NSDictionary *)statusBarComponentKnobValues {
    return _configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
}

- (NSView *)statusBarComponentView {
    [self doesNotRecognizeSelector:_cmd];
    return [[NSView alloc] init];
}

- (double)statusBarComponentPriority {
    NSNumber *number = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarPriorityKey] ?: @5;
    if (number) {
        return number.doubleValue;
    }
    return 5;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return INFINITY;
}

- (void)statusBarComponentUpdate {
}

- (CGFloat)statusBarComponentSpringConstant {
    NSNumber *value = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarCompressionResistanceKey] ?: @1;
    return MAX(0.01, value.doubleValue);
}

- (CGFloat)statusBarComponentMaximumWidth {
    NSNumber *value = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarMaximumWidthKey] ?: @(INFINITY);
    return MAX(24, value.doubleValue);
}

- (nullable NSViewController<iTermFindViewController> *)statusBarComponentSearchViewController {
    return nil;
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
}

- (BOOL)statusBarComponentHasMargins {
    return YES;
}

- (CGFloat)statusBarComponentVerticalOffset {
    return 0;
}

- (void)statusBarDefaultTextColorDidChange {
}

- (void)statusBarTerminalBackgroundColorDidChange {
}

- (void)statusBarComponentOpenPopoverWithHTML:(NSString *)html ofSize:(NSSize)size {
    WKWebView *webView = [[iTermWebViewFactory sharedInstance] webViewWithDelegate:self];
    if (!webView) {
        return;
    }
    [webView loadHTMLString:html baseURL:nil];
    NSPopover *popover = [[NSPopover alloc] init];
    NSViewController *viewController = [[iTermWebViewWrapperViewController alloc] initWithWebView:webView
                                                                                        backupURL:nil];
    popover.contentViewController = viewController;
    popover.contentSize = size;
    NSView *view = self.statusBarComponentView;
    popover.behavior = NSPopoverBehaviorSemitransient;
    popover.delegate = self;
    NSRectEdge preferredEdge = NSRectEdgeMinY;
    switch ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            preferredEdge = NSRectEdgeMaxY;
            break;
        case iTermStatusBarPositionBottom:
            preferredEdge = NSRectEdgeMinY;
            break;
    }
    [popover showRelativeToRect:view.bounds
                         ofView:view
                  preferredEdge:preferredEdge];
}

- (BOOL)statusBarComponentHandlesClicks {
    return NO;
}

- (BOOL)statusBarComponentIsEmpty {
    return NO;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
}

- (BOOL)statusBarComponentHandlesMouseDown {
    return NO;
}

- (void)statusBarComponentDidMoveToWindow {
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_configuration forKey:@"configuration"];
}

#pragma mark - NSPopoverDelegate

- (void)popoverDidClose:(NSNotification *)notification {
    NSPopover *popover = notification.object;
    iTermWebViewWrapperViewController *viewController = (iTermWebViewWrapperViewController *)popover.contentViewController;
    [viewController terminateWebView];

}

#pragma mark - iTermWebViewDelegate

- (void)itermWebViewScriptInvocation:(NSString *)invocation didFailWithError:(NSError *)error {
    [[iTermAPIHelper sharedInstance] logToConnectionHostingFunctionWithSignature:invocation
                                                                          string:error.localizedDescription];
}

- (iTermVariableScope *)itermWebViewScriptScopeForUserContentController:(WKUserContentController *)userContentController {
    return self.scope;
}

- (void)itermWebViewJavascriptError:(NSString *)errorText {
    XLog(@"Unhandled javascript error: %@", errorText);
}

- (void)itermWebViewWillExecuteJavascript:(NSString *)javascript {
    XLog(@"Unexpected javascript execution: %@", javascript);
}

- (BOOL)itermWebViewShouldAllowInvocation {
    return YES;
}

@end

NS_ASSUME_NONNULL_END
