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

@interface CommandUse()
@property(nonatomic, copy) NSString *markGuid;
@end

@implementation CommandUse

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_directory release];
    [_markGuid release];
    [_command release];
    [_code release];
    [super dealloc];
}

- (NSArray *)serializedValue {
    return @[ @(self.time),
              _directory ?: @"",
              _markGuid ?: @"",
              _command ?: @"",
              _code ?: [NSNull null] ];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] commandUseFromSerializedValue:[self serializedValue]] retain];
}

- (void)setMark:(VT100ScreenMark *)mark {
    self.markGuid = mark.guid;
}

- (VT100ScreenMark *)mark {
    if (!self.markGuid) {
        return nil;
    }
    return [VT100ScreenMark markWithGuid:self.markGuid];
}

+ (instancetype)commandUseFromSerializedValue:(id)serializedValue {
    CommandUse *commandUse = [[[CommandUse alloc] init] autorelease];
    if ([serializedValue isKindOfClass:[NSArray class]]) {
        commandUse.time = [serializedValue[0] doubleValue];
        if ([serializedValue count] > 1) {
            commandUse.directory = serializedValue[1];
        }
        if ([serializedValue count] > 2) {
            commandUse.markGuid = serializedValue[2];
        }
        if ([serializedValue count] > 3 && [serializedValue[3] length] > 0) {
            commandUse.command = serializedValue[3];
        }
        if ([serializedValue count] > 4 && ![serializedValue[4] isKindOfClass:[NSNull class]]) {
            commandUse.code = serializedValue[4];
        }
    } else if ([serializedValue isKindOfClass:[NSNumber class]]) {
        commandUse.time = [serializedValue doubleValue];
    }
    return commandUse;
}

@end
