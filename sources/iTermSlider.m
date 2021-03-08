//
//  iTermSlider.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/8/21.
//

#import "iTermSlider.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

static char iTermSliderKVOKey;

@interface iTermSlider()<NSTextFieldDelegate>
@end

@implementation iTermSlider {
    IBOutlet NSSlider *_slider;
    NSTextField *_textField;
    NSStepper *_stepper;
    __weak id _target;
    SEL _action;
    BOOL _percentage;
}

- (instancetype)init {
    assert(NO);
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self initCommon];
    }
    return self;
}

- (void)initCommon {
    // omg I hate appkit
    // https://stackoverflow.com/questions/17793022/make-nsview-not-clip-subviews-outside-of-its-bounds
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;

    _stepper = [[NSStepper alloc] init];
    [_stepper sizeToFit];
    NSRect rect = _stepper.frame;
    rect.origin.x = NSWidth(self.frame) - NSWidth(rect);
    rect.origin.y = (NSHeight(self.frame) - NSHeight(_stepper.frame)) / 2.0;
    _stepper.frame = rect;
    _stepper.autoresizingMask = NSViewMinXMargin;
    _stepper.target = self;
    _stepper.action = @selector(stepperDidChange:);
    [self addSubview:_stepper];

    const CGFloat textFieldWidth = 30;
    _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, textFieldWidth, 17)];
    [_textField sizeToFit];
    _textField.editable = YES;
    _textField.selectable = YES;
    _textField.autoresizingMask = NSViewMinXMargin;
    _textField.usesSingleLineMode = YES;
    _textField.delegate = self;
    _textField.focusRingType = NSFocusRingTypeNone;
    rect = _textField.frame;
    const CGFloat margin = 0;
    rect.size.width = textFieldWidth;
    rect.origin.x = NSMinX(_stepper.frame) - NSWidth(rect) - margin;
    rect.origin.y = (NSHeight(self.frame) - NSHeight(_textField.frame)) / 2.0;
    _textField.frame = rect;
    [self addSubview:_textField];
}

- (BOOL)wantsDefaultClipping {
    return NO;
}

- (void)awakeFromNib {
    if (!_slider) {
        for (NSView *view in [self subviews]) {
            if ([view isKindOfClass:[NSSlider class]]) {
                _slider = (NSSlider *)view;
                break;
            }
        }
    }
    self.autoresizingMask = _slider.autoresizingMask;
    _stepper.minValue = _slider.minValue;
    _stepper.maxValue = _slider.maxValue;
    _percentage = (_slider.minValue >= 0 && _slider.maxValue <= 1);
    if (_percentage) {
        _stepper.increment = 0.01;
    } else {
        _stepper.increment = 1;
    }
    NSRect rect = _slider.frame;
    rect.origin.x = 0;
    const CGFloat margin = 0;
    rect.size.width = NSMinX(_textField.frame) - margin;
    _slider.frame = rect;
    _target = _slider.target;
    _action = _slider.action;
    [_slider addObserver:self
              forKeyPath:@"doubleValue"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:(void *)&iTermSliderKVOKey];
    [self loadFromSlider];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != &iTermSliderKVOKey) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self loadFromSlider];
}

- (void)setTextFieldValue:(double)value {
    if (_percentage) {
        _textField.intValue = round(_slider.doubleValue * 100);
    } else {
        _textField.doubleValue = round(_slider.doubleValue);
    }
}

- (double)textFieldValue {
    if (_percentage) {
        return _textField.intValue / 100.0;
    } else {
        return _textField.doubleValue;
    }
}

- (void)loadFromSlider {
    [self setTextFieldValue:_slider.doubleValue];
    _stepper.doubleValue = _slider.doubleValue;
}

- (void)performAction {
    if (_target && _action) {
        [_target it_performNonObjectReturningSelector:_action withObject:_slider];
    }
}

#pragma mark - Actions

- (void)stepperDidChange:(id)sender {
    _slider.doubleValue = _stepper.doubleValue;
    [self setTextFieldValue:_stepper.doubleValue];
    [self performAction];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
    if (!_textField.stringValue.isNonnegativeFractionalNumber) {
        return;
    }
    const double value = [self textFieldValue];
    _slider.doubleValue = value;
    _stepper.doubleValue = value;
    [self performAction];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (!_textField.stringValue.isNonnegativeFractionalNumber) {
        [self loadFromSlider];
    }
}

@end
