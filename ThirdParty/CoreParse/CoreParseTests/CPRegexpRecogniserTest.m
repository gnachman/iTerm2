//
//  CPRegexpRecogniserTest.m
//  CoreParse
//
//  Created by Francis Chong on 1/22/14.
//  Copyright (c) 2014 In The Beginning... All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CPRegexpRecogniser.h"
#import "CPKeywordToken.h"

@interface CPRegexpRecogniserTest : XCTestCase

@end

@implementation CPRegexpRecogniserTest

- (void)setUp
{
    [super setUp];
    // Put setup code here; it will be run once, before the first test case.
}

- (void)tearDown
{
    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

- (void)testRecognizeRegexp
{
    NSUInteger position = 0;
    CPRegexpRecogniser* recognizer = [[CPRegexpRecogniser alloc] initWithRegexp:[[NSRegularExpression alloc] initWithPattern:@"[a-z]+" options:0 error:nil]
                                                                       matchHandler:^CPToken *(NSString *tokenString, NSTextCheckingResult *match) {
                                                                           NSString* matchedString = [tokenString substringWithRange:[match range]];
                                                                           return [CPKeywordToken tokenWithKeyword:matchedString];
                                                                       }];
    CPKeywordToken* token = (CPKeywordToken*) [recognizer recogniseTokenInString:@"hello world" currentTokenPosition:&position];
    XCTAssertEqualObjects([token class], [CPKeywordToken class], @"should be keyword token");
    XCTAssertEqualObjects(@"hello", [token keyword], @"should match the string hello");
    
    position = 5;
    token = (CPKeywordToken*) [recognizer recogniseTokenInString:@"hello world" currentTokenPosition:&position];
    XCTAssertNil(token, @"should not match space");

    position = 6;
    token = (CPKeywordToken*) [recognizer recogniseTokenInString:@"hello world" currentTokenPosition:&position];
    XCTAssertEqualObjects([token class], [CPKeywordToken class], @"should be keyword token");
    XCTAssertEqualObjects(@"world", [token keyword], @"should match the string world");
}

- (void)testReturnNilFromCallbackWillNotSkipContent
{
    NSUInteger position = 0;
    CPRegexpRecogniser* recognizer = [[CPRegexpRecogniser alloc] initWithRegexp:[[NSRegularExpression alloc] initWithPattern:@"[a-z]+" options:0 error:nil]
                                                                       matchHandler:^CPToken *(NSString *tokenString, NSTextCheckingResult *match) {
                                                                           return nil;
                                                                       }];
    CPKeywordToken* token = (CPKeywordToken*) [recognizer recogniseTokenInString:@"hello world" currentTokenPosition:&position];
    XCTAssertNil(token, @"should be nil");
    XCTAssertTrue(position == 0, @"should not skip content if callback return nil");
}

@end
