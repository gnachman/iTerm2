//
//  iTermPasteViewManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/18.
//

#import "iTermPasteViewManager.h"

#import "iTermStatusBarProgressComponent.h"
#import "iTermStatusBarViewController.h"
#import "PasteViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermPasteViewManager()<iTermStatusBarProgressComponentDelegate, PasteViewControllerDelegate>
@end

@implementation iTermPasteViewManager {
    PasteViewController *_dropDownViewController;
    iTermStatusBarViewController *_statusBarController;
    iTermStatusBarProgressComponent *_component;
}

- (void)startWithViewForDropdown:(NSView *)dropdownSuperview
         statusBarViewController:(iTermStatusBarViewController *)statusBarController {
    if (statusBarController) {
        [self showInStatusBar:statusBarController];
    } else {
        [self showDropDownInView:dropdownSuperview];
    }
}

- (void)didStop {
    if (_dropDownViewController) {
        [self hideDropdown];
    } else {
        [self hideInStatusBar];
    }
}

- (void)setRemainingLength:(int)remainingLength {
    if (_component) {
        _component.remainingLength = remainingLength;
    } else {
        _dropDownViewController.remainingLength = remainingLength;
    }
}

- (int)remainingLength {
    return _component ? _component.remainingLength : _dropDownViewController.remainingLength;
}

#pragma mark - Status bar

- (void)showInStatusBar:(iTermStatusBarViewController *)statusBar {
    NSDictionary *knobs = @{ iTermStatusBarPriorityKey: @(INFINITY) };
    NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    _component = [[iTermStatusBarProgressComponent alloc] initWithConfiguration:configuration];
    _component.progressDelegate = self;
    _component.pasteContext = self.pasteContext;
    _component.bufferLength = self.bufferLength;

    _statusBarController = statusBar;
    _statusBarController.temporaryRightComponent = _component;
}

- (void)hideInStatusBar {
    _statusBarController.temporaryRightComponent = nil;
    _statusBarController = nil;
    _component = nil;
}

#pragma mark - Dropdown

- (void)hideDropdown {
    [_dropDownViewController closeWithCompletion:^{
        [self.delegate pasteViewManagerDropDownPasteViewVisibilityDidChange];
    }];
    _dropDownViewController = nil;
    _dropDownPasteViewIsVisible = NO;
}

- (void)showDropDownInView:(NSView *)superview {
    _dropDownViewController = [[PasteViewController alloc] initWithContext:_pasteContext
                                                                    length:_bufferLength
                                                                      mini:NO];
    _dropDownViewController.delegate = self;
    _dropDownViewController.view.frame = NSMakeRect(20,
                                                    superview.frame.size.height - _dropDownViewController.view.frame.size.height,
                                                    _dropDownViewController.view.frame.size.width,
                                                    _dropDownViewController.view.frame.size.height);
    [superview addSubview:_dropDownViewController.view];
    [_dropDownViewController updateFrame];
    _dropDownPasteViewIsVisible = YES;
    [self.delegate pasteViewManagerDropDownPasteViewVisibilityDidChange];
}

#pragma mark - PasteViewControllerDelegate

- (void)pasteViewControllerDidCancel {
    [self.delegate pasteViewManagerUserDidCancel];
}

#pragma mark - iTermStatusBarProgressComponent

- (void)statusBarProgressComponentDidCancel {
    [self.delegate pasteViewManagerUserDidCancel];
}

@end

NS_ASSUME_NONNULL_END

