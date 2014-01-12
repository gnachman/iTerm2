//
//  PopupEntry.m
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import "PopupEntry.h"

@implementation PopupEntry
{
    NSString* s_;
    NSString* prefix_;
    double score_;
    double hitMultiplier_;
}

- (id)init
{
    self = [super init];
    if (self) {
        [self _setDefaultValues];
    }
    return self;
}

- (void)dealloc
{
    [s_ release];
    [prefix_ release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p s=%@ prefix=%@ score=%f hitMult=%f>",
            [self class], self, s_, prefix_, score_, hitMultiplier_];
}

- (void)_setDefaultValues
{
    hitMultiplier_ = 1;
    [self setMainValue:@""];
    [self setScore:0];
    [self setPrefix:@""];
}

+ (PopupEntry*)entryWithString:(NSString*)s score:(double)score
{
    PopupEntry* e = [[[PopupEntry alloc] init] autorelease];
    [e _setDefaultValues];
    [e setMainValue:s];
    [e setScore:score];
    
    return e;
}

- (NSString*)mainValue
{
    return s_;
}

- (void)setScore:(double)score
{
    score_ = score;
}

- (void)setMainValue:(NSString*)s
{
    [s_ autorelease];
    s_ = [s retain];
}

- (double)advanceHitMult
{
    hitMultiplier_ *= 0.8;
    return hitMultiplier_;
}

- (double)score
{
    return score_;
}

- (BOOL)isEqual:(id)o
{
    if ([o respondsToSelector:@selector(mainValue)]) {
        return [[self mainValue] isEqual:[o mainValue]];
    } else {
        return [super isEqual:o];
    }
}

- (NSComparisonResult)compare:(id)otherObject
{
    return [[NSNumber numberWithDouble:score_] compare:[NSNumber numberWithDouble:[otherObject score]]];
}

- (void)setPrefix:(NSString*)prefix
{
    [prefix_ autorelease];
    prefix_ = [prefix retain];
}

- (NSString*)prefix
{
    return prefix_;
}

@end
