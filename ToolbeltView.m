//
//  ToolbeltView.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolbeltView.h"
#import "ToolProfiles.h"

@interface ToolbeltView (Private)

+ (NSDictionary *)toolsDictionary;
- (void)addTool:(NSView<ToolbeltTool> *)theTool;

@end

@implementation ToolbeltView

static NSMutableDictionary *gRegisteredTools;

+ (void)initialize
{
    gRegisteredTools = [[NSMutableDictionary alloc] init];
    [ToolbeltView registerToolWithName:@"Profiles" withClass:[ToolProfiles class]];
}

- (id)initWithFrame:(NSRect)frame delegate:(id<ToolbeltDelegate>)delegate
{
    self = [super initWithFrame:frame];
    if (self) {
        delegate_ = delegate;
        splitter_ = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        [splitter_ setVertical:NO];
        [self addSubview:splitter_];
        tools_ = [[ToolbeltView toolsDictionary] retain];
        
        NSArray *items = [[NSUserDefaults standardUserDefaults] objectForKey:@"ToolbeltItems"];
        if (!items) {
            items = [gRegisteredTools allKeys];
        }
        for (NSString *toolName in items) {
            Class c = [gRegisteredTools objectForKey:toolName];
            [self addTool:[[[c alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)] autorelease]];
        }
    }
    return self;
}

- (void)dealloc
{
    [splitter_ release];
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

- (void)addTool:(NSView<ToolbeltTool> *)theTool
{
    [splitter_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [splitter_ addSubview:theTool];
    [splitter_ adjustSubviews];
}

@end
