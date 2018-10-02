//
//  CommandUse.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermCommandHistoryCommandUseMO.h"
#import "NSObject+iTerm.h"
#import "VT100ScreenMark.h"

@implementation iTermCommandHistoryCommandUseMO (Additions)

+ (instancetype)commandHistoryCommandUseInContext:(NSManagedObjectContext *)context {
    return [NSEntityDescription insertNewObjectForEntityForName:self.entityName
                                         inManagedObjectContext:context];
}

+ (NSString *)entityName {
    return @"CommandHistoryCommandUse";
}

+ (instancetype)commandHistoryCommandUseFromDeprecatedSerialization:(id)serializedValue
                                                          inContext:(NSManagedObjectContext *)context {
    iTermCommandHistoryCommandUseMO *managedObject = [self commandHistoryCommandUseInContext:context];
    if ([serializedValue isKindOfClass:[NSArray class]]) {
        managedObject.time = serializedValue[0];
        if ([serializedValue count] > 1 && ![serializedValue[1] isKindOfClass:[NSNull class]]) {
            managedObject.directory = serializedValue[1];
        }
        if ([serializedValue count] > 2 && ![serializedValue[2] isKindOfClass:[NSNull class]]) {
            managedObject.markGuid = serializedValue[2];
        }
        if ([serializedValue count] > 3 &&
            ![serializedValue[3] isKindOfClass:[NSNull class]] &&
            [serializedValue[3] length] > 0) {
            managedObject.command = serializedValue[3];
        }
        if ([serializedValue count] > 4 && ![serializedValue[4] isKindOfClass:[NSNull class]]) {
            managedObject.code = serializedValue[4];
        }
    } else if ([serializedValue isKindOfClass:[NSNumber class]]) {
        managedObject.time = serializedValue;
    }

    return managedObject;
}

- (VT100ScreenMark *)mark {
    if (!self.markGuid) {
        return nil;
    }
    return [VT100ScreenMark markWithGuid:self.markGuid];
}

- (void)setMark:(VT100ScreenMark *)mark {
    self.markGuid = mark.guid;
}

@end
