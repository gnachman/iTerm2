//
//  CommandUse.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "CommandUse.h"
#import "NSObject+iTerm.h"
#import "VT100ScreenMark.h"

NSString *const kCommandUseReleaseMarksInSession = @"kCommandUseReleaseMarksInSession";

@implementation CommandUse

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_mark release];
    [_directory release];
    [_markGuid release];
    [super dealloc];
}

- (NSArray *)serializedValue {
    return @[ @(self.time),
              _directory ?: @"",
              _mark.guid ?: [NSNull null] ];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] commandUseFromSerializedValue:[self serializedValue]] retain];
}

- (void)setMark:(VT100ScreenMark *)mark {
    if (_mark.sessionGuid) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kCommandUseReleaseMarksInSession
                                                      object:_mark.sessionGuid];
    }
    [_mark autorelease];
    _mark = [mark retain];
    if (_mark.sessionGuid) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMark)
                                                     name:kCommandUseReleaseMarksInSession
                                                   object:_mark.sessionGuid];
    }
}

- (void)clearMark {
    self.mark = nil;
}

+ (instancetype)commandUseFromSerializedValue:(id)serializedValue {
    CommandUse *commandUse = [[[CommandUse alloc] init] autorelease];
    if ([serializedValue isKindOfClass:[NSArray class]]) {
        commandUse.time = [serializedValue[0] doubleValue];
        if ([serializedValue count] > 1) {
            commandUse.directory = serializedValue[1];
        }
        if ([serializedValue count] > 2) {
            commandUse.markGuid = [serializedValue[2] nilIfNull];
        }

    } else if ([serializedValue isKindOfClass:[NSNumber class]]) {
        commandUse.time = [serializedValue doubleValue];
    }
    return commandUse;
}

@end
