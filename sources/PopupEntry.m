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
@synthesize mainValue = s_;
@synthesize score = score_;
@synthesize prefix = prefix_;

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

- (double)advanceHitMult
{
    hitMultiplier_ *= 0.8;
    return hitMultiplier_;
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

@end
