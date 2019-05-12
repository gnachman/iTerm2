//
//  iTermMigrationHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/1/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermMigrationHelper : NSObject

+ (void)migrateApplicationSupportDirectoryIfNeeded;
+ (void)recursiveMigrateBookmarks:(NSDictionary*)node path:(NSArray*)path;

@end
