//
//  NSView+RecursiveDescription.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "NSView+RecursiveDescription.h"

@implementation NSView (RecursiveDescription)

- (NSString *)recursiveDescriptionWithPrefix:(NSString *)prefix {
    NSMutableString *s = [NSMutableString string];
    NSMutableArray *arm = [NSMutableArray array];
    if (self.autoresizingMask & NSViewHeightSizable) {
        [arm addObject:@"h"];
    }
    if (self.autoresizingMask & NSViewWidthSizable) {
        [arm addObject:@"w"];
    }
    if (self.autoresizingMask & NSViewMinXMargin) {
        [arm addObject:@"minX"];
    }
    if (self.autoresizingMask & NSViewMaxXMargin) {
        [arm addObject:@"maxX"];
    }
    if (self.autoresizingMask & NSViewMinYMargin) {
        [arm addObject:@"minY"];
    }
    if (self.autoresizingMask & NSViewMaxYMargin) {
        [arm addObject:@"maxY"];
    }
    if (self.autoresizesSubviews) {
        [arm addObject:@"subviews"];
    }
    [s appendFormat:@"%@%@ frame=%@ hidden=%@ alphaValue=%0.2f autoresizing=%@ autolayout=%@ tracking_areas=%@\n",
     prefix,
     self,
     [NSValue valueWithRect:self.frame],
     self.isHidden ? @"YES" : @"no",
     self.alphaValue,
     [arm componentsJoinedByString:@","],
     self.translatesAutoresizingMaskIntoConstraints ? @"No" : @"*AUTO LAYOUT IN EFFECT*",
     self.trackingAreas.count ? self.trackingAreas : @"none"];
    for (NSView *view in [self subviews]) {
        [s appendString:[view recursiveDescriptionWithPrefix:[prefix stringByAppendingString:@"|   "]]];
    }
    return s;
}

- (NSString *)iterm_recursiveDescription {
    return [self recursiveDescriptionWithPrefix:@""];
}

@end

