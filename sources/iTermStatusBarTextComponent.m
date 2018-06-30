//
//  iTermStatusBarTextComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarTextComponent.h"

#import "NSObject+iTerm.h"

@implementation iTermStatusBarBaseComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    self = [super init];
    if (self) {
        _configuration = [configuration copy];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSDictionary<iTermStatusBarComponentConfigurationKey,id> *configuration = [aDecoder decodeObjectOfClass:[NSDictionary class]
                                                                                                     forKey:@"configuration"];
    if (!configuration) {
        return nil;
    }
    return [self initWithConfiguration:configuration];
}

- (CGFloat)statusBarComponentMinimumWidth {
    NSNumber *number = _configuration[iTermStatusBarComponentConfigurationKeyMinimumWidth];
    if (number) {
        return number.doubleValue;
    }
    return self.statusBarComponentCreateView.frame.size.width;
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

+ (id)statusBarComponentExemplar {
    [self doesNotRecognizeSelector:_cmd];
    return @"BUG";
}

+ (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

+ (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"Base class! This should not be called!";
}

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    [self doesNotRecognizeSelector:_cmd];
    return @[];
}

- (NSView *)statusBarComponentCreateView {
    [self doesNotRecognizeSelector:_cmd];
    return [[NSView alloc] init];
}

- (double)statusBarComponentPriority {
    NSNumber *number = _configuration[iTermStatusBarComponentConfigurationKeyPriority];
    if (number) {
        return number.doubleValue;
    }
    return iTermStatusBarComponentPriorityMedium;
}

- (iTermStatusBarComponentJustification)statusBarComponentJustification {
    NSNumber *number = _configuration[iTermStatusBarComponentConfigurationKeyJustification];
    if (number) {
        return number.unsignedIntegerValue;
    }
    return iTermStatusBarComponentJustificationLeft;
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
    return 1;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_configuration forKey:@"configuration"];
}

@end

@implementation iTermStatusBarTextComponent {
    NSTextField *_textField;
}

- (NSTextField *)textField {
    if (!_textField) {
        _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _textField.drawsBackground = NO;
        _textField.bordered = NO;
        _textField.editable = NO;
        _textField.selectable = NO;
        if (self.stringValue) {
            _textField.stringValue = self.stringValue;
            _textField.alignment = NSLeftTextAlignment;
            _textField.textColor = [NSColor textColor];
        } else if (self.attributedStringValue) {
            _textField.attributedStringValue = self.attributedStringValue;
        } else {
            assert(NO);
        }
        [_textField sizeToFit];
    }
    return _textField;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.textField;
}

@end

@implementation iTermStatusBarFixedSpacerComponent {
    NSView *_view;
}

+ (id)statusBarComponentExemplar {
    return @"";
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Fixed-size Spacer";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Adds ten points of space";
}

- (NSView *)statusBarComponentCreateView {
    if (!_view) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.statusBarComponentMinimumWidth, 0)];
    }
    return _view;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 10;
}

@end

@implementation iTermStatusBarSpringComponent {
    NSView *_view;
}


+ (id)statusBarComponentExemplar {
    return @"║┄┄║";
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Spring";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Pushes items apart. Use one spring to right-align status bar elements that follow it. Use two to center those inbetween.";
}

- (NSView *)statusBarComponentCreateView {
    if (!_view) {
        _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.statusBarComponentMinimumWidth, 0)];
    }
    return _view;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 0;
}

@end

