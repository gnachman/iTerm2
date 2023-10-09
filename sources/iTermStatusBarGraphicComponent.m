//
//  iTermStatusBarGraphicComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermStatusBarGraphicComponent.h"

#import "iTermStatusBarViewController.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermStatusBarImageComponentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
    }
    return self;
}

- (NSColor *)backgroundColor {
    return [NSColor colorWithCGColor:self.layer.backgroundColor];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    self.layer.backgroundColor = backgroundColor.CGColor;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    _contentView.frame = self.bounds;
}

- (void)setContentView:(NSView *)contentView {
    [_contentView removeFromSuperview];
    _contentView = contentView;
    [self addSubview:contentView];
    contentView.frame = self.bounds;
}

- (BOOL)clipsToBounds {
    return YES;
}

@end

@implementation iTermStatusBarGraphicComponent {
    CGFloat _preferredWidth;
    CGFloat _renderedWidth;
    iTermStatusBarImageComponentView *_view;
    CGFloat _previousWidth;
}

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSColor *configuredColor = [knobValues[iTermStatusBarSharedTextColorKey] colorValue];
    if (configuredColor) {
        return configuredColor;
    }

    NSColor *defaultTextColor = [self defaultTextColor];
    if (defaultTextColor) {
        return defaultTextColor;
    }

    NSColor *provided = [self.delegate statusBarComponentDefaultTextColor];
    if (provided) {
        return provided;
    } else {
        return [NSColor labelColor];
    }
}

- (nullable NSColor *)statusBarTextColor {
    return [self textColor];
}

- (NSColor *)statusBarBackgroundColor {
    return [self backgroundColor];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];
    NSArray<iTermStatusBarComponentKnob *> *knobs = [@[ backgroundColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
    if (self.shouldHaveTextColorKnob) {
        iTermStatusBarComponentKnob *textColorKnob =
            [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color:"
                                                              type:iTermStatusBarComponentKnobTypeColor
                                                       placeholder:nil
                                                      defaultValue:nil
                                                               key:iTermStatusBarSharedTextColorKey];
        knobs = [knobs arrayByAddingObject:textColorKnob];
    }
    return knobs;
}

- (iTermStatusBarImageComponentView *)newView {
    return [[iTermStatusBarImageComponentView alloc] initWithFrame:NSZeroRect];
}

- (iTermStatusBarImageComponentView *)view {
    if (!_view) {
        _view = [self newView];
    }
    return _view;
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [super statusBarBackgroundColor];
}

- (BOOL)shouldUpdateValue:(NSObject *)proposed {
    iTermStatusBarImageComponentView *view = self.view;
    NSObject *existing = self.model;
    const BOOL hasValue = existing != nil;
    const BOOL haveProposedvalue = proposed != nil;

    if (hasValue != haveProposedvalue) {
        return YES;
    }
    if (hasValue || haveProposedvalue) {
        return !([NSObject object:existing isEqualToObject:proposed] &&
                 [NSObject object:view.backgroundColor isEqualToObject:self.backgroundColor]);
    }

    return NO;
}

- (void)updateViewIfNeededAnimated:(BOOL)animated {
    CGFloat preferredWidth = 0;
    NSObject *newPreferred = [self widestModel:&preferredWidth];

    if (preferredWidth != _preferredWidth) {
        _preferredWidth = preferredWidth;
        [self.delegate statusBarComponentPreferredSizeDidChange:self];
    }

    NSObject *proposedForCurrentWidth = [self modelForCurrentWidth];

    const CGFloat viewWidth = self.view.frame.size.width;
    if ([self shouldUpdateValue:proposedForCurrentWidth] || viewWidth != _renderedWidth) {
        [self redrawAnimated:animated];
        _renderedWidth = viewWidth;
    }

    _model = proposedForCurrentWidth;
    _preferredModel = newPreferred;
}

- (NSObject *)modelForCurrentWidth {
    CGFloat currentWidth = self.view.frame.size.width;
    return [self modelForWidth:currentWidth width:nil];
}

- (NSObject *)widestModel:(out CGFloat *)width {
    return [self modelForWidth:INFINITY width:width];
}

- (CGFloat)statusBarComponentPreferredWidth {
    CGFloat width = 0;
    [self widestModel:&width];
    return width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    self.view.frame = NSMakeRect(0, 0, width, iTermGetStatusBarHeight());
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 1;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentView {
    return self.view;
}

- (void)statusBarComponentUpdate {
//    [self updateViewIfNeededAnimated:YES];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    if (newWidth == _previousWidth) {
        return;
    }
    _previousWidth = newWidth;
    [self updateViewIfNeededAnimated:NO];
}

- (void)statusBarDefaultTextColorDidChange {
    [self updateViewIfNeededAnimated:NO];
}

#pragma mark - Required overrides

- (NSObject *)modelForWidth:(CGFloat)maximumWidth width:(out CGFloat *)preferredWidth {
    [self doesNotRecognizeSelector:_cmd];
    return @{};
}

- (void)redraw {
    [self redrawAnimated:NO];
}

- (void)redrawAnimated:(BOOL)animated {
    NSRect frame = self.view.frame;
    frame.size.height = iTermGetStatusBarHeight();
    self.view.frame = frame;
}

@end

