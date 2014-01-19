//
//  CommandUse.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "CommandUse.h"

@implementation CommandUse

- (void)dealloc {
    [_mark release];
    [_directory release];
    [super dealloc];
}

- (NSArray *)serializedValue {
    return @[ @(self.time), _directory ?: @"" ];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] commandUseFromSerializedValue:[self serializedValue]] retain];
}

+ (instancetype)commandUseFromSerializedValue:(id)serializedValue {
    CommandUse *commandUse = [[[CommandUse alloc] init] autorelease];
    if ([serializedValue isKindOfClass:[NSArray class]]) {
        commandUse.time = [serializedValue[0] doubleValue];
        if ([serializedValue count] > 1) {
            commandUse.directory = serializedValue[1];
        }
    } else if ([serializedValue isKindOfClass:[NSNumber class]]) {
        commandUse.time = [serializedValue doubleValue];
    }
    return commandUse;
}

@end
