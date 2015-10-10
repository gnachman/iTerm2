//
//  iTermCommandHistoryMO+CoreDataProperties.h
//  iTerm2
//
//  Created by George Nachman on 10/10/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermCommandHistoryMO.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCommandHistoryMO (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *hostname;
@property (nullable, nonatomic, retain) NSString *username;
@property (nullable, nonatomic, retain) NSSet<iTermCommandHistoryEntryMO *> *entries;

@end

@interface iTermCommandHistoryMO (CoreDataGeneratedAccessors)

- (void)addEntriesObject:(iTermCommandHistoryEntryMO *)value;
- (void)removeEntriesObject:(iTermCommandHistoryEntryMO *)value;
- (void)addEntries:(NSSet<iTermCommandHistoryEntryMO *> *)values;
- (void)removeEntries:(NSSet<iTermCommandHistoryEntryMO *> *)values;

@end

NS_ASSUME_NONNULL_END
