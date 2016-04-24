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
