//
//  iTermEditSnippetsWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/20/20.
//

#import "iTermEditSnippetsWindowController.h"
#import "iTermSnippetsEditingViewController.h"
#import "iTermSnippetsModel.h"
#warning TODO: Support undo
@interface iTermEditSnippetsWindowController ()

@end

@implementation iTermEditSnippetsWindowController {
    IBOutlet iTermSnippetsEditingViewController *_viewController;
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
        _viewController.model = [iTermSnippetsModel instanceForProfileWithGUID:self.guid];
    } else {
        _viewController.model = [iTermSnippetsModel sharedInstance];
    }
}

- (void)windowWillOpen {

}

- (IBAction)ok:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

@end
