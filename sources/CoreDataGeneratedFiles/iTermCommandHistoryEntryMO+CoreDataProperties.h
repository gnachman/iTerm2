//
//  iTermCommandHistoryEntryMO+CoreDataProperties.h
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermCommandHistoryEntryMO.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCommandHistoryEntryMO (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *command;
@property (nullable, nonatomic, retain) NSNumber *matchLocation;
@property (nullable, nonatomic, retain) NSNumber *numberOfUses;
@property (nullable, nonatomic, retain) NSNumber *timeOfLastUse;
@property (nullable, nonatomic, retain) iTermHostRecordMO *remoteHost;
@property (nullable, nonatomic, retain) NSOrderedSet<iTermCommandHistoryCommandUseMO *> *uses;

@end

@interface iTermCommandHistoryEntryMO (CoreDataGeneratedAccessors)

- (void)insertObject:(iTermCommandHistoryCommandUseMO *)value inUsesAtIndex:(NSUInteger)idx;
- (void)removeObjectFromUsesAtIndex:(NSUInteger)idx;
- (void)insertUses:(NSArray<iTermCommandHistoryCommandUseMO *> *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeUsesAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInUsesAtIndex:(NSUInteger)idx withObject:(iTermCommandHistoryCommandUseMO *)value;
- (void)replaceUsesAtIndexes:(NSIndexSet *)indexes withUses:(NSArray<iTermCommandHistoryCommandUseMO *> *)values;
- (void)addUsesObject:(iTermCommandHistoryCommandUseMO *)value;
- (void)removeUsesObject:(iTermCommandHistoryCommandUseMO *)value;
- (void)addUses:(NSOrderedSet<iTermCommandHistoryCommandUseMO *> *)values;
- (void)removeUses:(NSOrderedSet<iTermCommandHistoryCommandUseMO *> *)values;

@end

NS_ASSUME_NONNULL_END
