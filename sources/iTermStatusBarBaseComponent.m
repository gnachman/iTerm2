//
//  iTermStatusBarBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarBaseComponent.h"

#import "iTermStatusBarSetupKnobsViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarCompressionResistanceKey = @"base: compression resistance";
NSString *const iTermStatusBarPriorityKey = @"base: priority";

@implementation iTermStatusBarBuiltInComponentFactory {
    Class _class;
    // NOTE: If mutable state is added update copyWithZone:
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
- (id<iTermStatusBarComponent>)newComponentWithKnobs:(NSDictionary *)knobs {
    return [[_class alloc] initWithConfiguration:@{iTermStatusBarComponentConfigurationKeyKnobValues: knobs}];
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

@implementation iTermStatusBarBaseComponent

@synthesize configuration = _configuration;
@synthesize delegate = _delegate;

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    self = [super init];
    if (self) {
        _configuration = [configuration copy];
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSDictionary<iTermStatusBarComponentConfigurationKey,id> *configuration = [aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                                                     forKey:@"configuration"];
    if (!configuration) {
        return nil;
    }
    return [self initWithConfiguration:configuration];
}

- (id<iTermStatusBarComponentFactory>)statusBarComponentFactory {
    return [[iTermStatusBarBuiltInComponentFactory alloc] initWithClass:self.class];
}

- (CGFloat)statusBarComponentMinimumWidth {
    return self.statusBarComponentCreateView.frame.size.width;
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

#pragma mark - iTermStatusBarComponent

- (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

- (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *compressionResistanceKnob = nil;
    if ([self statusBarComponentCanStretch]) {
        compressionResistanceKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Compression Resistance:"
                                                          type:iTermStatusBarComponentKnobTypeDouble
                                                   placeholder:@""
                                                  defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarCompressionResistanceKey]
                                                           key:iTermStatusBarCompressionResistanceKey];
    }
    iTermStatusBarComponentKnob *priorityKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Priority:"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:@""
                                              defaultValue:self.class.statusBarComponentDefaultKnobs[iTermStatusBarPriorityKey]
                                                       key:iTermStatusBarPriorityKey];
    if (compressionResistanceKnob) {
        return @[ compressionResistanceKnob, priorityKnob ];
    } else {
        return @[ priorityKnob ];
    }
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    return @{ iTermStatusBarCompressionResistanceKey: @1,
              iTermStatusBarPriorityKey: @5 };
}

- (id)statusBarComponentExemplar {
    [self doesNotRecognizeSelector:_cmd];
    return @"BUG";
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _configuration = [_configuration dictionaryBySettingObject:knobValues
                                                        forKey:iTermStatusBarComponentConfigurationKeyKnobValues];
    [self statusBarComponentUpdate];
    [self.delegate statusBarComponentKnobsDidChange:self];
}

- (NSView *)statusBarComponentCreateView {
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

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet set];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return INFINITY;
}

- (void)statusBarComponentUpdate {
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [self statusBarComponentUpdate];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    _scope = scope;
}

- (CGFloat)statusBarComponentSpringConstant {
    NSNumber *value = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues][iTermStatusBarCompressionResistanceKey] ?: @1;
    return MAX(0.01, value.doubleValue);
}

- (NSViewController<iTermFindViewController> *)statusBarComponentSearchViewController {
    return nil;
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
}

- (BOOL)statusBarComponentHasMargins {
    return YES;
}

- (CGFloat)statusBarComponentVerticalOffset {
    // Since most components are text this improves the vertical alignment of latin characters
    return 1.5;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_configuration forKey:@"configuration"];
}

@end

NS_ASSUME_NONNULL_END
