//
//  iTermCommandHistoryCommandUseMO+CoreDataProperties.h
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermCommandHistoryCommandUseMO.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCommandHistoryCommandUseMO (CoreDataProperties)

@property (nullable, nonatomic, retain) NSNumber *code;
@property (nullable, nonatomic, retain) NSString *command;
@property (nullable, nonatomic, retain) NSString *directory;
@property (nullable, nonatomic, retain) NSString *markGuid;
@property (nullable, nonatomic, retain) NSNumber *time;
@property (nullable, nonatomic, retain) iTermCommandHistoryEntryMO *entry;

@end

NS_ASSUME_NONNULL_END
