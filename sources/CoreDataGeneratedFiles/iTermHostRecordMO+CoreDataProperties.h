//
//  iTermHostRecordMO+CoreDataProperties.h
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermHostRecordMO.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermHostRecordMO (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *hostname;
@property (nullable, nonatomic, retain) NSString *username;
@property (nullable, nonatomic, retain) NSSet<iTermCommandHistoryEntryMO *> *entries;
@property (nullable, nonatomic, retain) NSSet<iTermRecentDirectoryMO *> *directories;

@end

@interface iTermHostRecordMO (CoreDataGeneratedAccessors)

- (void)addEntriesObject:(iTermCommandHistoryEntryMO *)value;
- (void)removeEntriesObject:(iTermCommandHistoryEntryMO *)value;
- (void)addEntries:(NSSet<iTermCommandHistoryEntryMO *> *)values;
- (void)removeEntries:(NSSet<iTermCommandHistoryEntryMO *> *)values;

- (void)addDirectoriesObject:(iTermRecentDirectoryMO *)value;
- (void)removeDirectoriesObject:(iTermRecentDirectoryMO *)value;
- (void)addDirectories:(NSSet<iTermRecentDirectoryMO *> *)values;
- (void)removeDirectories:(NSSet<iTermRecentDirectoryMO *> *)values;

@end

NS_ASSUME_NONNULL_END
