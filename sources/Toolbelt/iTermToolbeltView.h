#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "iTermToolWrapper.h"
#import "PTYSplitView.h"

@protocol PTYSplitViewDelegate;
@class ToolCapturedOutputView;
@class ToolCommandHistoryView;
@class ToolDirectoriesView;
@class ToolJobs;
@class ToolNamedMarks;
@class ToolStatus;
@class ToolbeltSplitView;

extern NSString *const kActionsToolName;
extern NSString *const kCapturedOutputToolName;
extern NSString *const kCommandHistoryToolName;
extern NSString *const kRecentDirectoriesToolName;
extern NSString *const kJobsToolName;
extern NSString *const kNotesToolName;
extern NSString *const kPasteHistoryToolName;
extern NSString *const kProfilesToolName;
extern NSString *const kDynamicToolsDidChange;
extern NSString *const kStatusToolName;

extern NSString *const iTermToolbeltDidRegisterDynamicToolNotification;

// Notification posted when all windows should hide their toolbelts.
extern NSString *const kToolbeltShouldHide;

@interface iTermToolbeltView : NSView <PTYSplitViewDelegate, ToolWrapperDelegate>

@property(nonatomic, assign) id<iTermToolbeltViewDelegate> delegate;
@property(nonatomic, readonly) ToolDirectoriesView *directoriesView;
@property(nonatomic, readonly) ToolCapturedOutputView *capturedOutputView;
@property(nonatomic, readonly) ToolJobs *jobsView;
@property(nonatomic, retain) NSDictionary *proportions;

+ (NSDictionary *)savedProportions;

// Returns an array of tool keys.
+ (NSArray *)allTools;

// Returns an array of tool keys for tools to show ignoring profile type.
+ (NSArray *)configuredTools;

// An array of tool keys that we can actually use.
+ (NSArray<NSString *> *)availableConfiguredToolsForProfileType:(ProfileType)profileType;

+ (void)populateMenu:(NSMenu *)menu;
+ (void)toggleShouldShowTool:(NSString *)theName;
+ (int)numberOfVisibleToolsForProfileType:(ProfileType)profileType;
+ (BOOL)shouldShowTool:(NSString *)name
           profileType:(ProfileType)profileType;
+ (NSArray<NSString *> *)builtInToolNames;

// Tool names double as stable identifiers (dictionary keys, prefs, menu-item
// identifiers, notification objects), so the raw name stays English. This maps a
// known built-in tool name to its localized display title for showing in the UI.
// Dynamic (user-named) tools are not in the map and pass through unchanged.
+ (NSString *)localizedToolNameForToolName:(NSString *)name;

// Returns `names` ordered by the localized display title that `displayNameForName`
// returns for each name, using a locale-aware, Finder-style comparison. This keeps the
// menu ordering matched to what the user actually sees. The block is injectable so the
// sort key can be exercised by tests independent of the runtime locale.
+ (NSArray<NSString *> *)toolNames:(NSArray<NSString *> *)names
   sortedByLocalizedNameUsingBlock:(NSString *(^)(NSString *name))displayNameForName;

+ (void)registerDynamicToolWithIdentifier:(NSString *)identifier name:(NSString *)name URL:(NSString *)url revealIfAlreadyRegistered:(BOOL)revealIfAlreadyRegistered;

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<iTermToolbeltViewDelegate>)delegate;

// Stop timers, etc., releasing any internal references to self.
- (void)shutdown;

- (void)toggleToolWithName:(NSString *)theName;

// Is the tool visible?
- (BOOL)showingToolWithName:(NSString *)theName;

- (void)relayoutAllTools;
- (void)restoreFromState:(NSDictionary *)state;
- (NSDictionary *)restorableState;
- (void)refreshTools;

#pragma mark - Testing

- (id<ToolbeltTool>)toolWithName:(NSString *)name;
- (void)windowBackgroundColorDidChange;

@end
