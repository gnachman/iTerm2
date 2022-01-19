//
//  CommandHistoryEntry.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermCommandHistoryEntryMO.h"

@protocol VT100RemoteHostReading;
@class VT100ScreenMark;
@protocol VT100ScreenMarkReading;

@interface iTermCommandHistoryEntryMO (Additions)

@property(nonatomic, readonly) id<VT100ScreenMarkReading> lastMark;

// PWD at the time of the command
@property(nonatomic, readonly) NSString *lastDirectory;

+ (instancetype)commandHistoryEntryInContext:(NSManagedObjectContext *)context;
+ (instancetype)commandHistoryEntryFromDeprecatedDictionary:(NSDictionary *)dictionary
                                                  inContext:(NSManagedObjectContext *)context;
+ (NSString *)entityName;

- (NSComparisonResult)compareUseTime:(iTermCommandHistoryEntryMO *)other;

@end
