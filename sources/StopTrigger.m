//
//  StopTrigger.m
//  iTerm2
//
//  Created by George Nachman on 5/15/15.
//
//

#import "StopTrigger.h"

@implementation StopTrigger

+ (NSString *)title {
  return @"Stop Processing Triggers";
}

- (BOOL)takesParameter {
  return NO;
}

- (BOOL)performActionWithValues:(NSArray *)values
                      inSession:(PTYSession *)aSession
                       onString:(NSString *)string
           atAbsoluteLineNumber:(long long)absoluteLineNumber
                           stop:(BOOL *)stop {
  *stop = YES;
  return NO;
}

@end
