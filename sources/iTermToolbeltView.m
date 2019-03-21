#import "iTermToolbeltView.h"

#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermDragHandleView.h"
#import "iTermPreferences.h"
#import "iTermSystemVersion.h"
#import "iTermToolActions.h"
#import "iTermToolWrapper.h"
#import "iTermToolbeltSplitView.h"
#import "iTermTuple.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "ToolDirectoriesView.h"
#import "ToolJobs.h"
#import "ToolNotes.h"
#import "ToolPasteHistory.h"
#import "ToolProfiles.h"
#import "ToolWebView.h"

NSString *const kActionsToolName = @"Actions";
NSString *const kCapturedOutputToolName = @"Captured Output";
NSString *const kCommandHistoryToolName = @"Command History";
NSString *const kRecentDirectoriesToolName = @"Recent Directories";
NSString *const kJobsToolName = @"Jobs";
NSString *const kNotesToolName = @"Notes";
NSString *const kPasteHistoryToolName = @"Paste History";
NSString *const kProfilesToolName = @"Profiles";

NSString *const kToolbeltShouldHide = @"kToolbeltShouldHide";

NSString *const kDynamicToolsDidChange = @"kDynamicToolsDidChange";
NSString *const iTermToolbeltDidRegisterDynamicToolNotification = @"iTermToolbeltDidRegisterDynamicToolNotification";

static NSString *const iTermToolbeltProportionsUserDefaultsKey = @"NoSyncToolbeltProportions";

@interface iTermToolbeltView () <iTermDragHandleViewDelegate>
@end

@implementation iTermToolbeltView {
    iTermDragHandleView *_dragHandle;
    iTermToolbeltSplitView *_splitter;
    // Tool name to wrapper
    NSMutableDictionary<NSString *, iTermToolWrapper *> *_tools;
    NSDictionary *_proportions;
}

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";
static NSString *const kDynamicToolsKey = @"NoSyncDynamicTools";
static NSString *const kDynamicToolName = @"name";
static NSString *const kDynamicToolURL = @"URL";

#pragma mark - Public class methods

+ (void)initialize {
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [iTermToolbeltView registerToolWithName:kActionsToolName withClass:[iTermToolActions class]];
    [iTermToolbeltView registerToolWithName:kCapturedOutputToolName withClass:[ToolCapturedOutputView class]];
    [iTermToolbeltView registerToolWithName:kCommandHistoryToolName withClass:[ToolCommandHistoryView class]];
    [iTermToolbeltView registerToolWithName:kRecentDirectoriesToolName withClass:[ToolDirectoriesView class]];
    [iTermToolbeltView registerToolWithName:kJobsToolName withClass:[ToolJobs class]];
    [iTermToolbeltView registerToolWithName:kNotesToolName withClass:[ToolNotes class]];
    [iTermToolbeltView registerToolWithName:kPasteHistoryToolName withClass:[ToolPasteHistory class]];
    [iTermToolbeltView registerToolWithName:kProfilesToolName withClass:[ToolProfiles class]];

    NSDictionary<NSString *, NSDictionary *> *dynamicTools = [[NSUserDefaults standardUserDefaults] objectForKey:kDynamicToolsKey];
    [dynamicTools enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull identifier, NSDictionary * _Nonnull dict, BOOL * _Nonnull stop) {
        [iTermToolbeltView registerToolWithName:dict[kDynamicToolName] withClass:[ToolWebView class]];
    }];
}

+ (NSArray<NSString *> *)builtInToolNames {
    return [gRegisteredTools.allKeys filteredArrayUsingBlock:^BOOL(NSString *key) {
        Class c = gRegisteredTools[key];
        return c != [ToolWebView class];
    }];
}

+ (NSArray<NSString *> *)dynamicToolNames {
    NSDictionary<NSString *, NSDictionary *> *dynamicTools = [[NSUserDefaults standardUserDefaults] objectForKey:kDynamicToolsKey];
    return [dynamicTools.allValues mapWithBlock:^id(NSDictionary *dict) {
        return dict[kDynamicToolName];
    }];

}

+ (void)registerDynamicToolWithIdentifier:(NSString *)identifier name:(NSString *)name URL:(NSString *)url revealIfAlreadyRegistered:(BOOL)revealIfAlreadyRegistered {
    if (!url) {
        return;
    }
    NSDictionary *registry = [[NSUserDefaults standardUserDefaults] objectForKey:kDynamicToolsKey];
    NSString *oldName = [[registry[identifier][kDynamicToolName] retain] autorelease];
    if ([registry[identifier][kDynamicToolURL] isEqualToString:url] &&
        [registry[identifier][kDynamicToolName] isEqualToString:name]) {
        if (revealIfAlreadyRegistered) {
            if (![[iTermToolbeltView configuredTools] containsObject:name]) {
                [self toggleShouldShowTool:name];
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermToolbeltDidRegisterDynamicToolNotification object:identifier];
        return;
    }
    NSMutableDictionary *mutableRegistry = [[registry mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
    mutableRegistry[identifier] = @{ kDynamicToolName: name,
                                     kDynamicToolURL: url };
    [[NSUserDefaults standardUserDefaults] setObject:mutableRegistry forKey:kDynamicToolsKey];

    if (oldName && [[iTermToolbeltView configuredTools] containsObject:oldName]) {
        [self toggleShouldShowTool:oldName];
    }
    if (oldName) {
        [gRegisteredTools removeObjectForKey:oldName];
    }
    [self registerToolWithName:name withClass:[ToolWebView class]];
    if (![[iTermToolbeltView configuredTools] containsObject:name]) {
        [self toggleShouldShowTool:name];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kDynamicToolsDidChange object:nil];
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
    if (menu.itemArray.count > 0) {
        for (NSInteger i = menu.itemArray.count - 1; i >= 0; i--) {
            NSMenuItem *item = menu.itemArray[i];
            if ([item action] == @selector(toggleToolbeltTool:)) {
                [menu removeItem:item];
            } else {
                break;
            }
        }
    }
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
    [_proportions release];
    [super dealloc];
}

#pragma mark - NSView

- (NSColor *)backgroundColor {
    if (@available(macOS 10.14, *)) {
        switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_MINIMAL:
                return [NSColor controlBackgroundColor];

            case TAB_STYLE_LIGHT:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            case TAB_STYLE_DARK:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
                break;
        }
    }

    NSColor *lightColor = [NSColor colorWithCalibratedWhite:237.0/255.0 alpha:1];
    NSColor *darkColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
    switch ([self.effectiveAppearance it_tabStyle:[iTermPreferences intForKey:kPreferenceKeyTabStyle]]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_MINIMAL:
            assert(NO);

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return lightColor;
            break;

        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            if (@available(macOS 10.14, *)) {
                return darkColor;
            } else if ([iTermAdvancedSettingsModel darkThemeHasBlackTitlebar]) {
                return darkColor;
            } else {
                return lightColor;
            }
            break;
    }
    return lightColor;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self backgroundColor] set];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - APIs

+ (NSDictionary *)savedProportions {
    return [[NSUserDefaults standardUserDefaults] objectForKey:iTermToolbeltProportionsUserDefaultsKey];
}

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
        if ([wrapper.tool respondsToSelector:@selector(shutdown)]) {
            [[wrapper tool] shutdown];
        }
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

- (void)windowBackgroundColorDidChange {
    for (iTermToolWrapper *wrapper in _tools.allValues) {
        if ([wrapper.tool respondsToSelector:@selector(windowBackgroundColorDidChange)]) {
            [wrapper.tool windowBackgroundColorDidChange];
        }
    }
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
        NSView<ToolbeltTool> *theTool = nil;
        NSRect frame = NSMakeRect(0,
                                  0,
                                  wrapper.container.frame.size.width,
                                  wrapper.container.frame.size.height);
        if ([c instancesRespondToSelector:@selector(initWithFrame:URL:identifier:)]) {
            NSDictionary *registry = [[NSUserDefaults standardUserDefaults] objectForKey:kDynamicToolsKey];
            NSString *identifier = [registry.allKeys objectPassingTest:^BOOL(NSString *key, NSUInteger index, BOOL *stop) {
                NSDictionary *dict = registry[key];
                return [dict[kDynamicToolName] isEqualToString:toolName];
            }];
            NSDictionary *attrs = registry[identifier];
            NSURL *url = [NSURL URLWithString:(attrs[kDynamicToolURL] ?: @"")];
            if (url && identifier) {
                theTool = [[[c alloc] initWithFrame:frame URL:url identifier:identifier] autorelease];
            }
        } else {
            theTool = [[[c alloc] initWithFrame:frame] autorelease];
        }
        if (theTool) {
            [self addTool:theTool toWrapper:wrapper];
        }
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

#pragma mark - PTYSplitViewDelegate

- (NSDictionary *)proportions {
    NSArray<NSString *> *names = [iTermToolbeltView configuredTools];
    NSArray<NSNumber *> *heights = [names mapWithBlock:^id(NSString *name) {
        return @(_tools[name].frame.size.height);
    }];
    double sumOfHeights = [heights sumOfNumbers];
    if (sumOfHeights <= 0) {
        return @{};
    }
    NSArray<NSNumber *> *fractions = [heights mapWithBlock:^id(NSNumber *height) {
        return @(height.doubleValue / sumOfHeights);
    }];
    NSArray<NSDictionary<NSString *, id> *> *proportions = [[names zip:fractions] mapWithBlock:^id(iTermTuple *tuple) {
        return @{ @"name": tuple.firstObject,
                  @"heightAsFraction": tuple.secondObject };
    }];
    return @{ @"proportions": proportions };
}

- (void)setProportions:(NSDictionary *)dict {
    [_proportions release];
    _proportions = nil;
    if (!dict) {
        return;
    }
    NSArray *proportions = [NSArray castFrom:dict[@"proportions"]];
    if (!proportions) {
        return;
    }

    NSArray<NSString *> *names = [iTermToolbeltView configuredTools];
    NSArray<NSNumber *> *currentHeights = [names mapWithBlock:^id(NSString *name) {
        return @(_tools[name].frame.size.height);
    }];
    const double sumOfCurrentHeights = [currentHeights sumOfNumbers];
    if (sumOfCurrentHeights <= 0) {
        return;
    }

    NSArray<iTermTuple<NSString *, NSNumber *> *> *tuples = [proportions mapWithBlock:^id(id anObject) {
        NSDictionary *info = [NSDictionary castFrom:anObject];
        if (!info) {
            return nil;
        }
        NSString *name = [NSString castFrom:info[@"name"]];
        NSNumber *fraction = [NSNumber castFrom:info[@"heightAsFraction"]];
        if (!name || !fraction) {
            return nil;
        }
        return [iTermTuple tupleWithObject:name andObject:fraction];
    }];
    if (tuples.count != proportions.count) {
        return;
    }
    const BOOL consistent = [[tuples zip:names] allWithBlock:^BOOL(iTermTuple<iTermTuple<NSString *, NSNumber *> *, NSString *> *tuple) {
        return [tuple.firstObject.firstObject isEqualToString:tuple.secondObject] && tuple.firstObject.secondObject.doubleValue > 0;
    }];
    if (!consistent) {
        return;
    }
    __block double addedHeight = 0;
    NSArray<NSNumber *> *desiredHeights = [tuples mapWithBlock:^id(iTermTuple<NSString *,NSNumber *> *tuple) {
        iTermToolWrapper *wrapper = self->_tools[tuple.firstObject];
        const CGFloat proposed = tuple.secondObject.doubleValue * sumOfCurrentHeights;
        const CGFloat accepted = MAX(proposed, wrapper.minimumHeight);
        const CGFloat addition = MAX(0, accepted - proposed);
        addedHeight += addition;
        return @(accepted);
    }];
    if (addedHeight > 0) {
        NSArray<NSNumber *> *wiggleRoom = [[tuples zip:desiredHeights] mapWithBlock:^id(iTermTuple<iTermTuple<NSString *,NSNumber *> *, NSNumber *> *tuple) {
            NSString *name = tuple.firstObject.firstObject;
            double desiredHeight = tuple.secondObject.doubleValue;
            iTermToolWrapper *wrapper = self->_tools[name];
            return @(MAX(0, desiredHeight - wrapper.minimumHeight));
        }];
        const double totalWiggleRoom = [wiggleRoom sumOfNumbers];
        if (totalWiggleRoom < addedHeight) {
            return;
        }
        desiredHeights = [[desiredHeights zip:wiggleRoom] mapWithBlock:^id(iTermTuple<NSNumber *, NSNumber *> *tuple) {
            const CGFloat wiggleRoom = tuple.secondObject.doubleValue;
            if (wiggleRoom == 0) {
                // No change
                return tuple.firstObject;
            }
            const CGFloat originalDesiredHeight = tuple.firstObject.doubleValue;
            const CGFloat fractionOfWiggleRoom = wiggleRoom / totalWiggleRoom;
            return @(originalDesiredHeight - fractionOfWiggleRoom * addedHeight);
        }];
    }

    CGFloat y = 0;
    for (iTermTuple<NSString *, NSNumber *> *tuple in [names zip:desiredHeights]) {
        NSView *view = _tools[tuple.firstObject];
        NSRect frame = view.frame;
        frame.origin.y = y;
        frame.size.height = tuple.secondObject.doubleValue * sumOfCurrentHeights;
        view.frame = frame;
        y += tuple.secondObject.doubleValue * sumOfCurrentHeights;
        y += _splitter.dividerThickness;
    }
    [_splitter adjustSubviews];
    _proportions = [[self proportions] retain];
}

- (void)splitView:(PTYSplitView *)splitView
draggingDidEndOfSplit:(int)clickedOnSplitterIndex
           pixels:(NSSize)changePx {
    [_proportions release];
    _proportions = [[self proportions] retain];
    [[NSUserDefaults standardUserDefaults] setObject:_proportions
                                              forKey:iTermToolbeltProportionsUserDefaultsKey];
}

- (void)splitView:(PTYSplitView *)splitView draggingWillBeginOfSplit:(int)splitterIndex {
}

- (void)splitViewDidChangeSubviews:(PTYSplitView *)splitView {
}

#pragma mark - iTermDragHandleViewDelegate

- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    return -[_delegate growToolbeltBy:-delta];
}

- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle {
    [_delegate toolbeltDidFinishGrowing];
}

@end
