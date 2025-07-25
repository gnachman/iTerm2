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
- (BOOL)supportsWindowLocation;
- (BOOL)supportsCreateNewTab;
- (BOOL)supportsChangeProfile;
- (BOOL)supportsOpenArrangement:(out BOOL *)tabsOnlyPtr;
- (BOOL)supportsScript;
- (BOOL)supportsColorPreset;
- (BOOL)supportsAction;
- (BOOL)supportsSnippet;
- (BOOL)supportsNamedMarks;
- (BOOL)supportsMenuItems;
- (BOOL)supportsBookmarks;
- (BOOL)supportsURLs;
@end

@interface iTermOpenQuicklyCommand : NSObject<iTermOpenQuicklyCommand>
+ (NSString *)restrictionDescription;
@end

@interface iTermOpenQuicklyInTabsWindowArrangementCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyWindowArrangementCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySearchSessionsCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySearchWindowsCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySwitchProfileCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyCreateTabCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyNoCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyScriptCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyColorPresetCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyActionCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySnippetCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyBookmarkCommand : iTermOpenQuicklyCommand
@end
