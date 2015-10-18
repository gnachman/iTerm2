//
//  PopupEntry.m
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import "PopupEntry.h"

@implementation PopupEntry {
    double _score;
    double _hitMultiplier;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self _setDefaultValues];
    }
    return self;
}

- (void)dealloc
{
    [_mainValue release];
    [_prefix release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p s=%@ prefix=%@ score=%f hitMult=%f>",
            [self class], self, _mainValue, _prefix, _score, _hitMultiplier];
}

- (void)_setDefaultValues
{
    _hitMultiplier = 1;
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

- (double)advanceHitMult {
    _hitMultiplier *= 0.8;
    return _hitMultiplier;
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
    return [[NSNumber numberWithDouble:_score] compare:[NSNumber numberWithDouble:[otherObject score]]];
}

@end
