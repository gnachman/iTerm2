//
//  iTermStatusBarKnobColorViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/5/18.
//

#import "iTermStatusBarKnobColorViewController.h"

#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"

@interface iTermStatusBarKnobColorViewController ()

@end

@implementation iTermStatusBarKnobColorViewController {
    IBOutlet CPKColorWell *_well;
    NSDictionary *_value;
}

- (void)viewDidLoad {
    _well.noColorAllowed = YES;
    self.view.autoresizesSubviews = NO;
    self.value = _value;
}

- (void)setValue:(NSDictionary *)value {
    _value = value;
    _well.color = [_value colorValue];
}

- (NSDictionary *)value {
    return [_well.color dictionaryValue];
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _label.stringValue = description;
    [self sizeToFit];
}

- (void)sizeToFit {
    const CGFloat marginBetweenLabelAndWell = NSMinX(_well.frame) - NSMaxX(_label.frame);
    
    [_label sizeToFit];
    NSRect rect = _label.frame;
    _label.frame = rect;
    
    rect = _well.frame;
    rect.origin.x = NSMaxX(_label.frame) + marginBetweenLabelAndWell;
    _well.frame = rect;

    rect = self.view.frame;
    rect.size.width = NSMaxX(_well.frame);
    self.view.frame = rect;
}

- (CGFloat)controlOffset {
    return NSMinX(_well.frame);
}

- (void)setHelpURL:(NSURL *)url {
    NSAssert(NO, @"Not supported");
}

@end
