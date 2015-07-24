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
    _usernameHostnamePath = [iTermRule ruleWithString:@"username@hostname:path"];
    _usernameWildcardPath = [iTermRule ruleWithString:@"username@*:path"];
    _hostnamePath = [iTermRule ruleWithString:@"hostname:path"];
    _path = [iTermRule ruleWithString:@"/path"];
    _malformed1 = [iTermRule ruleWithString:@"foo:bar@baz"];

    _rules = @[ _hostname,
                _username,
                _usernameHostname,
                _usernameHostnamePath,
                _usernameWildcardPath,
                _hostnamePath,
                _path,
                _malformed1 ];
}

- (iTermRule *)highestScoringRuleWithHostname:(NSString *)hostname username:(NSString *)username path:(NSString *)path {
    int bestScore = 0;
    iTermRule *bestRule = nil;
    for (iTermRule *rule in _rules) {
        int score = [rule scoreForHostname:hostname username:username path:path];
        if (score > bestScore) {
            bestScore = score;
            bestRule = rule;
        }
    }
    return bestRule;
}

- (void)testHostname {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"hostname" username:@"x" path:@"x"];
    XCTAssertEqual(winner, _hostname);
}

- (void)testUsername {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"x" username:@"username" path:@"x"];
    XCTAssertEqual(winner, _username);
}

- (void)testUsernameHostname {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"hostname" username:@"username" path:@"x"];
    XCTAssertEqual(winner, _usernameHostname);
}

- (void)testUsernameHostnamePath {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"hostname" username:@"username" path:@"path"];
    XCTAssertEqual(winner, _usernameHostnamePath);
}

- (void)testUsernameWildcardPath {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"x" username:@"username" path:@"path"];
    XCTAssertEqual(winner, _usernameWildcardPath);
}

- (void)testHostnamePath {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"hostname" username:@"x" path:@"path"];
    XCTAssertEqual(winner, _hostnamePath);
}

- (void)testPath {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"x" username:@"x" path:@"/path"];
    XCTAssertEqual(winner, _path);
}

- (void)testNoMatch {
    iTermRule *winner = [self highestScoringRuleWithHostname:@"x" username:@"x" path:@"x"];
    XCTAssertNil(winner);
}

@end
