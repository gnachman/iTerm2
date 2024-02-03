//
//  iTermRule.m
//  iTerm
//
//  Created by George Nachman on 6/24/14.
//
//

#import "iTermRule.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

@interface iTermRule()
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *job;
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
    // &job
    // hostname&job
    // username@&job
    // username@hostname&job
    // username@hostname:path&job
    // username@*:path&job
    // hostname:path&job
    // /path&job

    NSString *username = nil;
    NSString *hostname = nil;
    NSString *path = nil;
    BOOL sticky = NO;

    if ([string hasPrefix:@"!"]) {
        sticky = YES;
        string = [string substringFromIndex:1];
    }

    NSInteger ampersand = [string rangeOfString:@"&"].location;
    NSString *job = nil;
    if (ampersand != NSNotFound) {
        job = [string substringFromIndex:ampersand + 1];
        string = [string substringToIndex:ampersand];
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
    iTermRule *rule = [[iTermRule alloc] init];
    rule.username = username;
    rule.hostname = hostname;
    rule.path = path;
    rule.sticky = sticky;
    rule.job = job;
    return rule;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p hostname=%@ username=%@ path=%@ job=%@>",
            [self class], self, self.hostname, self.username, self.path, self.job];
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
                      path:(NSString *)path
                       job:(NSString *)job {
    int acc = 1;
    const int kPathPartialMatchScore = 0;
    const int kCatchallRuleScore = acc;
    acc *= 2;
    const int kPathExactMatchScore = acc;
    acc *= 2;
    const int kUserExactMatchScore = acc;
    acc *= 2;
    const int kJobMatchScore = acc;
    acc *= 2;
    const int kHostPartialMatchScore = acc;
    acc *= 2;
    const int kHostExactMatchScore = acc;

    double score = 0;

    if (self.job) {
        if (![job stringMatchesGlobPattern:self.job caseSensitive:YES]) {
            return 0;
        }
        score += kJobMatchScore;
    }

    if (self.hostname != nil) {
        NSRange wildcardPos = [self.hostname rangeOfString:@"*"];
        if (wildcardPos.location == NSNotFound && [hostname isEqualToString:self.hostname]) {
            score += kHostExactMatchScore;
        } else if ([self.hostname isEqualToString:@"*"]) {
            if (![self haveAnyComponentBesidesHostname]) {
                // This is for backward compatibility. Previously, a hostname of * would be treated the
                // same as not having a host name at all. That made sense from a scoring POV because
                // you shouldn't get a higher score than a profile that doesn't specify a hostname at
                // all, as they are exactly equivalent. However, if you specify only a hostname of *
                // that should outrank a profile without any APS rules at all. I decided to give the
                // lowest possible score because it's a catch-all, so any other rule should outrank it.
                score += kCatchallRuleScore;
            }
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
        // An augmented path ends in a / so a path glob pattern "/foo/bar/*" will match a path of "/foo/bar".
        // The regular path is also tested so that the glob pattern "/foo/*" will match a path of "/foo/bar"
        NSString *augmentedPath = path;
        if (![augmentedPath hasSuffix:@"/"]) {
            augmentedPath = [augmentedPath stringByAppendingString:@"/"];
        }

        NSRange wildcardPos = [self.path rangeOfString:@"*"];
        if (wildcardPos.location == NSNotFound && [path isEqualToString:self.path]) {
            score += kPathExactMatchScore;
        } else if ([augmentedPath stringMatchesGlobPattern:self.path caseSensitive:YES] ||
                   [path stringMatchesGlobPattern:self.path caseSensitive:YES]) {
            score += kPathPartialMatchScore + [self squash:self.path.length];
        } else if (self.path.length) {
            return 0;
        }
    }

    return score;
}

- (BOOL)haveAnyComponentBesidesHostname {
    return (self.username != nil ||
            self.path != nil ||
            self.job != nil);
}

@end
