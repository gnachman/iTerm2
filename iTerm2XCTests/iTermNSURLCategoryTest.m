//
//  iTermNSURLCategoryTest.m
//  iTerm2
//
//  Created by George Nachman on 4/24/16.
//
//

#import <XCTest/XCTest.h>
#import "NSURL+iTerm.h"

@interface iTermNSURLCategoryTest : XCTestCase

@end

@implementation iTermNSURLCategoryTest

#pragma mark - URLByReplacingFormatSpecifier

- (void)testURLByReplacingFormatSpecifier_QueryValue {
    NSString *string = @"https://example.com/?a=1&b=%@&c=3";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://example.com/?a=1&b=value&c=3");
}

- (void)testURLByReplacingFormatSpecifier_QueryName {
    NSString *string = @"https://example.com/?a=1&%@=2&c=3";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://example.com/?a=1&value=2&c=3");
}

- (void)testURLByReplacingFormatSpecifier_Fragment {
    NSString *string = @"https://example.com/?a=1&b=2&c=3#fragment%@";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://example.com/?a=1&b=2&c=3#fragmentvalue");
}

- (void)testURLByReplacingFormatSpecifier_Path {
    NSString *string = @"https://example.com/a/%@/b?a=1&b=2&c=3#fragment";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://example.com/a/value/b?a=1&b=2&c=3#fragment");
}

- (void)testURLByReplacingFormatSpecifier_Host {
    NSString *string = @"https://%@.example.com/a/c/b?a=1&b=2&c=3#fragment";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://value.example.com/a/c/b?a=1&b=2&c=3#fragment");
}

- (void)testURLByReplacingFormatSpecifier_User {
    NSString *string = @"https://%@:password@example.com/a/c/b?a=1&b=2&c=3#fragment";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://value:password@example.com/a/c/b?a=1&b=2&c=3#fragment");
}

- (void)testURLByReplacingFormatSpecifier_Password {
    NSString *string = @"https://user:%@@example.com/a/c/b?a=1&b=2&c=3#fragment";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertEqualObjects(url.absoluteString, @"https://user:value@example.com/a/c/b?a=1&b=2&c=3#fragment");
}

- (void)testURLByReplacingFormatSpecifier_BadURL {
    NSString *string = @" %@";
    NSURL *url = [NSURL urlByReplacingFormatSpecifier:@"%@" inString:string withValue:@"value"];
    XCTAssertNil(url);
}

#pragma mark - URLWithUserSuppliedString

- (void)testURLWithUserSuppliedString_NonAsciiPath {
    NSString *string = @"http://wiki.teamliquid.net/commons/images/thumb/a/af/Torbjörn-Barbarossa.jpg/580px-Torbjörn-Barbarossa.jpg";
    NSURL *url = [NSURL URLWithString:string];
    XCTAssertNil(url);

    url = [NSURL URLWithUserSuppliedString:string];
    XCTAssertEqualObjects(url.absoluteString, @"http://wiki.teamliquid.net/commons/images/thumb/a/af/Torbj%C3%B6rn-Barbarossa.jpg/580px-Torbj%C3%B6rn-Barbarossa.jpg");
}

- (void)testURLWithUserSuppliedString_NonAsciiFragment {
    NSString *string = @"http://example.com/path?a=b&c=d#Torbjörn";
    NSURL *url = [NSURL URLWithString:string];
    XCTAssertNil(url);

    url = [NSURL URLWithUserSuppliedString:string];
    XCTAssertEqualObjects(url.absoluteString, @"http://example.com/path?a=b&c=d#Torbj%C3%B6rn");
}

- (void)testURLWithUserSuppliedString_IDN {
    NSString *string = @"http://中国.icom.museum/";
    NSURL *url = [NSURL URLWithString:string];
    XCTAssertNil(url);

    url = [NSURL URLWithUserSuppliedString:string];
    XCTAssertEqualObjects(url.absoluteString, @"http://xn--fiqs8s.icom.museum/");
}

- (void)testURLWithUserSuppliedString_Acid {
    NSString *scheme = @"a1+-.";
    NSString *user = @"%20;";
    NSString *password = @"&=+$,é%20;&=+$,";
    NSString *host = @"á中国.%20.icom.museum";
    NSString *port = @"1";
    NSString *path = @"%20Torbjörn";
    NSString *query = @"%20国=%20中&ö";
    NSString *fragment = @"%20é./?:~ñ";
    NSString *urlString = [NSString stringWithFormat:@"%@://%@:%@@%@:%@/%@?%@#%@",
                           scheme,
                           user,
                           password,
                           host,
                           port,
                           path,
                           query,
                           fragment];
    NSURL *url = [NSURL URLWithUserSuppliedString:urlString];
    host = @"xn--1ca0960bnsf.%20.icom.museum";
    password = @"&=+$,%C3%A9%20;&=+$,";
    path = @"%20Torbj%C3%B6rn";
    query = @"%20%E5%9B%BD=%20%E4%B8%AD&%C3%B6";
    fragment = @"%20%C3%A9./?:~%C3%B1";
    urlString = [NSString stringWithFormat:@"%@://%@:%@@%@:%@/%@?%@#%@",
                 scheme,
                 user,
                 password,
                 host,
                 port,
                 path,
                 query,
                 fragment];

    XCTAssertEqualObjects(url.absoluteString, urlString);
}

- (void)testURLWithUserSuppliedString_ManyParts {
    NSString *urlString = @"https://example.com:6088/projects/repos/applications/pull-requests?create&sourceBranch=refs/heads/feature/myfeature";
    NSURL *url = [NSURL URLWithUserSuppliedString:urlString];
    XCTAssertEqualObjects(url.absoluteString, urlString);
}
- (void)testPercent {
    NSString *urlString = @"Georges-Mac-Pro:/Users/gnachman%";
    NSURL *url = [NSURL URLWithUserSuppliedString:urlString];
    XCTAssertEqualObjects(url.absoluteString, @"Georges-Mac-Pro:/Users/gnachman%25");
}

- (void)testUrlInQuery {
    NSString *urlString = @"https://google.com/search?q=http://google.com/";
    NSURL *url = [NSURL URLWithUserSuppliedString:urlString];
    XCTAssertEqualObjects(url.absoluteString, @"https://google.com/search?q=http://google.com/");
}

#pragma mark - URLByRemovingFragment

- (void)testURLByRemovingFragment_noFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByRemovingFragment];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo");
}

- (void)testURLByRemovingFragment_emptyFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo#";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByRemovingFragment];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo");
}

- (void)URLByRemovingFragment_hasFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo#bar";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByRemovingFragment];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo");
}

#pragma mark - URLByAppendingQueryParameter

- (void)testURLByAppendingQueryParameter_noQueryNoFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?x=y");
}

- (void)testURLByAppendingQueryParameter_hasQueryNoFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo?a=b";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?a=b&x=y");
}

- (void)testURLByAppendingQueryParameter_noQueryHasFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo#f";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?x=y#f");
}

- (void)testURLByAppendingQueryParameter_noQueryHasEmptyFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo#";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?x=y#");
}

- (void)testURLByAppendingQueryParameter_hasQueryHasFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo?a=b#f";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?a=b&x=y#f");
}

- (void)testURLByAppendingQueryParameter_emptyQueryNoFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo?";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?x=y");
}

- (void)testURLByAppendingQueryParameter_emptyQueryHasFragment {
    NSString *before = @"http://user:pass@iterm2.com/foo?#f";
    NSURL *url = [NSURL URLWithString:before];
    url = [url URLByAppendingQueryParameter:@"x=y"];
    NSString *after = [url absoluteString];
    XCTAssertEqualObjects(after, @"http://user:pass@iterm2.com/foo?x=y#f");
}


@end
