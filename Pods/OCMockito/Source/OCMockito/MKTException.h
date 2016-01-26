//
//  OCMockito - MKTException.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>


@interface MKTException : NSException

+ (NSException *)failureInFile:(NSString *)fileName
                        atLine:(int)lineNumber
                        reason:(NSString *)reason;

@end
