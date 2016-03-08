#import "iTermToolbeltView.h"

#import "FutureMethods.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermDragHandleView.h"
#import "iTermToolWrapper.h"
#import "iTermToolbeltSplitView.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "ToolDirectoriesView.h"
#import "ToolJobs.h"
#import "ToolNotes.h"
#import "ToolPasteHistory.h"
#import "ToolProfiles.h"

NSString *const kCapturedOutputToolName = @"Captured Output";
NSString *const kCommandHistoryToolName = @"Command History";
NSString *const kRecentDirectoriesToolName = @"Recent Directories";
NSString *const kJobsToolName = @"Jobs";
NSString *const kNotesToolName = @"Notes";
NSString *const kPasteHistoryToolName = @"Paste History";
NSString *const kProfilesToolName = @"Profiles";

NSString *const kToolbeltShouldHide = @"kToolbeltShouldHide";

@interface iTermToolbeltView () <iTermDragHandleViewDelegate>
@end

@implementation iTermToolbeltView {
    iTermDragHandleView *_dragHandle;
    iTermToolbeltSplitView *_splitter;
    NSMutableDictionary *_tools;
}

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";

#pragma mark - Public class methods

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

+ (NSArray *)allTools {
    return [gRegisteredTools allKeys];
}

+ (NSArray *)configuredTools {
    NSArray *tools = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey];
    if (!tools) {
        return [iTermToolbeltView defaultTools];
    }
    NSMutableArray *vettedTools = [NSMutableArray array];
    for (NSString *toolName in tools) {
        if (gRegisteredTools[toolName]) {
            [vettedTools addObject:toolName];
        }
    }
    return vettedTools;
}

+ (void)populateMenu:(NSMenu *)menu {
    NSArray *names = [[iTermToolbeltView allTools] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *theName in names) {
        NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:theName
                                                    action:@selector(toggleToolbeltTool:)
                                             keyEquivalent:@""] autorelease];
        [i setState:[iTermToolbeltView shouldShowTool:theName] ? NSOnState : NSOffState];
        [menu addItem:i];
    }
}

+ (void)toggleShouldShowTool:(NSString *)theName {
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

+ (int)numberOfVisibleTools {
    NSArray *tools = [iTermToolbeltView configuredTools];
    if (!tools) {
        tools = [iTermToolbeltView defaultTools];
    }
    return [tools count];
}

+ (BOOL)shouldShowTool:(NSString *)name {
    return [[iTermToolbeltView configuredTools] indexOfObject:name] != NSNotFound;
}

#pragma mark - Private class methods

+ (NSArray *)defaultTools {
    return [NSArray arrayWithObjects:@"Profiles", nil];
}

+ (void)registerToolWithName:(NSString *)name withClass:(Class)c {
    [gRegisteredTools setObject:c forKey:name];
}

+ (NSDictionary *)toolsDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *toolName in gRegisteredTools) {
        [dict setObject:[[[[gRegisteredTools objectForKey:toolName] alloc] init] autorelease]
                 forKey:toolName];
    }
    return dict;
}

#pragma mark - NSObject

- (instancetype)initWithFrame:(NSRect)frame delegate:(id<iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frame];
    if (self) {
        _delegate = delegate;

        NSArray *items = [iTermToolbeltView configuredTools];
        if (!items) {
            items = [iTermToolbeltView defaultTools];
            [[NSUserDefaults standardUserDefaults] setObject:items forKey:kToolbeltPrefKey];
        }

        _splitter = [[iTermToolbeltSplitView alloc] initWithFrame:NSMakeRect(0,
                                                                             0,
                                                                             frame.size.width,
                                                                             frame.size.height)];
        [_splitter setVertical:NO];
        [_splitter setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [_splitter setDividerStyle:NSSplitViewDividerStyleThin];
        [_splitter setDelegate:self];
        [_splitter setDividerColor:[NSColor colorWithCalibratedWhite:122/255.0 alpha:0.25]];
        [self addSubview:_splitter];

        _tools = [[NSMutableDictionary alloc] init];

        for (NSString *theName in items) {
            if ([iTermToolbeltView shouldShowTool:theName]) {
                [self addToolWithName:theName];
            }
        }
        _dragHandle = [[[iTermDragHandleView alloc] initWithFrame:NSMakeRect(0, 0, 3, frame.size.height)]
                       autorelease];
        _dragHandle.delegate = self;
        _dragHandle.autoresizingMask = (NSViewHeightSizable | NSViewMaxXMargin);
        [self addSubview:_dragHandle];
    }
    return self;
}

- (void)dealloc {
    [_splitter release];
    [_tools release];
    [super dealloc];
}

#pragma mark - NSView

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedWhite:237.0/255.0 alpha:1] set];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - APIs

- (void)shutdown {
    while ([_tools count]) {
        NSString *theName = [[_tools allKeys] objectAtIndex:0];

        iTermToolWrapper *wrapper = [_tools objectForKey:theName];
        if ([wrapper.tool respondsToSelector:@selector(shutdown)]) {
            [wrapper.tool shutdown];
        }
        [wrapper setDelegate:nil];
        [_tools removeObjectForKey:theName];
        [[wrapper retain] autorelease];
        [wrapper removeToolSubviews];
        [wrapper removeFromSuperview];
    }
}

- (void)toggleToolWithName:(NSString *)theName {
    iTermToolWrapper *wrapper = [_tools objectForKey:theName];
    if (wrapper) {
        [[wrapper tool] shutdown];
        [_tools removeObjectForKey:theName];
        [wrapper removeFromSuperview];
        [wrapper setDelegate:nil];
    } else {
        [self addToolWithName:theName];
    }
    [self forceSplitterSubviewsToRespectSizeConstraints];
}

- (BOOL)showingToolWithName:(NSString *)theName {
    return [_tools objectForKey:theName] != nil;
}

- (ToolDirectoriesView *)directoriesView {
    iTermToolWrapper *wrapper = [_tools objectForKey:@"Recent Directories"];
    return (ToolDirectoriesView *)wrapper.tool;
}

- (ToolCapturedOutputView *)capturedOutputView {
    iTermToolWrapper *wrapper = [_tools objectForKey:kCapturedOutputToolName];
    return (ToolCapturedOutputView *)wrapper.tool;
}

#pragma mark - Testing APIs

- (id<ToolbeltTool>)toolWithName:(NSString *)name {
    return [_tools[name] tool];
}

#pragma mark - Private

- (void)forceSplitterSubviewsToRespectSizeConstraints {
    NSArray *subviews = [_splitter subviews];
    CGFloat totalSlop = 0;
    CGFloat totalDeficit = 0;
    // Calculate the total amount of slop (height beyond the minimum) and deficit (height less than
    // minimum) in all views.
    for (int i = 0; i < subviews.count; i++) {
        iTermToolWrapper *wrapper = subviews[i];
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
            iTermToolWrapper *wrapper = subviews[i];
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
                frame.size.height = _splitter.frame.size.height - y;
            }
            wrapper.frame = frame;
            y += frame.size.height + [_splitter dividerThickness];
        }
    }
}

- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(iTermToolWrapper *)wrapper {
    [_splitter addSubview:wrapper];
    [wrapper.container addSubview:theTool];

    [wrapper setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [theTool setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_splitter adjustSubviews];
    [_tools setObject:wrapper forKey:[[wrapper.name copy] autorelease]];
}

- (void)addToolWithName:(NSString *)toolName {
    if (![gRegisteredTools objectForKey:toolName]) {
        // User could have a plist from a future version with a tool that doesn't exist here.
        return;
    }
    iTermToolWrapper *wrapper = [[[iTermToolWrapper alloc] initWithFrame:NSMakeRect(0,
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
    }
}

- (void)relayoutAllTools {
    _splitter.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
    for (iTermToolWrapper *wrapper in [_splitter subviews]) {
        [wrapper relayout];
    }
}

#pragma mark - ToolWrapperDelegate

- (BOOL)haveOnlyOneTool {
    return [[_splitter subviews] count] == 1;
}

- (void)hideToolbelt {
    [[NSNotificationCenter defaultCenter] postNotificationName:kToolbeltShouldHide object:nil userInfo:nil];
}

- (void)toggleShowToolWithName:(NSString *)theName {
    [iTermToolbeltView toggleShouldShowTool:theName];
}

- (ToolCommandHistoryView *)commandHistoryView {
    iTermToolWrapper *wrapper = [_tools objectForKey:kCommandHistoryToolName];
    return (ToolCommandHistoryView *)wrapper.tool;
}

#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification {
    [self relayoutAllTools];
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
         ofSubviewAt:(NSInteger)dividerIndex {
    CGFloat min = 0;
    NSArray *subviews = [_splitter subviews];
    for (int i = 0; i <= dividerIndex; i++) {
        iTermToolWrapper *wrapper = subviews[i];
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
         ofSubviewAt:(NSInteger)dividerIndex {
    CGFloat height = splitView.frame.size.height;
    NSArray *subviews = [_splitter subviews];
    for (int i = subviews.count - 1; i > dividerIndex; i--) {
        iTermToolWrapper *wrapper = subviews[i];
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

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    [splitView adjustSubviews];
    [self forceSplitterSubviewsToRespectSizeConstraints];
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    return -[_delegate growToolbeltBy:-delta];
}

- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle {
    [_delegate toolbeltDidFinishGrowing];
}

@end
