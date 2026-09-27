//
//  SplitPanel.m
//  iTerm
//
//  Created by George Nachman on 8/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "SplitPanel.h"
#import "iTermModalSheetRunner.h"
#import "ProfileListView.h"

@interface SplitPanel ()<ProfileListViewDelegate>
@end

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
            [splitPanel.label setStringValue:NSLocalizedStringWithDefaultValue(@"SplitPanel.VerticalPrompt", nil, [NSBundle mainBundle], @"Split current pane vertically with profile:", @"Label prompting the user to pick a profile for a vertical split")];
        } else {
            [splitPanel.label setStringValue:NSLocalizedStringWithDefaultValue(@"SplitPanel.HorizontalPrompt", nil, [NSBundle mainBundle], @"Split current pane horizontally with profile:", @"Label prompting the user to pick a profile for a horizontal split")];
        }
        [parent.window beginSheet:splitPanel.window completionHandler:^(NSModalResponse returnCode) {
            // Fires a run-loop turn later, after iTermRunModalForWindowAbortingIfParentCloses
            // may have aborted our session (parent closed). Only stop if we're still the
            // current modal, so we don't stop an unrelated modal that is live by then.
            if (NSApp.modalWindow == splitPanel.window) {
                [NSApp stopModal];
            }
        }];

        NSWindow *panel = [splitPanel window];
        iTermRunModalForWindowAbortingIfParentCloses(panel, parent.window);
        [parent.window endSheet:splitPanel.window];
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

- (void)dealloc {
    [guid_ release];
    [parent_ release];
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

#pragma mark - ProfileListViewDelegate

- (void)profileTableSelectionDidChange:(id)profileTable
{
    [splitButton_ setEnabled:([profileTable selectedGuid] != nil)];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
}

- (void)profileTableRowSelected:(id)profileTable
{
    NSString *guid = [bookmarks_ selectedGuid];
    if (guid) {
        self.guid = guid;
        [self _close];
    }
}

@end
