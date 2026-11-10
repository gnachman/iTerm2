//
//  iTermReflectionTests.m
//  ModernTests
//
//  Covers how iTermReflection extracts class names from object type
//  encodings. Compiled methods usually encode object arguments as a bare @,
//  so these tests register methods with explicit encodings to exercise the
//  quoted @"ClassName" form.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "iTermReflection.h"

static void iTermReflectionTestsNoOp(id self, SEL _cmd, id arg) {
}

@interface iTermReflectionTests : XCTestCase
@end

@implementation iTermReflectionTests

// Returns the reflected argument for a one-argument method on a fresh class
// whose only argument has the given type encoding.
- (iTermReflectionMethodArgument *)argumentForEncoding:(const char *)argumentEncoding {
    NSString *className = [NSString stringWithFormat:@"iTermReflectionTestsClass_%@",
                           [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    Class theClass = objc_allocateClassPair([NSObject class], className.UTF8String, 0);
    XCTAssertNotNil(theClass);
    SEL selector = NSSelectorFromString(@"value:");
    NSString *types = [NSString stringWithFormat:@"v@:%s", argumentEncoding];
    XCTAssertTrue(class_addMethod(theClass, selector, (IMP)iTermReflectionTestsNoOp, types.UTF8String));
    objc_registerClassPair(theClass);

    iTermReflection *reflection = [[iTermReflection alloc] initWithClass:theClass selector:selector];
    XCTAssertEqual(reflection.arguments.count, 1);
    iTermReflectionMethodArgument *argument = reflection.arguments.firstObject;
    XCTAssertEqualObjects(argument.argumentName, @"value");
    return argument;
}

- (void)testQuotedClassNameIsExtractedWhole {
    iTermReflectionMethodArgument *argument = [self argumentForEncoding:"@\"NSString\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"NSString");
}

- (void)testSingleCharacterClassName {
    iTermReflectionMethodArgument *argument = [self argumentForEncoding:"@\"X\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"X");
}

- (void)testEmptyQuotedClassName {
    iTermReflectionMethodArgument *argument = [self argumentForEncoding:"@\"\""];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"");
}

- (void)testUnquotedObjectFallsBackToNSObject {
    iTermReflectionMethodArgument *argument = [self argumentForEncoding:"@"];
    XCTAssertEqual(argument.type, iTermReflectionMethodArgumentTypeObject);
    XCTAssertEqualObjects(argument.className, @"NSObject");
}

@end
