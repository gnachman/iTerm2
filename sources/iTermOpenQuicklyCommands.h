//
//  iTermOpenQuicklyCommands.h
//  iTerm2
//
//  Created by George Nachman on 3/7/16.
//
//

#import <Foundation/Foundation.h>

@protocol iTermOpenQuicklyCommand<NSObject>
@property(nonatomic, copy) NSString *text;
+ (NSString *)tipTitle;
+ (NSString *)tipDetail;
+ (NSString *)command;

- (BOOL)supportsSessionLocation;
- (BOOL)supportsCreateNewTab;
- (BOOL)supportsChangeProfile;
- (BOOL)supportsOpenArrangement;
@end

@interface iTermOpenQuicklyCommand : NSObject<iTermOpenQuicklyCommand>
+ (NSString *)restrictionDescription;
@end

@interface iTermOpenQuicklyWindowArrangementCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySearchSessionsCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySwitchProfileCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyCreateTabCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyNoCommand : iTermOpenQuicklyCommand
@end

