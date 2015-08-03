//
//  CommandHistoryEntry.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Foundation/Foundation.h>

@class VT100RemoteHost;
@class VT100ScreenMark;

// Holds an instance of a command plus an array of individual uses of the command.
@interface CommandHistoryEntry : NSObject

// Full text of command.
@property(nonatomic, copy) NSString *command;

// Number of times used.
@property(nonatomic, assign) int uses;

// Time since reference date of last use.
@property(nonatomic, assign) NSTimeInterval lastUsed;

// Array of ComamndUse objects.
@property(nonatomic, readonly) NSMutableArray *commandUses;

// First character matched by current search.
@property(nonatomic, assign) int matchLocation;

+ (instancetype)commandHistoryEntry;

+ (instancetype)entryWithDictionary:(NSDictionary *)dict;

- (VT100ScreenMark *)lastMark;

// PWD at the time of the command
- (NSString *)lastDirectory;

- (NSDictionary *)dictionary;

- (NSComparisonResult)compareUseTime:(CommandHistoryEntry *)other;

- (CommandHistoryEntry *)copyWithoutUses;

@end
