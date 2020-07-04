//
//  CPSTAssertionsTests.m
//  CoreParse
//
//  Created by Christopher Miller on 5/18/12.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "CPSTAssertionsTests.h"
#import "CoreParse.h"
#import "CPSenTestKitAssertions.h"

@implementation CPSTAssertionsTests

#pragma mark Tokenization Tests

- (void)testTokenizerKeywordAssertions
{
    CPTokeniser * tk = [[CPTokeniser alloc] init];
    [tk addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"{"]];
    [tk addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"}"]];
    
    /* 2012-05-18 11:01:17.780 otest[3862:403] ts: <Keyword: {> <Keyword: }> <EOF> */
    CPTokenStream * ts = [tk tokenise:@"{}"];
    CPSTAssertKeywordEquals([ts popToken], @"{");
    CPSTAssertKeywordEquals([ts popToken], @"}");
    CPSTAssertKindOfClass([ts popToken], CPEOFToken);
}

- (void)testTokenizerIdentifierAssertion
{
    CPIdentifierToken * t = [CPIdentifierToken tokenWithIdentifier:@"foobar"];
    CPSTAssertIdentifierEquals(t, @"foobar");
}

- (void)testTokenizerNumberAssertions
{
    CPTokeniser * qTokenizer = [[CPTokeniser alloc] init];
    CPTokeniser * dTokenizer = [[CPTokeniser alloc] init];
    CPTokeniser * russianRoulette = [[CPTokeniser alloc] init];
    [qTokenizer addTokenRecogniser:[CPNumberRecogniser integerRecogniser]];
    [dTokenizer addTokenRecogniser:[CPNumberRecogniser floatRecogniser]];
    [russianRoulette addTokenRecogniser:[CPNumberRecogniser numberRecogniser]];
    
    // test basic ideas about how to recognize numbers
    NSString * qs = @"1337", * ds_us = @"13.37", * ds_uk = @"13,37";
    NSInteger q = 1337, qa = 1336, qa_v = 1, qe = 13, qea = 12, qea_v = 1;
    double d = 13.37, da = 12.37, da_v = 1.00f;
    
    CPTokenStream * ts = [qTokenizer tokenise:qs];
    CPSTAssertIntegerNumberEquals([ts peekToken], q);
    CPSTAssertIntegerNumberEqualsWithAccuracy([ts popToken], qa, qa_v);
    CPSTAssertKindOfClass([ts popToken], CPEOFToken);
    
    ts = [qTokenizer tokenise:ds_us];
    CPSTAssertIntegerNumberEquals([ts peekToken], qe);
    CPSTAssertIntegerNumberEqualsWithAccuracy([ts popToken], qea, qea_v);
    CPSTAssertKindOfClass([ts popToken], CPErrorToken);
    
    ts = [qTokenizer tokenise:ds_uk];
    CPSTAssertIntegerNumberEquals([ts peekToken], qe);
    CPSTAssertIntegerNumberEqualsWithAccuracy([ts popToken], qea, qea_v);
    CPSTAssertKindOfClass([ts popToken], CPErrorToken);

    // for some reason, the default tokenizer always uses floating point
    ts = [russianRoulette tokenise:qs];
    CPSTAssertFloatingNumberEquals([ts peekToken], q);
    CPSTAssertFloatingNumberEqualsWithAccuracy([ts popToken], qa, qa_v);
    CPSTAssertKindOfClass([ts popToken], CPEOFToken);
    
    ts = [russianRoulette tokenise:ds_us];
    CPSTAssertFloatingNumberEquals([ts peekToken], d);
    CPSTAssertFloatingNumberEqualsWithAccuracy([ts popToken], da, da_v);
    CPSTAssertKindOfClass([ts popToken], CPEOFToken);
    
    ts = [russianRoulette tokenise:ds_uk];
    CPSTAssertFloatingNumberEquals([ts peekToken], qe);
    CPSTAssertFloatingNumberEqualsWithAccuracy([ts popToken], qea, qea_v);
    CPSTAssertKindOfClass([ts popToken], CPErrorToken);
    
    ts = [dTokenizer tokenise:qs];
    CPSTAssertKindOfClass([ts popToken], CPErrorToken);
    
    ts = [dTokenizer tokenise:ds_us];
    CPSTAssertFloatingNumberEquals([ts peekToken], d);
    CPSTAssertFloatingNumberEqualsWithAccuracy([ts popToken], da, da_v);
    CPSTAssertKindOfClass([ts popToken], CPEOFToken);
    
    ts = [dTokenizer tokenise:ds_uk];
    CPSTAssertKindOfClass([ts popToken], CPErrorToken);
    
}

@end
