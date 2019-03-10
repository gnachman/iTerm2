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

    iTermRule *_hostnameJob;  // hostname&job
    iTermRule *_usernameJob;  // username@&job
    iTermRule *_usernameHostnameJob;  // username@hostname&job
    iTermRule *_usernameHostnamePathJob;  // username@hostname:path&job
    iTermRule *_usernamePathJob;  // username@*:path&job
    iTermRule *_usernameWildcardStartPathJob;  // username@*hostname:path&job
    iTermRule *_usernameWildcardEndPathJob;  // username@hostname*:path&job
    iTermRule *_usernameWildcardStartEndPathJob;  // username@*hostname*:path&job
    iTermRule *_usernameWildcardMiddlePathJob;  // username@host*name:path&job
    iTermRule *_usernameWildcardAllPathJob;  // username@*host*name*:path&job
    iTermRule *_usernameWildcardActualPathJob; // username@service*.*.hostname.com:path&job
    iTermRule *_hostnamePathJob;  // hostname:path&job
    iTermRule *_pathJob;  // /path&job
    iTermRule *_job;  // &job

    iTermRule *_malformed1;  // foo:bar@baz
    iTermRule *_malformed2;  // foo:bar@baz&job

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

    _hostnameJob = [iTermRule ruleWithString:@"hostname&job"];
    _usernameJob = [iTermRule ruleWithString:@"username@&job"];
    _usernameHostnameJob = [iTermRule ruleWithString:@"username@hostname&job"];
    _usernameHostnamePathJob = [iTermRule ruleWithString:@"username@hostname:/path&job"];
    _usernamePathJob = [iTermRule ruleWithString:@"username@*:/path&job"];
    _usernameWildcardStartPathJob = [iTermRule ruleWithString:@"username@*hostname:/path&job"];
    _usernameWildcardEndPathJob = [iTermRule ruleWithString:@"username@hostname*:/path&job"];
    _usernameWildcardStartEndPathJob = [iTermRule ruleWithString:@"username@*hostname*:/path&job"];
    _usernameWildcardMiddlePathJob = [iTermRule ruleWithString:@"username@host*name:/path&job"];
    _usernameWildcardAllPathJob = [iTermRule ruleWithString:@"username@*host*name*:/path&job"];
    _usernameWildcardActualPathJob = [iTermRule ruleWithString:@"username@service*.*.hostname.com:/path&job"];
    _hostnamePathJob = [iTermRule ruleWithString:@"hostname:/path&job"];
    _pathJob = [iTermRule ruleWithString:@"/path&job"];
    _job = [iTermRule ruleWithString:@"&job*"];

    _malformed1 = [iTermRule ruleWithString:@"/foo:bar@baz"];
    _malformed2 = [iTermRule ruleWithString:@"/foo:bar@baz&job"];

    _rules = @[
               _hostname,
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

               _hostnameJob,
               _usernameJob,
               _usernameHostnameJob,
               _usernameHostnamePathJob,
               _usernamePathJob,
               _usernameWildcardStartPathJob,
               _usernameWildcardEndPathJob,
               _usernameWildcardStartEndPathJob,
               _usernameWildcardMiddlePathJob,
               _usernameWildcardAllPathJob,
               _usernameWildcardActualPathJob,
               _hostnamePathJob,
               _pathJob,
               _job,

               _malformed1,
               _malformed2,
               ];
}

- (NSArray *)matchingRulesSortedByScoreWithHostname:(NSString *)hostname
                                           username:(NSString *)username
                                               path:(NSString *)path
                                                job:(NSString *)job {
    NSMutableArray *matching = [NSMutableArray array];
    for (iTermRule *rule in _rules) {
        double score = [rule scoreForHostname:hostname username:username path:path job:job];
        if (score > 0) {
            [matching addObject:rule];
        }
    }
    return [matching sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        int score1 = [obj1 scoreForHostname:hostname username:username path:path job:job];
        int score2 = [obj2 scoreForHostname:hostname username:username path:path job:job];
        return [@(score2) compare:@(score1)];
    }];
}

- (void)testHostname {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"x"
                                                              job:@"x"];
    XCTAssertEqualObjects(rules, @[ _hostname ]);
}

- (void)testUsername {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"x"
                                                              job:@"x"];
    XCTAssertEqualObjects(rules, @[ _username ]);
}

- (void)testUsernameHostname {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"x"
                                                              job:@"x"];
    NSArray *expected = @[ _usernameHostname, _hostname, _username ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameHostnamePath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"x"];
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
                                                             path:@"/path"
                                                              job:@"x"];
    NSArray *expected = @[ _usernamePath,
                           _username,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardStartPath {
  NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.hostname"
                                                       username:@"username"
                                                           path:@"/path"
                                                            job:@"x"];
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
                                                           path:@"/path"
                                                            job:@"x"];
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
                                                           path:@"/path"
                                                            job:@"x"];
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
                                                           path:@"/path"
                                                            job:@"x"];
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
                                                             path:@"/path"
                                                              job:@"x"];
    NSArray *expected = @[ _hostnamePath,
                           _hostname,
                           _path ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testPath {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"/path"
                                                              job:@"x"];
    XCTAssertEqualObjects(rules, @[ _path ]);
}

#pragma mark Job

- (void)testHostnameJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"x"
                                                              job:@"job"];
    NSArray *expected = @[ _hostnameJob,
                           _hostname,
                           _job];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"x"
                                                              job:@"job"];
    NSArray *expected = @[ _usernameJob,
                           _job,
                           _username,
                           ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameHostnameJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"x"
                                                              job:@"job"];
    NSArray *expected = @[ _usernameHostnameJob,
                           _hostnameJob,
                           _usernameHostname,
                           _hostname,
                           _usernameJob,
                           _job,
                           _username ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameHostnamePathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[ _usernameHostnamePathJob,
                           _usernameHostnameJob,
                           _usernameWildcardStartPathJob,
                           _usernameWildcardEndPathJob,
                           _usernameWildcardStartEndPathJob,
                           _usernameWildcardMiddlePathJob,
                           _usernameWildcardAllPathJob,
                           _hostnamePathJob,
                           _hostnameJob,
                           _usernameHostnamePath,
                           _usernameHostname,
                           _usernameWildcardStartPath,
                           _usernameWildcardEndPath,
                           _usernameWildcardStartEndPath,
                           _usernameWildcardMiddlePath,
                           _usernameWildcardAllPath,
                           _hostnamePath,
                           _hostname,
                           _usernamePathJob,
                           _usernameJob,
                           _pathJob,
                           _job,
                           _usernamePath,
                           _username,
                           _path ];

    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _usernamePathJob,
                          _usernameJob,
                          _pathJob,
                          _job,
                          _usernamePath,
                          _username,
                          _path,
                           ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardStartPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.hostname"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _usernameWildcardStartPathJob,
                          _usernameWildcardStartEndPathJob,
                          _usernameWildcardAllPathJob,
                          _usernameWildcardStartPath,
                          _usernameWildcardStartEndPath,
                          _usernameWildcardAllPath,
                          _usernamePathJob,
                          _usernameJob,
                          _pathJob,
                          _job,
                          _usernamePath,
                          _username,
                          _path
                          ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardEndPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname.com"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _usernameWildcardEndPathJob,
                          _usernameWildcardStartEndPathJob,
                          _usernameWildcardAllPathJob,
                          _usernameWildcardEndPath,
                          _usernameWildcardStartEndPath,
                          _usernameWildcardAllPath,
                          _usernamePathJob,
                          _usernameJob,
                          _pathJob,
                          _job,
                          _usernamePath,
                          _username,
                          _path
                          ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardStartEndPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.hostname.com"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _usernameWildcardStartEndPathJob,
                          _usernameWildcardAllPathJob,
                          _usernameWildcardStartEndPath,
                          _usernameWildcardAllPath,
                          _usernamePathJob,
                          _usernameJob,
                          _pathJob,
                          _job,
                          _usernamePath,
                          _username,
                          _path
                          ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testUsernameWildcardActualPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"service01.prod.hostname.com"
                                                         username:@"username"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _usernameWildcardStartEndPathJob,
                          _usernameWildcardAllPathJob,
                          _usernameWildcardActualPathJob,
                          _usernameWildcardStartEndPath,
                          _usernameWildcardAllPath,
                          _usernameWildcardActualPath,
                          _usernamePathJob,
                          _usernameJob,
                          _pathJob,
                          _job,
                          _usernamePath,
                          _username,
                          _path,
                          ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testHostnamePathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"hostname"
                                                         username:@"x"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[
                          _hostnamePathJob,
                          _hostnameJob,
                          _hostnamePath,
                          _hostname,
                          _pathJob,
                          _job,
                          _path,
                          ];
    XCTAssertEqualObjects(rules, expected);
}

- (void)testPathJob {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"/path"
                                                              job:@"job"];
    NSArray *expected = @[ _pathJob, _job, _path ];
    XCTAssertEqualObjects(rules, expected);
}

#pragma mark -

- (void)testNoMatch {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"x"
                                                              job:@"x"];
    XCTAssertEqualObjects(rules, @[ ]);
}

- (void)testScoreMonotonicInWildcardRuleHostLength {
    iTermRule *exactHostnameRule = [iTermRule ruleWithString:@"hostname12"];
    iTermRule *longHostnameRule = [iTermRule ruleWithString:@"hostname*"];
    iTermRule *shortHostnameRule = [iTermRule ruleWithString:@"h*"];

    double exactScore = [exactHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path" job:@"job"];
    double longScore = [longHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path" job:@"job"];
    double shortScore = [shortHostnameRule scoreForHostname:@"hostname12" username:@"george" path:@"/path" job:@"job"];

    XCTAssertGreaterThan(longScore, shortScore);
    XCTAssertGreaterThan(exactScore, longScore);
}

- (void)testScoreMonotonicInWildcardRulePathLength {
    iTermRule *exactPathRule = [iTermRule ruleWithString:@"/path123"];
    iTermRule *longPathRule = [iTermRule ruleWithString:@"/path*"];
    iTermRule *shortPathRule = [iTermRule ruleWithString:@"/p*"];

    double exactScore = [exactPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123" job:@"job"];
    double longScore = [longPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123" job:@"job"];
    double shortScore = [shortPathRule scoreForHostname:@"hostname" username:@"george" path:@"/path123" job:@"job"];

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

    double longScore = [longRule scoreForHostname:@"hostname" username:@"george" path:path job:@"job"];
    double shortScore = [shortRule scoreForHostname:@"hostname" username:@"george" path:path job:@"job"];

    XCTAssertGreaterThan(longScore, shortScore);
}

- (void)testSticky {
    iTermRule *nonStickyRule = [iTermRule ruleWithString:@"hostname"];
    iTermRule *stickyRule = [iTermRule ruleWithString:@"!hostname"];

    XCTAssertFalse(nonStickyRule.isSticky);
    XCTAssertTrue(stickyRule.isSticky);
}

- (void)testJobGlobWorks {
    NSArray *rules = [self matchingRulesSortedByScoreWithHostname:@"x"
                                                         username:@"x"
                                                             path:@"x"
                                                              job:@"jobber"];
    NSArray *expected = @[
                          _job,
                          ];
    XCTAssertEqualObjects(rules, expected);
}

@end
