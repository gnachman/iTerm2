//
//  iTermSoundPlayer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/6/19.
//

#import "iTermSoundPlayer.h"
#import "DebugLogging.h"
#import "NSArray+iTerm.h"

#import <Cocoa/Cocoa.h>

@implementation iTermSoundPlayer {
    NSSound *_sound;
}

+ (NSString *)keyClickPath {
    return [[NSBundle bundleForClass:[self class]] pathForResource:@"keyclick" ofType:@"m4a"];
}

+ (instancetype)keyClick {
    static iTermSoundPlayer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithPath:[self keyClickPath]];
    });
    return instance;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _sound = [[NSSound alloc] initWithContentsOfFile:path byReference:NO];
    }
    return self;
}

- (void)play {
    [_sound play];
}

@end
