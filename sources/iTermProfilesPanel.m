//
//  iTermProfilesPanel.m
//  iTerm2
//
//  Created by George Nachman on 6/12/15.
//
//

#import "iTermProfilesPanel.h"
#import "ProfileListView.h"

// Window restorable state keys
static NSString *kTagsOpen = @"Tags Open";
static NSString *kCloseAfterOpening = @"Close After Opening";

@implementation iTermProfilesPanel {
    __weak IBOutlet ProfileListView *_profileListView;
    __weak IBOutlet NSButton *_closeAfterOpening;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeBool:_profileListView.tagsVisible forKey:kTagsOpen];
    [coder encodeBool:_closeAfterOpening.state == NSOnState forKey:kCloseAfterOpening];
}

- (void)restoreStateWithCoder:(NSCoder *)coder {
    [super restoreStateWithCoder:coder];
    [_profileListView setTagsOpen:[coder decodeBoolForKey:kTagsOpen] animated:NO];
    [_closeAfterOpening setState:[coder decodeBoolForKey:kCloseAfterOpening] ? NSOnState : NSOffState];
}

@end
