//
//  NSApplication+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 7/4/15.
//
//

#import <Cocoa/Cocoa.h>

@interface NSObject (IsRunningTests)
- (BOOL)isTesting;
@end

@implementation NSApplication (iTerm)

- (BOOL)isRunningUnitTests {
  Class theClass;
  theClass = NSClassFromString(@"XCTestProbe");
  if (theClass) {
      return [theClass isTesting];
  } else {
      return NO;
  }
}

@end
