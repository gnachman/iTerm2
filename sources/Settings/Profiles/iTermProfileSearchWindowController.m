//
//  iTermProfileSearchWindowController.m
//  iTerm2SharedARC
//
//  Created by OpenAI on 7/23/26.
//

#import "iTermProfileSearchWindowController.h"

#import "ProfileListView.h"
#import "ProfileModel.h"

@interface iTermProfileSearchPanel : NSPanel
@end

@implementation iTermProfileSearchPanel

- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
        [self close];
        return;
    }
    [super sendEvent:event];
}

@end

@interface iTermProfileSearchWindowController ()<ProfileListViewDelegate, NSWindowDelegate>
@end

@implementation iTermProfileSearchWindowController {
    ProfileListView *_profileListView;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 520, 420);
    iTermProfileSearchPanel *panel =
        [[iTermProfileSearchPanel alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskUtilityWindow)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    panel.title = @"Search Profiles";
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.minSize = NSMakeSize(360, 260);
    if (@available(macOS 10.16, *)) {
        panel.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
    }

    self = [super initWithWindow:panel];
    if (self) {
        panel.delegate = self;

        _profileListView =
            [[ProfileListView alloc] initWithFrame:panel.contentView.bounds
                                            model:[ProfileModel sharedInstance]
                                            font:nil
                                     profileTypes:ProfileTypeAll];
        _profileListView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _profileListView.delegate = self;
        [_profileListView forceOverlayScroller];
        [panel.contentView addSubview:_profileListView];
    }
    return self;
}

- (void)dealloc {
    if (self.window.delegate == self) {
        self.window.delegate = nil;
    }
    _profileListView.delegate = nil;
}

- (void)showSearchWindow:(id)sender {
    [_profileListView clearSearchField];
    [_profileListView reloadData];
    if (_profileListView.numberOfRows > 0) {
        [_profileListView selectRowIndex:0];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:sender];
    [self.window center];
    [self.window makeKeyAndOrderFront:sender];
    [_profileListView focusSearchField];
}

- (void)profileTableRowSelected:(ProfileListView *)sender {
    NSString *guid = sender.selectedGuid;
    if (!guid) {
        return;
    }
    if (self.profileSelected) {
        self.profileSelected(guid);
    }
    [self close];
}

- (void)windowWillClose:(NSNotification *)notification {
    [_profileListView clearSearchField];
}

@end
