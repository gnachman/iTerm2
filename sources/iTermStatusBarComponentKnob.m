//
//  iTermStatusBarComponentKnob.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import "iTermStatusBarComponentKnob.h"

#import "iTermDragHandleView.h"
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermStatusBarComponentKnobMinimumWidthKey = @"_minimumWidth";

@implementation iTermStatusBarComponentKnob

- (instancetype)initWithLabelText:(nullable NSString *)labelText
                             type:(iTermStatusBarComponentKnobType)type
                      placeholder:(nullable NSString *)placeholder
                     defaultValue:(nullable id)defaultValue
                              key:(NSString *)key {
    self = [super init];
    if (self) {
        _labelText = [labelText copy];
        _type = type;
        _placeholder = [placeholder copy];
        _value = defaultValue;
        _key = [key copy];
    }
    return self;
}

- (NSView *)inputView {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (nullable NSString *)stringValue {
    return [NSString castFrom:_value];
}

- (nullable NSNumber *)numberValue {
    return [NSNumber castFrom:_value];
}

@end

NS_ASSUME_NONNULL_END
