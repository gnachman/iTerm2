//
//  iTermReflectionTests.m
//  ModernTests
//
//  Covers how iTermReflectionMethodArgument extracts class names from object
//  type encodings. The Objective-C runtime does not parse quoted class names
//  in method type encodings, so these tests call the type-string parser
//  directly rather than going through a registered method.
//

#import <XCTest/XCTest.h>

#import "iTermReflection.h"

@interface iTermReflectionMethodArgument (Testing)
+ (iTermReflectionMethodArgument *)argumentForTypeString:(NSString *)typeString
                                            argumentName:(NSString *)argumentName;
@end

@interface iTermReflectionTests : XCTestCase
@end

@implementation iTermReflectionTests

- (iTermReflectionMethodArgument *)argumentForTypeString:(NSString *)typeString {
    iTermReflectionMethodArgument *argument =
        [iTermReflectionMethodArgument argumentForTypeString:typeString argumentName:@"value"];
    XCTAssertEqualObjects(argument.argumentName, @"value");
    return argument;
}

- (void)testQuotedClassNameIsExtractedWhole {
    iTermReflectionMethodArgument *argument = [self argumentForTypeString:@"@\"NSString\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"NSString");
}

- (void)testSingleCharacterClassName {
    iTermReflectionMethodArgument *argument = [self argumentForTypeString:@"@\"X\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"X");
}

- (void)testEmptyQuotedClassName {
    iTermReflectionMethodArgument *argument = [self argumentForTypeString:@"@\"\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"");
}

- (void)testUnquotedObjectFallsBackToNSObject {
    iTermReflectionMethodArgument *argument = [self argumentForTypeString:@"@"];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"NSObject");
}

@end
