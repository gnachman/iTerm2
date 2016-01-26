//
//  OCMockito - MKTTestLocation.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTTestLocation.h"

#import "MKTException.h"


// As of 2010-09-09, the iPhone simulator has a bug where you can't catch exceptions when they are
// thrown across NSInvocation boundaries. (See http://openradar.appspot.com/8081169 ) So instead of
// using an NSInvocation to call -failWithException: without linking in SenTestingKit, we simply
// pretend it exists on NSObject.
@interface NSObject (MTExceptionBugHack)
- (void)failWithException:(NSException *)exception;
@end


void MKTFailTest(id testCase, const char *fileName, int lineNumber, NSString *description)
{
    NSString *theFileName = @(fileName);
    NSException *failure = [MKTException failureInFile:theFileName
                                                atLine:lineNumber
                                                reason:description];
    [testCase failWithException:failure];
}

void MKTFailTestLocation(MKTTestLocation testLocation, NSString *description)
{
    MKTFailTest(testLocation.testCase, testLocation.fileName, testLocation.lineNumber, description);
}
