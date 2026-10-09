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
- (BOOL)supportsSessionContents;
@end

@interface iTermOpenQuicklyCommand : NSObject<iTermOpenQuicklyCommand>
+ (NSString *)restrictionDescription;
// What to type to start a query in this command’s mode, such as “/g ”.
+ (NSString *)queryPrefix;
@end

@interface iTermOpenQuicklyInTabsWindowArrangementCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklyWindowArrangementCommand : iTermOpenQuicklyCommand
@end

@interface iTermOpenQuicklySearchSessionsCommand : iTermOpenQuicklyCommand
@end

// Searches the text in every session's buffer, not just its metadata.
@interface iTermOpenQuicklySearchSessionContentsCommand : iTermOpenQuicklyCommand
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
