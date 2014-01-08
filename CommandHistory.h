//
//  CommandHistory.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Foundation/Foundation.h>

@class VT100RemoteHost;

@interface CommandHistoryEntry : NSObject

// Full text of command.
@property(nonatomic, copy) NSString *command;

// Number of times used.
@property(nonatomic, assign) int uses;

// Time since reference date of last use.
@property(nonatomic, assign) NSTimeInterval lastUsed;

@end

@interface CommandHistory : NSObject

+ (instancetype)sharedInstance;

- (void)addCommand:(NSString *)command onHost:(VT100RemoteHost *)host;

- (NSArray *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host;

@end
