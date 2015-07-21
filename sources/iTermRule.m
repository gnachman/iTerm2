//
//  iTermRule.m
//  iTerm
//
//  Created by George Nachman on 6/24/14.
//
//

#import "iTermRule.h"

@interface iTermRule()
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *path;
@end

@implementation iTermRule

+ (instancetype)ruleWithString:(NSString *)string {
  // hostname
  // username@
  // username@hostname
  // username@hostname:path
  // username@*:path
  // hostname:path
  // /path

  NSString *username = nil;
  NSString *hostname = nil;
  NSString *path = nil;

  NSUInteger atSign = [string rangeOfString:@"@"].location;
  NSUInteger colon = [string rangeOfString:@":"].location;

  if (atSign != NSNotFound) {
    // user@host[:path]
    username = [string substringToIndex:atSign];
    if (colon != NSNotFound && colon < atSign) {
      // malformed, like foo:bar@baz
      colon = NSNotFound;
    } else if (colon != NSNotFound) {
      // user@host:path
      hostname = [string substringWithRange:NSMakeRange(atSign + 1, colon - atSign)];
    }
  }
  if (colon != NSNotFound) {
    // [user@]host:path
    path = [string substringFromIndex:colon + 1];
  } else if (atSign == NSNotFound && [string hasPrefix:@"/"]) {
    // /path
    path = string;
  } else if (atSign == NSNotFound && colon == NSNotFound) {
    // host
    hostname = string;
  }
  if ([hostname isEqualToString:@"*"]) {
    // user@*:path or *:path
    hostname = nil;
  }
  iTermRule *rule = [[[iTermRule alloc] init] autorelease];
  rule.username = username;
  rule.hostname = hostname;
  rule.path = path;
  return rule;
}

- (void)dealloc {
  [_hostname release];
  [_username release];
  [_path release];
  [super dealloc];
}

- (int)scoreForHostname:(NSString *)hostname
               username:(NSString *)username
                   path:(NSString *)path {
  const int kHostExactMatchScore = 8;
  const int kHostMatchScore      = 4;
  const int kUserMatchScore      = 2;
  const int kPathMatchScore      = 1;

  int score = 0;

  if (self.hostname != nil) {
    NSRange containsHost = [hostname rangeOfString:self.hostname options:NSCaseInsensitiveSearch];
    if (containsHost.location != NSNotFound) {
      if (containsHost.location == 0 && containsHost.length == hostname.length) {
        score |= kHostExactMatchScore;
      } else {
        score |= kHostMatchScore;
      }
    }
  }

  if ([username isEqualToString:self.username]) {
    score |= kUserMatchScore;
  }
  if ([path isEqualToString:self.path]) {
    score |= kPathMatchScore;
  }

  return score;
}

@end
