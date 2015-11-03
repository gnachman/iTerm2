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
  [s appendFormat:@"%@%@ frame=%@ hidden=%@ alphaValue=%0.2f tracking_areas=%@\n",
      prefix,
      self,
      [NSValue valueWithRect:self.frame],
      self.isHidden ? @"YES" : @"no",
      self.alphaValue,
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

