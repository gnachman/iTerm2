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
      hostname = [string substringWithRange:NSMakeRange(atSign + 1, colon - atSign - 1)];
    } else if (colon == NSNotFound) {
      // user@host
      hostname = [string substringFromIndex:atSign + 1];
    }
  }
  if (colon != NSNotFound) {
    // [user@]host:path
      if (!hostname) {
          hostname = [string substringToIndex:colon];
      }
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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p hostname=%@ username=%@ path=%@>",
            [self class], self, self.hostname, self.username, self.path];
}

- (int)scoreForHostname:(NSString *)hostname
               username:(NSString *)username
                   path:(NSString *)path {
  const int kHostExactMatchScore = 8;
  const int kHostMatchScore = 4;
  const int kUserMatchScore = 2;
  const int kPathMatchScore = 1;

  int score = 0;

  if (self.hostname != nil) {
    // Fixup hostname for regex match
    NSString *fixedHostname = [self.hostname stringByReplacingOccurrencesOfString:@"." withString:@"\\."];
    int prevLength = [fixedHostname length];
    fixedHostname = [fixedHostname stringByReplacingOccurrencesOfString:@"*" withString:@".*"];
    int postLength = [fixedHostname length];

    // If no wildcards just do exact match
    if (prevLength == postLength) {
      if ([hostname isEqualToString:self.hostname]) {
        score |= kHostExactMatchScore;
      }
    } else {
      // Wildcards found, do regex pattern match
      NSError *error = nil;
      NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:fixedHostname
                                                                        options:NSRegularExpressionCaseInsensitive
                                                                          error:&error];
      if (error) {
        NSLog(@"Could not create regex from pattern: %@", fixedHostname);
      } else {
        NSRange hostnameRange = NSMakeRange(0, [hostname length]);
        NSRange foundRange = [regex rangeOfFirstMatchInString:hostname
                                                      options:NSMatchingReportProgress
                                                        range:hostnameRange];
        if (foundRange.location != NSNotFound &&
            foundRange.location == 0 &&
            foundRange.length == hostnameRange.length) {
          score |= kHostMatchScore;
        }
      }
    }
    
    if (score == 0 && self.hostname.length) {
      return 0;
    }
  }
  
  if ([username isEqualToString:self.username]) {
    score |= kUserMatchScore;
  } else if (self.username.length) {
      return 0;
  }
  if ([path isEqualToString:self.path]) {
    score |= kPathMatchScore;
  } else if (self.path.length) {
      return 0;
  }

  return score;
}

@end
