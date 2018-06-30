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

@implementation iTermStatusBarComponentKnobText {
    NSTextField *_view;
}

- (NSView *)inputView {
    if (!_view) {
        _view = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _view.drawsBackground = NO;
        _view.bordered = NO;
        _view.editable = NO;
        _view.selectable = NO;
        _view.placeholderString = self.placeholder;
        _view.stringValue = self.stringValue;
        _view.alignment = NSLeftTextAlignment;
        _view.textColor = [NSColor textColor];
        [_view sizeToFit];
    }
    return _view;
}

@end

@implementation iTermStatusBarComponentKnobMinimumWidth

- (NSView *)inputView {
    NSView *view = [[iTermDragHandleView alloc] initWithFrame:NSMakeRect(0, 0, 22, 4)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = [[NSColor grayColor] CGColor];
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [[NSColor blackColor] CGColor];
    return view;
}

@end

NS_ASSUME_NONNULL_END
