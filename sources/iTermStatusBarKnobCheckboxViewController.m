//
//  iTermStatusBarKnobCheckboxViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarKnobCheckboxViewController.h"

@interface iTermStatusBarKnobCheckboxViewController ()

@end

@implementation iTermStatusBarKnobCheckboxViewController

- (NSNumber *)value {
    self.view.autoresizesSubviews = NO;
    return @(_checkbox.state == NSOnState);
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _checkbox.title = description;
    [self sizeToFit];
    self.view.frame = _checkbox.frame;
}

- (CGFloat)controlOffset {
    return 0;
}

- (void)setValue:(id)value {
    _checkbox.state = [value boolValue] ? NSOnState : NSOffState;
}

- (void)sizeToFit {
    [_checkbox sizeToFit];
}


- (void)encodeWithCoder:(nonnull NSCoder *)aCoder {
    [aCoder encodeObject:self.value forKey:@"value"];
}

- (void)setHelpURL:(NSURL *)url {
    NSAssert(NO, @"Not supported");
}

@end
