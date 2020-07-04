//
//  CPRegexpRecogniserTest.m
//  CoreParse
//
//  Created by Francis Chong on 1/22/14.
//  Copyright (c) 2014 In The Beginning... All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CPTokeniser.h"
#import "CPKeywordRecogniser.h"
#import "CPKeywordToken.h"
#import "CPEOFToken.h"

@interface CPWillFinishDelegateTest : XCTestCase <CPTokeniserDelegate>

@end

@implementation CPWillFinishDelegateTest

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

- (void)testWillFinishCalled
{
	CPTokeniser *tokeniser = [[CPTokeniser alloc] init];
	tokeniser.delegate = self;
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"{"]];
    [tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"}"]];
    CPTokenStream *tokenStream = [tokeniser tokenise:@"{}"];
    CPTokenStream *expectedTokenStream = [CPTokenStream tokenStreamWithTokens:[NSArray arrayWithObjects:[CPKeywordToken tokenWithKeyword:@"{"], [CPKeywordToken tokenWithKeyword:@"}"], [CPKeywordToken tokenWithKeyword:@"done"], [CPEOFToken eof], nil]];
    XCTAssertEqualObjects(tokenStream, expectedTokenStream, @"tokeniser:WillFinish:stream not called", nil);
}

- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token
{
	return YES;
}

- (void)tokeniserWillFinish:(CPTokeniser *)tokeniser stream:(CPTokenStream *)stream
{
	[stream pushToken:[CPKeywordToken tokenWithKeyword:@"done"]];
}

@end
