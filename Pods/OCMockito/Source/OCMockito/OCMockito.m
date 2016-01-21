//
//  OCMockito - OCMockito.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "OCMockito.h"

#import "MKTAtLeastTimes.h"
#import "MKTExactTimes.h"
#import "MKTMockitoCore.h"
#import "MKTTestLocation.h"


static BOOL isValidMock(id mock, id testCase, const char *fileName, int lineNumber, NSString *functionName)
{
    NSString *underlyingClassName = NSStringFromClass([mock class]);
    if (!([underlyingClassName isEqualToString:@"MKTObjectMock"] ||
          [underlyingClassName isEqualToString:@"MKTProtocolMock"] ||
          [underlyingClassName isEqualToString:@"MKTClassObjectMock"] ||
          [underlyingClassName isEqualToString:@"MKTObjectAndProtocolMock"]))
    {
        NSString *actual = nil;
        if (!underlyingClassName)
            actual = @"nil";
        else
            actual = [@"type " stringByAppendingString:underlyingClassName];

        NSString *description = [NSString stringWithFormat:
                                 @"Argument passed to %@ should be a mock but is %@",
                                 functionName, actual];
        MKTFailTest(testCase, fileName, lineNumber, description);
        return NO;
    }

    return YES;
}


MKTOngoingStubbing *MKTGivenWithLocation(id testCase, const char *fileName, int lineNumber, ...)
{
    MKTMockitoCore *mockitoCore = [MKTMockitoCore sharedCore];
    return [mockitoCore stubAtLocation:MKTTestLocationMake(testCase, fileName, lineNumber)];
}

id MKTVerifyWithLocation(id mock, id testCase, const char *fileName, int lineNumber)
{
    if (!isValidMock(mock, testCase, fileName, lineNumber, @"verify()"))
        return nil;

    return MKTVerifyCountWithLocation(mock, MKTTimes(1), testCase, fileName, lineNumber);
}

id MKTVerifyCountWithLocation(id mock, id mode, id testCase, const char *fileName, int lineNumber)
{
    if (!isValidMock(mock, testCase, fileName, lineNumber, @"verifyCount()"))
        return nil;

    MKTMockitoCore *mockitoCore = [MKTMockitoCore sharedCore];
    return [mockitoCore verifyMock:mock
                          withMode:mode
                        atLocation:MKTTestLocationMake(testCase, fileName, lineNumber)];
}

id MKTTimes(NSUInteger wantedNumberOfInvocations)
{
    return [MKTExactTimes timesWithCount:wantedNumberOfInvocations];
}

id MKTNever()
{
    return MKTTimes(0);
}

id MKTAtLeast(NSUInteger minimumWantedNumberOfInvocations)
{
    return [MKTAtLeastTimes timesWithMinimumCount:minimumWantedNumberOfInvocations];
}

id MKTAtLeastOnce()
{
    return MKTAtLeast(1);
}
