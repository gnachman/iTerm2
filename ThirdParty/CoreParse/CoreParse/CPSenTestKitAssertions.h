//
//  CPSenTestKitAssertions.h
//  CoreParse
//
//  Created by Christopher Miller on 5/18/12.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#pragma mark General Assertions

/*
 * Note that you can have this fail under CocoaPods. All you need to do is remove the "libpods.a" item from the unit testing target's linked libraries. This removes duplicate symbols which kludge the test.
 */
#define CPSTAssertKindOfClass(obj, cls) \
    do { \
        id _obj = obj; \
        XCTAssertTrue([_obj isKindOfClass:[cls class]], @"Expecting a kind of class %@; got class %@ from object %@.", NSStringFromClass([_obj class]), NSStringFromClass([cls class]), _obj); \
    } while (0)
#define _CPSTAssertKindOfClass_Unsafe(obj, cls) XCTAssertTrue([obj isKindOfClass:[cls class]], @"Expecting a kind of class %@; got class %@ from object %@.", NSStringFromClass([obj class]), NSStringFromClass([cls class]), obj);

#pragma mark Token Assertions

#define CPSTAssertKeywordEquals(token, expectation) \
    do { \
        CPKeywordToken * t = (CPKeywordToken *)token; /* this escapes the potential multiple invocations of popToken */ \
        _CPSTAssertKindOfClass_Unsafe(t, CPKeywordToken); \
        XCTAssertEqualObjects([t keyword], expectation, @"Keyword doesn't match expectation."); \
    } while (0)
#define CPSTAssertIdentifierEquals(token, expectation) \
    do { \
        CPIdentifierToken * _t = (CPIdentifierToken *)token; \
        _CPSTAssertKindOfClass_Unsafe(_t, CPIdentifierToken); \
        XCTAssertEqualObjects([_t identifier], expectation, @"Identifier doesn't match expectation."); \
    } while (0)
#define CPSTAssertIntegerNumberEquals(token, expectation) \
    do { \
        CPNumberToken * t = (CPNumberToken *)token; /* this escapes the potential multiple invocations of popToken */ \
        _CPSTAssertKindOfClass_Unsafe(t, CPNumberToken); \
        NSNumber * n = [t number]; \
        XCTAssertTrue(0==strcmp([n objCType], @encode(NSInteger)), @"Type expectation failure. Wanted %s, got %s.", @encode(NSInteger), [n objCType]); \
        XCTAssertEqual([n integerValue], ((NSInteger)expectation), @"Number fails expectation."); \
    } while (0)
#define CPSTAssertIntegerNumberEqualsWithAccuracy(token, expectation, accuracy) \
    do { \
        CPNumberToken * t = (CPNumberToken *)token; \
        _CPSTAssertKindOfClass_Unsafe(t, CPNumberToken); \
        NSNumber * n = [t number]; \
        XCTAssertTrue(0==strcmp([n objCType], @encode(NSInteger)), @"Type expectation failure. Wanted %s, got %s.", @encode(NSInteger), [n objCType]); \
        XCTAssertEqualWithAccuracy([n integerValue], ((NSInteger)expectation), ((NSInteger)accuracy), @"Number fails expectation."); \
    } while (0)
#define CPSTAssertFloatingNumberEquals(token, expectation) \
    do { \
        CPNumberToken * t = (CPNumberToken *)token; \
        _CPSTAssertKindOfClass_Unsafe(t, CPNumberToken); \
        NSNumber * n = [t number]; \
        XCTAssertTrue(0==strcmp([n objCType], @encode(double)), @"Type expectation failure. Wanted %s, got %s.", @encode(double), [n objCType]); \
        XCTAssertEqual([n doubleValue], ((double)expectation), @"Number fails expectation."); \
    } while (0)
#define CPSTAssertFloatingNumberEqualsWithAccuracy(token, expectation, accuracy) \
    do { \
        CPNumberToken * t = (CPNumberToken *)token; \
        _CPSTAssertKindOfClass_Unsafe(t, CPNumberToken); \
        NSNumber * n = [t number]; \
        XCTAssertTrue(0==strcmp([n objCType], @encode(double)), @"Type expectation failure. Wanted %s, got %s.", @encode(double), [n objCType]); \
        XCTAssertEqualWithAccuracy([n doubleValue], ((double)expectation), ((double)accuracy), @"Number fails expectation."); \
    } while (0)
