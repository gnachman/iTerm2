//
//  iTermShortcutsViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import "iTermShortcutsViewController.h"
#import "iTermActionsEditingViewController.h"
#import "iTermSnippetsEditingViewController.h"

@interface iTermShortcutsViewController ()

@end

@implementation iTermShortcutsViewController {
    IBOutlet NSTabView *_tabView;
    IBOutlet iTermActionsEditingViewController *_actionsViewController;
    IBOutlet iTermSnippetsEditingViewController *_snippetsViewController;
    IBOutlet NSView *_actionsView;
    IBOutlet NSView *_snippetsView;
}

- (void)awakeFromNib {
    [_actionsViewController defineControlsInContainer:self containerView:_actionsView];
    [_snippetsViewController defineControlsInContainer:self containerView:_snippetsView];
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 846;
}

@end
