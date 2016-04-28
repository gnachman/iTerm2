//
//  iTermRule.m
//  iTerm
//
//  Created by George Nachman on 6/24/14.
//
//

#import "iTermRule.h"
#import "NSStringITerm.h"

@interface iTermRule()
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, readwrite) BOOL sticky;
@end

@implementation iTermRule

+ (instancetype)ruleWithString:(NSString *)string {
    // Any rule may begin with ! to indicate it is sticky (it will be reverted to in the future if
    // no APS rule matches).
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
    BOOL sticky = NO;

    if ([string hasPrefix:@"!"]) {
        sticky = YES;
        string = [string substringFromIndex:1];
    }
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
    rule.sticky = sticky;
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

// This is a monotonically increasing function whose range is [0, 1) for the domain of nonnegative
// values. It grows very slowly so that for any value of x that could be a Unix path name,
// squash(x + 1) - squash(x) > machine_epsilon.
- (double)squash:(double)x {
    assert(x >= 0);
    return x / (x + 1.0);
}

- (double)scoreForHostname:(NSString *)hostname
                  username:(NSString *)username
                      path:(NSString *)path {
    const int kHostExactMatchScore = 8;
    const int kHostPartialMatchScore = 4;

    const int kUserExactMatchScore = 2;

    const int kPathExactMatchScore = 1;
    const int kPathPartialMatchScore = 0;

    double score = 0;

    if (self.hostname != nil) {
        NSRange wildcardPos = [self.hostname rangeOfString:@"*"];
        if (wildcardPos.location == NSNotFound && [hostname isEqualToString:self.hostname]) {
            score += kHostExactMatchScore;
        } else if ([hostname stringMatchesGlobPattern:self.hostname caseSensitive:NO]) {
            score += kHostPartialMatchScore * (1.0 + [self squash:self.hostname.length]);
        } else if (self.hostname.length) {
            return 0;
        }
    }

    if ([username isEqualToString:self.username]) {
        score += kUserExactMatchScore;
    } else if (self.username.length) {
        return 0;
    }

    if (self.path != nil) {
        // Make sure path ends in a / so a path glob pattern "/foo/bar/*" will match a path of "/foo/bar".
        NSString *pathForGlob = path;
        if (![pathForGlob hasSuffix:@"/"]) {
            pathForGlob = [pathForGlob stringByAppendingString:@"/"];
        }
        
        NSRange wildcardPos = [self.path rangeOfString:@"*"];
        if (wildcardPos.location == NSNotFound && [path isEqualToString:self.path]) {
            score += kPathExactMatchScore;
        } else if ([pathForGlob stringMatchesGlobPattern:self.path caseSensitive:YES]) {
            score += kPathPartialMatchScore + [self squash:self.path.length];
        } else if (self.path.length) {
            return 0;
        }
    }

    return score;
}

@end
