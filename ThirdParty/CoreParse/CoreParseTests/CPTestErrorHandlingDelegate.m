//
//  CPTestErrorHandlingDelegate.m
//  CoreParse
//
//  Created by Thomas Davie on 05/02/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import "CPTestErrorHandlingDelegate.h"

@implementation CPTestErrorHandlingDelegate

@synthesize hasEncounteredError;

- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token
{
    return YES;
}

- (NSArray *)tokeniser:(CPTokeniser *)tokeniser willProduceToken:(CPToken *)token
{
    return [NSArray arrayWithObject:token];
}

- (NSUInteger)tokeniser:(CPTokeniser *)tokeniser didNotFindTokenOnInput:(NSString *)input position:(NSUInteger)position error:(NSString **)errorMessage
{
    *errorMessage = @"Found something that wasn't a comment";
    NSRange nextSlashStar = [input rangeOfString:@"/*" options:NSLiteralSearch range:NSMakeRange(position, [input length] - position)];
    return nextSlashStar.location;
}

- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    return syntaxTree;
}

- (CPRecoveryAction *)parser:(CPParser *)parser didEncounterErrorOnInput:(CPTokenStream *)inputStream expecting:(NSSet *)acceptableTokens
{
    hasEncounteredError = YES;
    return [CPRecoveryAction recoveryActionDeletingCurrentToken];
}

@end
