//
//  iTermApplication+Scripting.m
//  iTerm2
//
//  Created by George Nachman on 8/26/14.
//
//

#import "iTermApplication+Scripting.h"
#import "iTermController.h"

@implementation iTermApplication (Scripting)

- (NSUInteger)countOfTerminalWindows {
  return [[[iTermController sharedInstance] terminals] count];
}

- (id)valueInTerminalWindowsAtIndex:(unsigned)anIndex {
  id terminalWindow = [[iTermController sharedInstance] terminals][anIndex];
  return terminalWindow;
}

- (id)valueForUndefinedKey:(NSString *)key {
  return @[];
}

- (id)valueForKey:(NSString *)key {
  if ([key isEqualToString:@"terminalWindows"]) {
    return [[iTermController sharedInstance] terminals];
  } else if ([key isEqualToString:@"currentWindow"]) {
    return [[iTermController sharedInstance] currentTerminal];
  } else {
    return nil;
  }
}

- (PseudoTerminal *)currentWindow {
  return [[iTermController sharedInstance] currentTerminal];
}

@end
