//
//  CommandHistoryEntry.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermCommandHistoryEntryMO+Additions.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermCommandHistoryCommandUseMO.h"
#import "iTermCommandHistoryEntryMO.h"

// Keys for serializing an entry
static NSString *const kCommand = @"command";
static NSString *const kUses = @"uses";
static NSString *const kLastUsed = @"last used";
static NSString *const kCommandUses = @"use times";  // The name is a historical artifact

@implementation iTermCommandHistoryEntryMO (iTermShellHistoryController)

+ (instancetype)commandHistoryEntryInContext:(NSManagedObjectContext *)context {
    return [NSEntityDescription insertNewObjectForEntityForName:self.entityName
                                         inManagedObjectContext:context];
}

+ (NSString *)entityName {
    return @"CommandHistoryEntry";
}

+ (instancetype)commandHistoryEntryFromDeprecatedDictionary:(NSDictionary *)dict
                                                  inContext:(NSManagedObjectContext *)context {
    iTermCommandHistoryEntryMO *managedObject =
        [NSEntityDescription insertNewObjectForEntityForName:@"CommandHistoryEntry"
                                      inManagedObjectContext:context];
    managedObject.command = dict[kCommand];
    managedObject.timeOfLastUse = dict[kLastUsed];
    managedObject.numberOfUses = dict[kUses];
    for (id serializedCommandUse in dict[kCommandUses]) {
        iTermCommandHistoryCommandUseMO *useManagedObject =
            [iTermCommandHistoryCommandUseMO commandHistoryCommandUseFromDeprecatedSerialization:serializedCommandUse
                                                                                       inContext:context];
        assert(useManagedObject);

        useManagedObject.entry = managedObject;
        useManagedObject.command = managedObject.command;
        [managedObject addUsesObject:useManagedObject];
    }

    return managedObject;

}

// Core data is a piece of garbage. The generated code throws an exception when there's a
// one-to-many relationship. These methods route around the damage.
// http://stackoverflow.com/questions/7385439/exception-thrown-in-nsorderedset-generated-accessors
- (void)removeUsesObject:(iTermCommandHistoryCommandUseMO *)value {
    if (![self.uses containsObject:value]) {
        return;
    }
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:[self.uses indexOfObject:value]];
    NSString *const key = @"uses";
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:key];
    [[self primitiveValueForKey:key] removeObject:value];
    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:key];
}

- (void)addUsesObject:(iTermCommandHistoryCommandUseMO *)value {
    if ([self.uses containsObject:value]) {
        return;
    }
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:self.uses.count];
    NSString *const key = @"uses";
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexSet forKey:key];
    [[self primitiveValueForKey:key] addObject:value];
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexSet forKey:key];
}

- (VT100ScreenMark *)lastMark {
    iTermCommandHistoryCommandUseMO *use = [self.uses lastObject];
    return use.mark;
}

- (NSString *)lastDirectory {
    iTermCommandHistoryCommandUseMO *use = [self.uses lastObject];
    return use.directory.length > 0 ? use.directory : nil;
}

- (NSComparisonResult)compareUseTime:(iTermCommandHistoryEntryMO *)other {
    return [(other.timeOfLastUse ?: @0) compare:(self.timeOfLastUse ?: @0)];
}

- (NSComparisonResult)compare:(iTermCommandHistoryEntryMO *)other {
    return [@(other.score) compare:@(self.score)];
}

- (double)score {
    const double uses = MAX(0, self.numberOfUses.doubleValue);
    const double age = MAX(0, [NSDate timeIntervalSinceReferenceDate] - self.timeOfLastUse.doubleValue);
    const double usePower = [iTermAdvancedSettingsModel commandHistoryUsePower];
    const double agePower = [iTermAdvancedSettingsModel commandHistoryAgePower];
    return pow(log10(10 + uses), usePower) / pow(log10(10 + age), agePower);
}

@end
