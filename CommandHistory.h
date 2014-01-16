//
//  CommandHistory.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Foundation/Foundation.h>

extern NSString *const kCommandHistoryDidChangeNotificationName;

@class VT100RemoteHost;
@class VT100ScreenMark;

@interface CommandHistoryEntry : NSObject

// Full text of command.
@property(nonatomic, copy) NSString *command;

// Number of times used.
@property(nonatomic, assign) int uses;

// Time since reference date of last use.
@property(nonatomic, assign) NSTimeInterval lastUsed;

// NSNumber times since reference date
@property(nonatomic, readonly) NSMutableArray *useTimes;

- (VT100ScreenMark *)lastMark;

@end

@interface CommandHistory : NSObject

+ (instancetype)sharedInstance;

- (void)addCommand:(NSString *)command onHost:(VT100RemoteHost *)host withMark:(VT100ScreenMark *)mark;

- (NSArray *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host;

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host;

- (NSArray *)entryArrayByExpandingAllUsesInEntryArray:(NSArray *)array;

- (void)eraseHistory;

@end
