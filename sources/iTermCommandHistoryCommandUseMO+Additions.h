//
//  CommandUse.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>

#import "iTermCommandHistoryCommandUseMO.h"

@class iTermCommandHistoryCommandUseMO;
@class VT100ScreenMark;

@interface iTermCommandHistoryCommandUseMO (Additions)

// Setting this actually sets the markGuid.
@property(nonatomic, retain) VT100ScreenMark *mark;

+ (instancetype)commandHistoryCommandUseInContext:(NSManagedObjectContext *)context;
+ (NSString *)entityName;
+ (instancetype)commandHistoryCommandUseFromDeprecatedSerialization:(id)serializedValue
                                                          inContext:(NSManagedObjectContext *)context;

@end
