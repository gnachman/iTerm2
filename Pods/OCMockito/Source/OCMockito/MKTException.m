//
//  OCMockito - MKTException.m
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import "MKTException.h"


@implementation MKTException

+ (NSException *)failureInFile:(NSString *)fileName
                        atLine:(int)lineNumber
                        reason:(NSString *)reason
{
    NSDictionary *userInfo = @{@"SenTestFilenameKey": fileName,
                              @"SenTestLineNumberKey": @(lineNumber)};
    return [self exceptionWithName:@"SenTestFailureException" reason:reason userInfo:userInfo];
}

@end
