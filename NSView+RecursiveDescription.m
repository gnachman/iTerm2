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
  [s appendFormat:@"%@%@ frame=%@\n", prefix, self, [NSValue valueWithRect:self.frame]];
  for (NSView *view in [self subviews]) {
    [s appendString:[view recursiveDescriptionWithPrefix:[prefix stringByAppendingString:@"|   "]]];
  }
  return s;
}

- (NSString *)iterm_recursiveDescription {
  return [self recursiveDescriptionWithPrefix:@""];
}

@end

