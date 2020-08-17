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
