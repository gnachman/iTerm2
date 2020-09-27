//
//  iTermEditActionsWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/20.
//

#import "iTermEditActionsWindowController.h"
#import "iTermActionsEditingViewController.h"
#import "iTermActionsModel.h"
#warning TODO: Support undo

@interface iTermEditActionsWindowController ()

@end

@implementation iTermEditActionsWindowController {
    IBOutlet iTermActionsEditingViewController *_viewController;
    IBOutlet NSView *_wrapper;
}

- (instancetype)init {
    return [self initWithWindowNibName:NSStringFromClass([self class])];
}

- (void)awakeFromNib {
    [_wrapper addSubview:_viewController.view];
    [_viewController finishInitialization];
    _viewController.view.frame = _wrapper.bounds;
    [self updateGUID];
}

- (void)setGuid:(NSString *)guid {
    _guid = [guid copy];
    [self updateGUID];
}

- (void)updateGUID {
    if (self.guid) {
        _viewController.model = [iTermActionsModel instanceForProfileWithGUID:self.guid];
    } else {
        _viewController.model = [iTermActionsModel sharedInstance];
    }
}

- (void)windowWillOpen {

}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

@end
