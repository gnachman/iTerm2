//
//  OCHamcrest - HCAssertThat.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Docs: http://hamcrest.github.com/OCHamcrest/
//  Source: https://github.com/hamcrest/OCHamcrest
//

#import "HCAssertThat.h"

#import "HCStringDescription.h"
#import "HCMatcher.h"


/**
    Create OCUnit failure

    With OCUnit's extension to NSException, this is effectively the same as
@code
[NSException failureInFile: [NSString stringWithUTF8String:fileName]
                    atLine: lineNumber
           withDescription: description]
@endcode
    except we use an NSInvocation so that OCUnit (SenTestingKit) does not have to be linked.
 */
static NSException *createOCUnitException(const char* fileName, int lineNumber, __unsafe_unretained NSString *description)
{
    __unsafe_unretained NSException *result = nil;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL selector = @selector(failureInFile:atLine:withDescription:);
#pragma clang diagnostic pop

    NSMethodSignature *signature = [[NSException class] methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:[NSException class]];
    [invocation setSelector:selector];

    __unsafe_unretained id fileArg = @(fileName);
    [invocation setArgument:&fileArg atIndex:2];
    [invocation setArgument:&lineNumber atIndex:3];
    [invocation setArgument:&description atIndex:4];

    [invocation invoke];
    [invocation getReturnValue:&result];
    return result;
}

static NSException *createAssertThatFailure(const char *fileName, int lineNumber, NSString *description)
{
    // If the Hamcrest client has linked to OCUnit, generate an OCUnit failure.
    if (NSClassFromString(@"SenTestCase") != Nil)
        return createOCUnitException(fileName, lineNumber, description);

    NSString *failureReason = [NSString stringWithFormat:@"%s:%d: matcher error: %@",
                                                        fileName, lineNumber, description];
    return [NSException exceptionWithName:@"Hamcrest Error" reason:failureReason userInfo:nil];
}


#pragma mark -

// As of 2010-09-09, the iPhone simulator has a bug where you can't catch
// exceptions when they are thrown across NSInvocation boundaries. (See
// dmaclach's comment at http://openradar.appspot.com/8081169 ) So instead of
// using an NSInvocation to call failWithException:assertThatFailure without
// linking in OCUnit, we simply pretend it exists on NSObject.
@interface NSObject (HCExceptionBugHack)
- (void)failWithException:(NSException *)exception;
@end

void HC_assertThatWithLocation(id testCase, id actual, id<HCMatcher> matcher,
                                           const char *fileName, int lineNumber)
{
    if (![matcher matches:actual])
    {
        HCStringDescription *description = [HCStringDescription stringDescription];
        [[[description appendText:@"Expected "]
                       appendDescriptionOf:matcher]
                       appendText:@", but "];
        [matcher describeMismatchOf:actual to:description];

        NSException *assertThatFailure = createAssertThatFailure(fileName, lineNumber,
                                                                 [description description]);
        [testCase failWithException:assertThatFailure];
    }
}
