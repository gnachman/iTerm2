#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "iTermToolWrapper.h"

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
@property(nonatomic, readonly) ToolDirectoriesView *directoriesView;
@property(nonatomic, readonly) ToolCapturedOutputView *capturedOutputView;

// Returns an array of tool keys.
+ (NSArray *)allTools;

// Returns an array of tool keys for tools to show.
+ (NSArray *)configuredTools;

+ (void)populateMenu:(NSMenu *)menu;
+ (void)toggleShouldShowTool:(NSString *)theName;
+ (int)numberOfVisibleTools;
+ (BOOL)shouldShowTool:(NSString *)name;

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<iTermToolbeltViewDelegate>)delegate;

// Stop timers, etc., releasing any internal references to self.
- (void)shutdown;

- (void)toggleToolWithName:(NSString *)theName;

// Is the tool visible?
- (BOOL)showingToolWithName:(NSString *)theName;

- (void)relayoutAllTools;

#pragma mark - Testing

- (id<ToolbeltTool>)toolWithName:(NSString *)name;

@end
