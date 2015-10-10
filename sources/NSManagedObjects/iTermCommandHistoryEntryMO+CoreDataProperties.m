//
//  iTermCommandHistoryEntryMO+CoreDataProperties.m
//  iTerm2
//
//  Created by George Nachman on 10/10/15.
//
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

#import "iTermCommandHistoryEntryMO+CoreDataProperties.h"

@implementation iTermCommandHistoryEntryMO (CoreDataProperties)

@dynamic command;
@dynamic numberOfUses;
@dynamic timeOfLastUse;
@dynamic matchLocation;
@dynamic uses;
@dynamic remoteHost;

@end
