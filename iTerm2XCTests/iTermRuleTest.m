//
//  iTermRuleTest.m
//  iTerm2
//
//  Created by George Nachman on 7/24/15.
//
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "iTermRule.h"

@interface iTermRuleTest : XCTestCase

@end

@implementation iTermRuleTest {
    iTermRule *_hostname;  // hostname
    iTermRule *_username;  // username@
    iTermRule *_usernameHostname;  // username@hostname
    iTermRule *_usernameHostnamePath;  // username@hostname:path
    iTermRule *_usernamePath;  // username@*:path
    iTermRule *_usernameWildcardStartPath;  // username@*hostname:path
    iTermRule *_usernameWildcardEndPath;  // username@hostname*:path
    iTermRule *_usernameWildcardStartEndPath;  // username@*hostname*:path
    iTermRule *_usernameWildcardMiddlePath;  // username@host*name:path
    iTermRule *_usernameWildcardAllPath;  // username@*host*name*:path
    iTermRule *_usernameWildcardActualPath; // username@service*.*.hostname.com:path
    iTermRule *_hostnamePath;  // hostname:path
    iTermRule *_path;  // /path
    iTermRule *_malformed1;  // foo:bar@baz

    NSArray *_rules;
}

- (void)setUp {
    [super setUp];
    _hostname = [iTermRule ruleWithString:@"hostname"];
    _username = [iTermRule ruleWithString:@"username@"];
    _usernameHostname = [iTermRule ruleWithString:@"username@hostname"];
    _usernameHostnamePath = [iTermRule ruleWithString:@"username@hostname:/path"];
    _usernamePath = [iTermRule ruleWithString:@"username@*:/path"];
  
    _usernameWildcardStartPath = [iTermRule ruleWithString:@"username@*hostname:/path"];
    _usernameWildcardEndPath = [iTermRule ruleWithString:@"username@hostname*:/path"];
    _usernameWildcardStartEndPath = [iTermRule ruleWithString:@"username@*hostname*:/path"];
    _usernameWildcardMiddlePath = [iTermRule ruleWithString:@"username@host*name:/path"];
    _usernameWildcardAllPath = [iTermRule ruleWithString:@"username@*host*name*:/path"];
    _usernameWildcardActualPath = [iTermRule ruleWithString:@"username@service*.*.hostname.com:/path"];
  
    _hostnamePath = [iTermRule ruleWithString:@"hostname:/path"];
    _path = [iTermRule ruleWithString:@"/path"];
    _malformed1 = [iTermRule ruleWithString:@"/foo:bar@baz"];

    _rules = @[ _hostname,
                _username,
                _usernameHostname,
                _usernameHostnamePath,
                _usernamePath,
                _usernameWildcardStartPath,
                _usernameWildcardEndPath,
                _usernameWildcardStartEndPath,
                _usernameWildcardMiddlePath,
                _usernameWildcardAllPath,
                _usernameWildcardActualPath,
                _hostnamePath,
                _path,
                _malformed1 ];
}

- (NSArray *)matchingRulesSortedByScoreWithHostname:(NSString *)hostname username:(NSString *)username path:(NSString *)path {
    NSMutableArray *matching = [NSMutableArray array];
    for (iTermRule *rule in _rules) {
        double score = [rule scoreForHostname:hostname username:username path:path];
        if (score > 0) {
            [matching addObject:rule];
        }
    }
    return [matching sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int score1 = [obj1 scoreForHostname:hostname username:username path:path];
        int score2 = [obj2 scoreForHostname:hostname username:username path:path];
        return [@(score2) compare:@(score1)];
    }];
}

- (void)testHostname {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"x"];
    XCTAssertEqualObjects(rules, @[ _hostname ]);
}

- (void)testUsername {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"x"];
    XCTAssertEqualObjects(rules, @[ _username ]);
}

- (void)testUsernameHostname {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"x"];
    NSArray *expected = @[ _usernameHostname, _hostname, _username ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameHostnamePath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"/path"];
    NSArray *expected = @[ _usernameHostnamePath,
                           _usernameHostname,
                           _usernameWildcardStartPath,
                           _usernameWildcardEndPath,
                           _usernameWildcardStartEndPath,
                           _usernameWildcardMiddlePath,
                           _usernameWildcardAllPath,
                           _hostnamePath,
                           _hostname,
                           _usernamePath,
                           _username,
                           _path ];

    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardPath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"/path"];
    NSArray *expected = @[ _usernamePath,
                           _username,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardStartPath {
  NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.hostname"
                                                       username:@"username"
                                                           path:@"/path"];
  NSArray *expected = @[ _usernameWildcardStartPath,
                         _usernameWildcardStartEndPath,
                         _usernameWildcardAllPath,
                         _usernamePath,
                         _username,
                         _path ];
  XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardEndPath {
  NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname.com"
                                                       username:@"username"
                                                           path:@"/path"];
  NSArray *expected = @[ _usernameWildcardEndPath,
                         _usernameWildcardStartEndPath,
                         _usernameWildcardAllPath,
                         _usernamePath,
                         _username,
                         _path ];
  XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardStartEndPath {
  NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.hostname.com"
                                                       username:@"username"
                                                           path:@"/path"];
  NSArray *expected = @[ _usernameWildcardStartEndPath,
                         _usernameWildcardAllPath,
                         _usernamePath,
                         _username,
                         _path ];
  XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardActualPath {
  NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.prod.hostname.com"
                                                       username:@"username"
                                                           path:@"/path"];
  NSArray *expected = @[ _usernameWildcardStartEndPath,
                         _usernameWildcardAllPath,
                         _usernameWildcardActualPath,
                         _usernamePath,
                         _username,
                         _path ];
  XCTAssertEqualObjects(rules, expected);
}


- (void)testHostnamePath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"/path"];
    NSArray *expected = @[ _hostnamePath,
                           _hostname,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testPath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"/path"];
    XCTAssertEqualObjects(rules, @[ _path ]);
}

- (void)testNoMatch {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"x"];
    XCTAssertEqualObjects(rules, @[ ]);
}

- (void)testScoreMonotonicInWildcardRuleHostLength {
    iTermRule *exactHostnameRule = [iTermRule ruleWithString:@"hostname12"];
    iTermRule *longHostnameRule = [iTermRule ruleWithString:@"hostname*"];
    iTermRule *shortHostnameRule = [iTermRule ruleWithString:@"h*"];

    double exactScore = [exactHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path"];
    double longScore = [longHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path"];
    double shortScore = [shortHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path"];

    XCTAssertGreaterThan(longScore, shortScore);
    XCTAssertGreaterThan(exactScore, longScore);
}

- (void)testScoreMonotonicInWildcardRulePathLength {
    iTermRule *exactPathRule = [iTermRule ruleWithString:@"/path123"];
    iTermRule *longPathRule = [iTermRule ruleWithString:@"/path*"];
    iTermRule *shortPathRule = [iTermRule ruleWithString:@"/p*"];

    double exactScore = [exactPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123"];
    double longScore = [longPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123"];
    double shortScore = [shortPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123"];

    XCTAssertGreaterThan(longScore, shortScore);
    XCTAssertGreaterThan(exactScore, longScore);
}

- (void)testScoreMonotonicInWildcardRulePathLength_VeryLongRule {
    NSMutableString *longString = [NSMutableString string];
    for (int i = 0; i < 1024; i++) {
        [longString appendString:@"x"];
    }

    NSString *longRuleString = [NSString stringWithFormat:@"/x%@*", longString];
    NSString *shortRuleString = [NSString stringWithFormat:@"/%@*", longString];
    NSString *path = [NSString stringWithFormat:@"/xx%@", longString];

    iTermRule *longRule = [iTermRule ruleWithString:longRuleString];
    iTermRule *shortRule = [iTermRule ruleWithString:shortRuleString];

    double longScore = [longRule scoreForHostname:@"hostname" username:@"george" path:path];
    double shortScore = [shortRule scoreForHostname:@"hostname" username:@"george" path:path];

    XCTAssertGreaterThan(longScore, shortScore);
}

- (void)testSticky {
    iTermRule *nonStickyRule = [iTermRule ruleWithString:@"hostname"];
    iTermRule *stickyRule = [iTermRule ruleWithString:@"!hostname"];
    
    XCTAssertFalse(nonStickyRule.isSticky);
    XCTAssertTrue(stickyRule.isSticky);
}

@end
