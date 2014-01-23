//
//  ToolbeltView.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolbeltView.h"
#import "ToolCommandHistoryView.h"
#import "ToolProfiles.h"
#import "ToolPasteHistory.h"
#import "ToolWrapper.h"
#import "ToolJobs.h"
#import "ToolNotes.h"
#import "iTermApplicationDelegate.h"
#import "iTermApplication.h"
#import "FutureMethods.h"

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

@interface ToolbeltView (Private)

+ (NSDictionary *)toolsDictionary;
- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(ToolWrapper *)wrapper;
- (void)addToolWithName:(NSString *)theName;
- (void)setHaveOnlyOneTool:(BOOL)value;

@end

@implementation ToolbeltView

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";

+ (void)initialize
{
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [ToolbeltView registerToolWithName:@"Command History"
                             withClass:[ToolCommandHistoryView class]];
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
    return tools;
}

- (id)initWithFrame:(NSRect)frame term:(PseudoTerminal *)term
{
    self = [super initWithFrame:frame];
    if (self) {
        term_ = term;

        NSArray *items = [ToolbeltView configuredTools];
        if (!items) {
            items = [ToolbeltView defaultTools];
            [[NSUserDefaults standardUserDefaults] setObject:items forKey:kToolbeltPrefKey];
        }

        splitter_ = [[ToolbeltSplitView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        [splitter_ setVertical:NO];
        [splitter_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [splitter_ setDividerStyle:NSSplitViewDividerStyleThin];
        [splitter_ setDelegate:self];
        [self addSubview:splitter_];
        tools_ = [[NSMutableDictionary alloc] init];

        for (NSString *theName in items) {
            if ([ToolbeltView shouldShowTool:theName]) {
                [self addToolWithName:theName];
            }
        }
    }
    return self;
}

- (void)dealloc
{
    [splitter_ release];
    [tools_ release];
    [super dealloc];
}

- (void)setUseDarkDividers:(BOOL)useDarkDividers {
    [splitter_ setDividerColor:useDarkDividers ? [NSColor darkGrayColor] : [NSColor lightGrayColor]];
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
                                                                          self.frame.size.height / MAX(1, [ToolbeltView numberOfVisibleTools ] - 1))] autorelease];
    wrapper.name = toolName;
    wrapper.term = term_;
        wrapper.delegate = self;
    Class c = [gRegisteredTools objectForKey:toolName];
    [self addTool:[[[c alloc] initWithFrame:NSMakeRect(0,
                                                       0,
                                                       wrapper.container.frame.size.width,
                                                       wrapper.container.frame.size.height)] autorelease]
        toWrapper:wrapper];
    [self setHaveOnlyOneTool:[self haveOnlyOneTool]];
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
    for (ToolWrapper *wrapper in [splitter_ subviews]) {
        [wrapper relayout];
    }
}

#pragma mark - ToolWrapperDelegate

- (void)hideToolbelt
{
        iTermApplicationDelegate *itad = [[iTermApplication sharedApplication] delegate];
        [itad toggleToolbelt:self];
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
    ToolWrapper *wrapper = [tools_ objectForKey:@"Command History"];
    return (ToolCommandHistoryView *)wrapper.tool;
}

@end
