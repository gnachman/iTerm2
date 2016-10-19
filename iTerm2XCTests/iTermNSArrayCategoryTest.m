//
//  iTermNSArrayCategoryTest.m
//  iTerm2
//
//  Created by George Nachman on 6/1/16.
//
//

#import <XCTest/XCTest.h>
#import "NSArray+iTerm.h"

@interface iTermNSArrayCategoryTest : XCTestCase

@end

@implementation iTermNSArrayCategoryTest

- (void)testObjectsOfClasses {
    NSArray *objects = @[ [NSNull null], @0, [[[NSObject alloc] init] autorelease], @1 ];
    
    NSArray *numbers = [objects objectsOfClasses:@[ [NSNumber class] ]];
    XCTAssertEqual(numbers.count, 2);
    XCTAssertTrue([numbers containsObject:@0]);
    XCTAssertTrue([numbers containsObject:@1]);
    
    NSArray *numbersAndNull = [objects objectsOfClasses:@[ [NSNumber class], [NSNull class] ]];
    XCTAssertEqual(numbersAndNull.count, 3);
    XCTAssertTrue([numbersAndNull containsObject:@0]);
    XCTAssertTrue([numbersAndNull containsObject:@1]);
    XCTAssertTrue([numbersAndNull containsObject:[NSNull null]]);
}

- (void)testAttributedComponentsJoinedByAttributedString {
    NSDictionary *attributes1 = @{ NSForegroundColorAttributeName: [NSColor whiteColor] };
    NSDictionary *attributes2 = @{ NSForegroundColorAttributeName: [NSColor blackColor] };
    NSDictionary *joinAttributes = @{ NSForegroundColorAttributeName: [NSColor redColor] };
    
    NSAttributedString *string1 = [[[NSAttributedString alloc] initWithString:@"one" attributes:attributes1] autorelease];
    NSAttributedString *string2 = [[[NSAttributedString alloc] initWithString:@"two" attributes:attributes2] autorelease];
    NSAttributedString *joiner = [[[NSAttributedString alloc] initWithString:@"," attributes:joinAttributes] autorelease];
    
    NSArray *array = @[ string1, string2 ];
    NSAttributedString *joined = [array attributedComponentsJoinedByAttributedString:joiner];
    NSMutableAttributedString *expected = [[[NSMutableAttributedString alloc] init] autorelease];
    [expected appendAttributedString:string1];
    [expected appendAttributedString:joiner];
    [expected appendAttributedString:string2];
    
    XCTAssertEqualObjects(expected, joined);
}

- (void)testMapWithBlock {
    NSArray *input = @[ @1, @2, @3 ];
    NSArray *actual = [input mapWithBlock:^id(id anObject) {
        return @([anObject integerValue] * 2);
    }];
    NSArray *expected = @[ @2, @4, @6 ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testFilteredArrayUsingBlock {
    NSArray *input = @[ @1, @2, @3, @4 ];
    NSArray *actual = [input filteredArrayUsingBlock:^BOOL(id anObject) {
        return ([anObject integerValue] % 2) == 0;
    }];
    NSArray *expected = @[ @2, @4 ];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testContainsObjectBesides {
    NSArray *empty = @[];
    NSArray *oneElement = @[ @1 ];
    NSArray *twoElements = @[ @1, @2 ];
    
    XCTAssertFalse([empty containsObjectBesides:@1]);
    
    XCTAssertFalse([oneElement containsObjectBesides:@1]);
    XCTAssertTrue([oneElement containsObjectBesides:@2]);

    XCTAssertTrue([twoElements containsObjectBesides:@0]);
    XCTAssertTrue([twoElements containsObjectBesides:@1]);
    XCTAssertTrue([twoElements containsObjectBesides:@2]);
}

- (void)testNumbersAsHexStrings {
    NSArray *inputs = @[ @1, @17, @4294967295 ];
    NSString *expected = @"0x1 0x11 0xffffffff";
    NSString *actual = [inputs numbersAsHexStrings];
    XCTAssertEqualObjects(actual, expected);
}

- (void)testComponentsJoinedWithOxfordComma_zeroElements {
    NSArray *input = @[];
    NSString *expected = @"";
    NSString *actual = [input componentsJoinedWithOxfordComma];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testComponentsJoinedWithOxfordComma_oneElement {
    NSArray *input = @[ @"one" ];
    NSString *expected = @"one";
    NSString *actual = [input componentsJoinedWithOxfordComma];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testComponentsJoinedWithOxfordComma_twoElements {
    NSArray *input = @[ @"one", @"two" ];
    NSString *expected = @"one and two";
    NSString *actual = [input componentsJoinedWithOxfordComma];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testComponentsJoinedWithOxfordComma_threeElements {
    NSArray *input = @[ @"one", @"two", @"three" ];
    NSString *expected = @"one, two, and three";
    NSString *actual = [input componentsJoinedWithOxfordComma];
    XCTAssertEqualObjects(expected, actual);
}

- (void)testComponentsJoinedWithOxfordComma_fourElements {
    NSArray *input = @[ @"one", @"two", @"three", @"four" ];
    NSString *expected = @"one, two, three, and four";
    NSString *actual = [input componentsJoinedWithOxfordComma];
    XCTAssertEqualObjects(expected, actual);
}

@end
