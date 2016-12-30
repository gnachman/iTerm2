//
//  iTermRecentDirectoryMO+CoreDataProperties.h
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermRecentDirectoryMO.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermRecentDirectoryMO (CoreDataProperties)

@property (nullable, nonatomic, retain) NSString *path;
@property (nullable, nonatomic, retain) NSNumber *useCount;
@property (nullable, nonatomic, retain) NSNumber *lastUse;
@property (nullable, nonatomic, retain) NSNumber *starred;
@property (nullable, nonatomic, retain) iTermHostRecordMO *remoteHost;

@end

NS_ASSUME_NONNULL_END
