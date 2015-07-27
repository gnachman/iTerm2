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
    iTermRule *_usernameWildcardPath;  // username@*:path
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
    _usernameWildcardPath = [iTermRule ruleWithString:@"username@*:/path"];
    _hostnamePath = [iTermRule ruleWithString:@"hostname:/path"];
    _path = [iTermRule ruleWithString:@"/path"];
    _malformed1 = [iTermRule ruleWithString:@"/foo:bar@baz"];

    _rules = @[ _hostname,
                _username,
                _usernameHostname,
                _usernameHostnamePath,
                _usernameWildcardPath,
                _hostnamePath,
                _path,
                _malformed1 ];
}

- (NSArray *)matchingRulesSortedByScoreWithHostname:(NSString *)hostname username:(NSString *)username path:(NSString *)path {
    NSMutableArray *matching = [NSMutableArray array];
    for (iTermRule *rule in _rules) {
        int score = [rule scoreForHostname:hostname username:username path:path];
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
    NSArray *expected = @[ _usernameHostnamePath, _usernameHostname, _hostnamePath, _hostname,
                           _usernameWildcardPath, _username,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardPath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"/path"];
    NSArray *expected = @[ _usernameWildcardPath, _username,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testHostnamePath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"/path"];
    NSArray *expected = @[ _hostnamePath, _hostname,
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

@end
