#import <Cocoa/Cocoa.h>
#import "ToolWrapper.h"
#import "FutureMethods.h"

@class ToolCapturedOutputView;
@class ToolCommandHistoryView;
@class ToolDirectoriesView;
@class ToolbeltSplitView;

extern NSString *const kCapturedOutputToolName;
extern NSString *const kCommandHistoryToolName;
extern NSString *const kRecentDirectoriesToolName;
extern NSString *const kJobsToolName;
extern NSString *const kNotesToolName;
extern NSString *const kPasteHistoryToolName;
extern NSString *const kProfilesToolName;

// Notification posted when all windows should hide their toolbelts.
extern NSString *const kToolbeltShouldHide;

@interface iTermToolbeltView : NSView <NSSplitViewDelegate, ToolWrapperDelegate>

@property(nonatomic, assign) id<iTermToolbeltViewDelegate> delegate;
+ (NSArray *)configuredTools;

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c;
+ (void)populateMenu:(NSMenu *)menu;
+ (void)toggleShouldShowTool:(NSString *)theName;
+ (int)numberOfVisibleTools;
+ (NSArray *)allTools;

- (id)initWithFrame:(NSRect)frame delegate:(id<iTermToolbeltViewDelegate>)delegate;

// Is the tool visible?
- (BOOL)showingToolWithName:(NSString *)theName;

- (void)toggleToolWithName:(NSString *)theName;

// Do prefs say the tool is visible?
+ (BOOL)shouldShowTool:(NSString *)name;

- (BOOL)haveOnlyOneTool;
- (void)shutdown;

- (ToolCommandHistoryView *)commandHistoryView;
- (ToolDirectoriesView *)directoriesView;
- (ToolCapturedOutputView *)capturedOutputView;

- (void)relayoutAllTools;

#pragma mark - Testing

- (id<ToolbeltTool>)toolWithName:(NSString *)name;

@end
