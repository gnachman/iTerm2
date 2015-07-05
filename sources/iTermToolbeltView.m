#import "iTermToolbeltView.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "ToolDirectoriesView.h"
#import "ToolProfiles.h"
#import "ToolPasteHistory.h"
#import "ToolWrapper.h"
#import "ToolJobs.h"
#import "ToolNotes.h"
#import "iTermApplicationDelegate.h"
#import "iTermApplication.h"
#import "iTermDragHandleView.h"
#import "FutureMethods.h"

NSString *const kCapturedOutputToolName = @"Captured Output";
NSString *const kCommandHistoryToolName = @"Command History";
NSString *const kRecentDirectoriesToolName = @"Recent Directories";
NSString *const kJobsToolName = @"Jobs";
NSString *const kNotesToolName = @"Notes";
NSString *const kPasteHistoryToolName = @"Paste History";
NSString *const kProfilesToolName = @"Profiles";

NSString *const kToolbeltShouldHide = @"kToolbeltShouldHide";

@interface ToolbeltSplitView : NSSplitView {
    NSColor *dividerColor_;
}

- (void)setDividerColor:(NSColor *)dividerColor;

@end

@implementation ToolbeltSplitView

- (void)dealloc {
    [dividerColor_ release];
    [super dealloc];
}

- (void)setDividerColor:(NSColor *)dividerColor {
    [dividerColor_ autorelease];
    dividerColor_ = [dividerColor retain];
    [self setNeedsDisplay:YES];
}

- (NSColor *)dividerColor {
    return dividerColor_;
}

@end

@interface iTermToolbeltView () <iTermDragHandleViewDelegate>
@end

@implementation iTermToolbeltView {
    iTermDragHandleView *dragHandle_;
    ToolbeltSplitView *splitter_;
    NSMutableDictionary *tools_;
}

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";

+ (void)initialize {
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [iTermToolbeltView registerToolWithName:kCapturedOutputToolName withClass:[ToolCapturedOutputView class]];
    [iTermToolbeltView registerToolWithName:kCommandHistoryToolName withClass:[ToolCommandHistoryView class]];
    [iTermToolbeltView registerToolWithName:kRecentDirectoriesToolName withClass:[ToolDirectoriesView class]];
    [iTermToolbeltView registerToolWithName:kJobsToolName withClass:[ToolJobs class]];
    [iTermToolbeltView registerToolWithName:kNotesToolName withClass:[ToolNotes class]];
    [iTermToolbeltView registerToolWithName:kPasteHistoryToolName withClass:[ToolPasteHistory class]];
    [iTermToolbeltView registerToolWithName:kProfilesToolName withClass:[ToolProfiles class]];
}

+ (NSArray *)defaultTools
{
    return [NSArray arrayWithObjects:@"Profiles", nil];
}

+ (NSArray *)allTools {
    return [gRegisteredTools allKeys];
}

+ (NSArray *)configuredTools
{
    NSArray *tools = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey];
    if (!tools) {
        return [iTermToolbeltView defaultTools];
    }
    NSMutableArray *vettedTools = [NSMutableArray array];
    for (NSString *toolName in tools) {
        if ([gRegisteredTools objectForKey:toolName]) {
            [vettedTools addObject:toolName];
        }
    }
    return vettedTools;
}

- (id)initWithFrame:(NSRect)frame delegate:(id<iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frame];
    if (self) {
        _delegate = delegate;

        NSArray *items = [iTermToolbeltView configuredTools];
        if (!items) {
            items = [iTermToolbeltView defaultTools];
            [[NSUserDefaults standardUserDefaults] setObject:items forKey:kToolbeltPrefKey];
        }

        splitter_ = [[ToolbeltSplitView alloc] initWithFrame:NSMakeRect(0,
                                                                        0,
                                                                        frame.size.width,
                                                                        frame.size.height)];
        [splitter_ setVertical:NO];
        [splitter_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [splitter_ setDividerStyle:NSSplitViewDividerStyleThin];
        [splitter_ setDelegate:self];
        [splitter_ setDividerColor:[NSColor colorWithCalibratedWhite:122/255.0 alpha:0.25]];
        [self addSubview:splitter_];
        tools_ = [[NSMutableDictionary alloc] init];

        for (NSString *theName in items) {
            if ([iTermToolbeltView shouldShowTool:theName]) {
                [self addToolWithName:theName];
            }
        }
        dragHandle_ = [[[iTermDragHandleView alloc] initWithFrame:NSMakeRect(0, 0, 3, frame.size.height)]
                       autorelease];
        dragHandle_.delegate = self;
        dragHandle_.autoresizingMask = (NSViewHeightSizable | NSViewMaxXMargin);
        [self addSubview:dragHandle_];
    }
    return self;
}

- (void)dealloc
{
    [splitter_ release];
    [tools_ release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedWhite:237.0/255.0 alpha:1] set];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (void)shutdown
{
    while ([tools_ count]) {
        NSString *theName = [[tools_ allKeys] objectAtIndex:0];

        ToolWrapper *wrapper = [tools_ objectForKey:theName];
                if ([wrapper.tool respondsToSelector:@selector(shutdown)]) {
                        [wrapper.tool shutdown];
                }
                [wrapper setDelegate:nil];
        [tools_ removeObjectForKey:theName];
        [[wrapper retain] autorelease];
        [wrapper removeToolSubviews];
        [wrapper removeFromSuperview];
    }
}

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c
{
    [gRegisteredTools setObject:c forKey:name];
}

+ (NSDictionary *)toolsDictionary
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *toolName in gRegisteredTools) {
        [dict setObject:[[[[gRegisteredTools objectForKey:toolName] alloc] init] autorelease]
                 forKey:toolName];
    }
    return dict;
}

+ (BOOL)shouldShowTool:(NSString *)name
{
    return [[iTermToolbeltView configuredTools] indexOfObject:name] != NSNotFound;
}

- (void)toggleShowToolWithName:(NSString *)theName
{
    [iTermToolbeltView toggleShouldShowTool:theName];
}

+ (void)toggleShouldShowTool:(NSString *)theName
{
    NSMutableArray *tools = [[[iTermToolbeltView configuredTools] mutableCopy] autorelease];
    if (!tools) {
        tools = [[[iTermToolbeltView defaultTools] mutableCopy] autorelease];
    }
    if ([tools indexOfObject:theName] == NSNotFound) {
        [tools addObject:theName];
    } else {
        [tools removeObject:theName];
    }
    [[NSUserDefaults standardUserDefaults] setObject:tools forKey:kToolbeltPrefKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermToolToggled"
                                                        object:theName
                                                      userInfo:nil];
}

+ (int)numberOfVisibleTools
{
    NSArray *tools = [iTermToolbeltView configuredTools];
    if (!tools) {
        tools = [iTermToolbeltView defaultTools];
    }
    return [tools count];
}

- (void)forceSplitterSubviewsToRespectSizeConstraints
{
    NSArray *subviews = [splitter_ subviews];
    CGFloat totalSlop = 0;
    CGFloat totalDeficit = 0;
    // Calculate the total amount of slop (height beyond the minimum) and deficit (height less than
    // minimum) in all views.
    for (int i = 0; i < subviews.count; i++) {
        ToolWrapper *wrapper = subviews[i];
        CGFloat excess = wrapper.frame.size.height - wrapper.minimumHeight;
        if (excess < 0) {
            totalDeficit -= excess;
        } else {
            totalSlop += excess;
        }
    }
    if (totalDeficit > 0) {
        // One or more views is under the minimum height. Steal a fraction from each view that is
        // over the minimum.
        double fractionOfSlopToRedistribute = MIN(1, totalDeficit / totalSlop);
        CGFloat y = 0;
        for (int i = 0; i < subviews.count; i++) {
            ToolWrapper *wrapper = subviews[i];
            NSRect frame = wrapper.frame;
            CGFloat excess = wrapper.frame.size.height - wrapper.minimumHeight;
            if (excess < 0) {
                frame.size.height = wrapper.minimumHeight;
            } else {
                frame.size.height -= ceil(excess * fractionOfSlopToRedistribute);
            }
            frame.origin.y = y;
            if (i == subviews.count - 1) {
                // Last view always fills out the remainder. This takes care of accumulated rounding
                // errors.
                frame.size.height = splitter_.frame.size.height - y;
            }
            wrapper.frame = frame;
            y += frame.size.height + [splitter_ dividerThickness];
        }
    }
}

- (void)toggleToolWithName:(NSString *)theName
{
    ToolWrapper *wrapper = [tools_ objectForKey:theName];
    if (wrapper) {
        [[wrapper tool] shutdown];
        [tools_ removeObjectForKey:theName];
        [wrapper removeFromSuperview];
        [wrapper setDelegate:nil];
    } else {
        [self addToolWithName:theName];
    }
    [self forceSplitterSubviewsToRespectSizeConstraints];
}

- (BOOL)showingToolWithName:(NSString *)theName
{
    return [tools_ objectForKey:theName] != nil;
}

+ (void)populateMenu:(NSMenu *)menu
{
    NSArray *names = [[iTermToolbeltView allTools] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *theName in names) {
        NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:theName
                                                    action:@selector(toggleToolbeltTool:)
                                             keyEquivalent:@""] autorelease];
        [i setState:[iTermToolbeltView shouldShowTool:theName] ? NSOnState : NSOffState];
        [menu addItem:i];
    }
}

- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(ToolWrapper *)wrapper
{
    [splitter_ addSubview:wrapper];
    [wrapper.container addSubview:theTool];

    [wrapper setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [theTool setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [splitter_ adjustSubviews];
    [tools_ setObject:wrapper forKey:[[wrapper.name copy] autorelease]];
}

- (void)addToolWithName:(NSString *)toolName
{
    if (![gRegisteredTools objectForKey:toolName]) {
        // User could have a plist from a future version with a tool that doesn't exist here.
        return;
    }
    ToolWrapper *wrapper = [[[ToolWrapper alloc] initWithFrame:NSMakeRect(0,
                                                                          0,
                                                                          self.frame.size.width,
                                                                          self.frame.size.height / MAX(1, [iTermToolbeltView numberOfVisibleTools ] - 1))] autorelease];
    wrapper.name = toolName;
    wrapper.delegate = self;
    Class c = [gRegisteredTools objectForKey:toolName];
    if (c) {
        [self addTool:[[[c alloc] initWithFrame:NSMakeRect(0,
                                                           0,
                                                           wrapper.container.frame.size.width,
                                                           wrapper.container.frame.size.height)] autorelease]
            toWrapper:wrapper];
        [self setHaveOnlyOneTool:[self haveOnlyOneTool]];
    }
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setHaveOnlyOneTool:(BOOL)value
{
    // For KVO
}

- (void)relayoutAllTools
{
    splitter_.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
    for (ToolWrapper *wrapper in [splitter_ subviews]) {
        [wrapper relayout];
    }
}

- (id<ToolbeltTool>)toolWithName:(NSString *)name {
    return [tools_[name] tool];
}

#pragma mark - ToolWrapperDelegate

- (void)hideToolbelt {
    [[NSNotificationCenter defaultCenter] postNotificationName:kToolbeltShouldHide object:nil userInfo:nil];
}

- (BOOL)haveOnlyOneTool
{
    return [[splitter_ subviews] count] == 1;
}

#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
    [self relayoutAllTools];
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
         ofSubviewAt:(NSInteger)dividerIndex
{
    CGFloat min = 0;
    NSArray *subviews = [splitter_ subviews];
    for (int i = 0; i <= dividerIndex; i++) {
        ToolWrapper *wrapper = subviews[i];
        if (i == dividerIndex) {
            min += wrapper.minimumHeight;
        } else {
            min += wrapper.frame.size.height;
        }
        if (i > 0) {
            min += [splitView dividerThickness];
        }
    }
    return min;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
         ofSubviewAt:(NSInteger)dividerIndex
{
    CGFloat height = splitView.frame.size.height;
    NSArray *subviews = [splitter_ subviews];
    for (int i = subviews.count - 1; i > dividerIndex; i--) {
        ToolWrapper *wrapper = subviews[i];
        if (i == dividerIndex + 1) {
            height -= wrapper.minimumHeight;
        } else {
            height -= wrapper.frame.size.height;
        }
        if (i != subviews.count - 1) {
            height -= [splitView dividerThickness];
        }
    }
    return height;
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
    [splitView adjustSubviews];
    [self forceSplitterSubviewsToRespectSizeConstraints];
}

- (ToolCommandHistoryView *)commandHistoryView {
    ToolWrapper *wrapper = [tools_ objectForKey:kCommandHistoryToolName];
    return (ToolCommandHistoryView *)wrapper.tool;
}

- (ToolDirectoriesView *)directoriesView {
    ToolWrapper *wrapper = [tools_ objectForKey:@"Recent Directories"];
    return (ToolDirectoriesView *)wrapper.tool;
}

- (ToolCapturedOutputView *)capturedOutputView {
    ToolWrapper *wrapper = [tools_ objectForKey:kCapturedOutputToolName];
    return (ToolCapturedOutputView *)wrapper.tool;
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    return -[_delegate growToolbeltBy:-delta];
}

@end
