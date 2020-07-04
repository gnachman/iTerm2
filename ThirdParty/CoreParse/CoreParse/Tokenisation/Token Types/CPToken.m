//
//  CPToken.m
//  CoreParse
//
//  Created by Tom Davie on 12/02/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import "CPToken.h"

@implementation CPToken

@synthesize lineNumber;
@synthesize columnNumber;
@synthesize characterNumber;
@synthesize length;

- (NSString *)name
{
    [NSException raise:@"Abstract method called exception" format:@"CPToken is abstract, and should not have name called."];
    return @"";
}

- (NSUInteger)hash
{
    return [[self name] hash];
}

- (BOOL)isEqual:(id)object
{
    return ([object isToken] &&
            [[self name] isEqualToString:[(CPToken *)object name]]);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@>", [self name]];
}

@end

@implementation NSObject (CPIsToken)

- (BOOL)isToken
{
    return NO;
}

@end
