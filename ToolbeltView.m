//
//  ToolbeltView.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolbeltView.h"
#import "ToolProfiles.h"
#import "ToolPasteHistory.h"
#import "ToolWrapper.h"

@interface ToolbeltView (Private)

+ (NSDictionary *)toolsDictionary;
- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(ToolWrapper *)wrapper;
- (void)addToolWithName:(NSString *)theName;
- (void)setHaveMultipleTools:(BOOL)value;

@end

@implementation ToolbeltView

static NSMutableDictionary *gRegisteredTools;
static NSString *kToolbeltPrefKey = @"ToolbeltTools";

+ (void)initialize
{
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [ToolbeltView registerToolWithName:@"Paste History" withClass:[ToolPasteHistory class]];
    [ToolbeltView registerToolWithName:@"Profiles" withClass:[ToolProfiles class]];
}

- (id)initWithFrame:(NSRect)frame delegate:(id<ToolbeltDelegate>)delegate
{
    self = [super initWithFrame:frame];
    if (self) {
        delegate_ = delegate;

        NSArray *items = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey];
        if (!items) {
            items = [gRegisteredTools allKeys];
            [[NSUserDefaults standardUserDefaults] setObject:items forKey:kToolbeltPrefKey];
        }

        splitter_ = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
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
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey] indexOfObject:name] != NSNotFound;
}

+ (void)toggleShouldShowTool:(NSString *)theName
{
    NSMutableArray *tools = [[[[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey] mutableCopy] autorelease];
    if (!tools) {
        tools = [[[gRegisteredTools allKeys] mutableCopy] autorelease];
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
    NSArray *tools = [[NSUserDefaults standardUserDefaults] objectForKey:kToolbeltPrefKey];
    if (!tools) {
        tools = [gRegisteredTools allKeys];
    }
    return [tools count];
}

- (void)toggleToolWithName:(NSString *)theName
{
    ToolWrapper *wrapper = [tools_ objectForKey:theName];
    if (wrapper) {
        [wrapper removeFromSuperview];
        [tools_ removeObjectForKey:theName];
    } else {
        [self addToolWithName:theName];
    }
    [self setHaveMultipleTools:[self haveMultipleTools]];
}

- (BOOL)showingToolWithName:(NSString *)theName
{
    return [tools_ objectForKey:theName] != nil;
}

+ (void)populateMenu:(NSMenu *)menu
{
    NSArray *names = [[gRegisteredTools allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *theName in names) {
        NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:theName action:@selector(toggleToolbeltTool:) keyEquivalent:@""] autorelease];
        [i setState:[ToolbeltView shouldShowTool:theName] ? NSOnState : NSOffState];
        [menu addItem:i];
    }
}

- (void)addTool:(NSView<ToolbeltTool> *)theTool toWrapper:(ToolWrapper *)wrapper
{
    [splitter_ addSubview:wrapper];
    [wrapper release];
    [wrapper.container addSubview:theTool];
    [wrapper setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [theTool setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [splitter_ adjustSubviews];
    [wrapper bindCloseButton];
    [tools_ setObject:wrapper forKey:wrapper.name];
}

- (void)addToolWithName:(NSString *)toolName
{
    ToolWrapper *wrapper = [[ToolWrapper alloc] initWithFrame:NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height)];
    wrapper.name = toolName;
    Class c = [gRegisteredTools objectForKey:toolName];
    [self addTool:[[[c alloc] initWithFrame:NSMakeRect(0, 0, wrapper.container.frame.size.width, wrapper.container.frame.size.height)] autorelease]
        toWrapper:wrapper];
    [self setHaveMultipleTools:[self haveMultipleTools]];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setHaveMultipleTools:(BOOL)value
{
    // For KVO
}

- (BOOL)haveMultipleTools
{
    return [[splitter_ subviews] count] > 1;
}

@end
