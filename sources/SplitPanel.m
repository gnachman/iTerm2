//
//  SplitPanel.m
//  iTerm
//
//  Created by George Nachman on 8/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SplitPanel.h"
#import "ProfileListView.h"

@implementation SplitPanel

@synthesize parent = parent_;
@synthesize isVertical = isVertical_;
@synthesize label = label_;
@synthesize guid = guid_;

+ (NSString *)showPanelWithParent:(NSWindowController *)parent isVertical:(BOOL)vertical
{
    SplitPanel *splitPanel = [[[SplitPanel alloc] initWithWindowNibName:@"SplitPanel"] autorelease];
    if (splitPanel) {
        splitPanel.parent = parent;
        splitPanel.isVertical = vertical;
        if (vertical) {
            [splitPanel.label setStringValue:@"Split current pane vertically with profile:"];
        } else {
            [splitPanel.label setStringValue:@"Split current pane horizontally with profile:"];
        }
        [NSApp beginSheet:[splitPanel window]
            modalForWindow:[parent window]
            modalDelegate:splitPanel
            didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
            contextInfo:nil];
        
        NSWindow *panel = [splitPanel window];
        [NSApp runModalForWindow:panel];
        [NSApp endSheet:panel];
        [panel orderOut:nil];
        [splitPanel close];
        
        return splitPanel.guid;
    } else {
        return nil;
    }
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        [self window];
        [splitButton_ setEnabled:NO];
    }
    return self;
}

- (void)dealloc
{
    [guid_ release];
    [super dealloc];
}

- (void)_close
{
    [NSApp stopModal];
}

- (void)sheetDidEnd:(NSWindow *)sheet
         returnCode:(NSInteger)returnCode
        contextInfo:(void *)contextInfo
{
    [self _close];
}

- (IBAction)cancel:(id)sender
{
    self.guid = nil;
    [self _close];
}

- (IBAction)split:(id)sender
{
    self.guid = [bookmarks_ selectedGuid];
    [self _close];
}

#pragma mark BookmarkListView delegate methods

- (void)profileTableSelectionDidChange:(id)profileTable
{
    [splitButton_ setEnabled:([profileTable selectedGuid] != nil)];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
}

- (void)profileTableRowSelected:(id)profileTable
{
}

@end
