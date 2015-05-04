#import "ToolbeltView.h"
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
#import "iTermCollapsingSplitView.h"
#import "iTermDragHandleView.h"
#import "FutureMethods.h"
#import "PseudoTerminal.h"  // TODO: Use delegacy

NSString *kCapturedOutputToolName = @"Captured Output";
NSString *kCommandHistoryToolName = @"Command History";

NSString *const kToolbeltShouldHide = @"kToolbeltShouldHide";

@interface ToolbeltView () <iTermDragHandleViewDelegate>
@end

@implementation ToolbeltView {
    iTermDragHandleView *dragHandle_;

    iTermCollapsingSplitView *splitter_;
    NSMutableDictionary *tools_;
    PseudoTerminal *term_;   // weak
}

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";

+ (void)initialize
{
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [ToolbeltView registerToolWithName:kCapturedOutputToolName withClass:[ToolCapturedOutputView class]];
    [ToolbeltView registerToolWithName:kCommandHistoryToolName
                             withClass:[ToolCommandHistoryView class]];
    [ToolbeltView registerToolWithName:@"Recent Directories" withClass:[ToolDirectoriesView class]];
    [ToolbeltView registerToolWithName:@"Jobs" withClass:[ToolJobs class]];
    [ToolbeltView registerToolWithName:@"Notes" withClass:[ToolNotes class]];
    [ToolbeltView registerToolWithName:@"Paste History" withClass:[ToolPasteHistory class]];
    [ToolbeltView registerToolWithName:@"Profiles" withClass:[ToolProfiles class]];
}

+ (NSArray *)defaultTools
{
    return [NSArray arrayWithObjects:@"Profiles", nil];
}

+ (NSArray *)allTools
{
    return [gRegisteredTools allKeys];
}

+ (NSArray *)configuredTools
{
    NSArray *tools = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey];
    if (!tools) {
        return [ToolbeltView defaultTools];
    }
    NSMutableArray *vettedTools = [NSMutableArray array];
    for (NSString *toolName in tools) {
        if ([gRegisteredTools objectForKey:toolName]) {
            [vettedTools addObject:toolName];
        }
    }
    return vettedTools;
}

- (id)initWithFrame:(NSRect)frame term:(PseudoTerminal *)term
{
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        term_ = term;

        NSArray *items = [ToolbeltView configuredTools];
        if (!items) {
            items = [ToolbeltView defaultTools];
            [[NSUserDefaults standardUserDefaults] setObject:items forKey:kToolbeltPrefKey];
        }

        splitter_ = [[iTermCollapsingSplitView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
        splitter_.dividerColor = [NSColor colorWithCalibratedWhite:122/255.0 alpha:1];
        [self addSubview:splitter_];
        tools_ = [[NSMutableDictionary alloc] init];

        for (NSString *theName in items) {
            if ([ToolbeltView shouldShowTool:theName]) {
                [self addToolWithName:theName];
            }
        }
        dragHandle_ = [[[iTermDragHandleView alloc] initWithFrame:NSMakeRect(0, 0, 3, frame.size.height)]
                       autorelease];
        dragHandle_.delegate = self;
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
    return [[ToolbeltView configuredTools] indexOfObject:name] != NSNotFound;
}

- (void)toggleShowToolWithName:(NSString *)theName
{
        [ToolbeltView toggleShouldShowTool:theName];
}

+ (void)toggleShouldShowTool:(NSString *)theName
{
    NSMutableArray *tools = [[[ToolbeltView configuredTools] mutableCopy] autorelease];
    if (!tools) {
        tools = [[[ToolbeltView defaultTools] mutableCopy] autorelease];
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
    NSArray *tools = [ToolbeltView configuredTools];
    if (!tools) {
        tools = [ToolbeltView defaultTools];
    }
    return [tools count];
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
    [splitter_ update];
}

- (BOOL)showingToolWithName:(NSString *)theName
{
    return [tools_ objectForKey:theName] != nil;
}

+ (void)populateMenu:(NSMenu *)menu
{
    NSArray *names = [[ToolbeltView allTools] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *theName in names) {
        NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:theName
                                                    action:@selector(toggleToolbeltTool:)
                                             keyEquivalent:@""] autorelease];
        [i setState:[ToolbeltView shouldShowTool:theName] ? NSOnState : NSOffState];
        [menu addItem:i];
    }
}

- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(ToolWrapper *)wrapper
{
    [splitter_ addItem:wrapper];
    theTool.frame = wrapper.container.bounds;
    [wrapper.container addSubview:theTool];

    [splitter_ update];
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
                                                                          self.frame.size.height / MAX(1, [ToolbeltView numberOfVisibleTools ] - 1))] autorelease];
    wrapper.name = toolName;
    wrapper.term = term_;
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
    for (ToolWrapper *wrapper in [splitter_ items]) {
        [wrapper relayout];
    }
}

#pragma mark - ToolWrapperDelegate

- (void)hideToolbelt {
    [[NSNotificationCenter defaultCenter] postNotificationName:kToolbeltShouldHide object:nil userInfo:nil];
}

- (BOOL)haveOnlyOneTool
{
    return [[splitter_ items] count] == 1;
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
    return -[term_ growToolbeltBy:-delta];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    splitter_.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
    [splitter_ updateForHeight:self.frame.size.height];
    dragHandle_.frame = NSMakeRect(0, 0, 3, self.frame.size.height);
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    splitter_.frame = NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height);
    [splitter_ updateForHeight:self.frame.size.height];
    NSLog(@"%@", [splitter_ iterm_recursiveDescription]);
    dragHandle_.frame = NSMakeRect(0, 0, 3, self.frame.size.height);
}


@end
