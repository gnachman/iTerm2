//
//  iTermComposerManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/31/20.
//

#import "iTermComposerManager.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermMinimalComposerViewController.h"
#import "iTermStatusBarComposerComponent.h"
#import "iTermStatusBarViewController.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

@interface iTermComposerManager()<
    iTermMinimalComposerViewControllerDelegate,
    iTermStatusBarComposerComponentDelegate>
@end

@implementation iTermComposerManager {
    iTermStatusBarComposerComponent *_component;
    iTermStatusBarViewController *_statusBarViewController;
    iTermMinimalComposerViewController *_minimalViewController;
    NSString *_saved;
    BOOL _preserveSaved;
}

- (void)setCommand:(NSString *)command {
    _saved = [command copy];
}

- (void)showOrAppendToDropdownWithString:(NSString *)string {
    if (!_dropDownComposerViewIsVisible) {
        _saved = [string copy];
        [self showMinimalComposerInView:[self.delegate composerManagerContainerView:self]];
    } else {
        _minimalViewController.stringValue = [NSString stringWithFormat:@"%@\n%@",
                                              _minimalViewController.stringValue, string];
    }
    [_minimalViewController makeFirstResponder];
}
- (void)showWithCommand:(NSString *)command {
    _saved = [command copy];
    if (_dropDownComposerViewIsVisible) {
        // Put into already-visible drop-down view.
        _minimalViewController.stringValue = command;
        [_minimalViewController makeFirstResponder];
        return;
    }
    iTermStatusBarViewController *statusBarViewController = [self.delegate composerManagerStatusBarViewController:self];
    if (statusBarViewController) {
        iTermStatusBarComposerComponent *component = [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]];
        if (component) {
            // Put into already-visible status bar component.
            component.stringValue = command;
            [component makeFirstResponder];
            [component deselect];
            return;
        }
    }
    // Nothing is currently visible. Reveal as usual.
    [self reveal];
}

- (void)reveal {
    iTermStatusBarViewController *statusBarViewController = [self.delegate composerManagerStatusBarViewController:self];
    if (statusBarViewController && [self shouldRevealStatusBarComposerInViewController:statusBarViewController]) {
        if (_dropDownComposerViewIsVisible) {
            _saved = _minimalViewController.stringValue;
            [self dismissMinimalView];
        } else {
            [self showComposerInStatusBar:statusBarViewController];
        }
    } else {
        [self showMinimalComposerInView:[self.delegate composerManagerContainerView:self]];
    }
}

- (BOOL)shouldRevealStatusBarComposerInViewController:(iTermStatusBarViewController *)statusBarViewController {
    if ([iTermAdvancedSettingsModel alwaysUseStatusBarComposer]) {
        return YES;
    }
    return [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]] != nil;
}

- (void)revealMinimal {
    iTermStatusBarViewController *statusBarViewController = [self.delegate composerManagerStatusBarViewController:self];
    if (statusBarViewController) {
        iTermStatusBarComposerComponent *component = [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]];
        if (component) {
            _saved = [component.stringValue copy];
        }
    }
    [self showMinimalComposerInView:[self.delegate composerManagerContainerView:self]];
}

- (void)showComposerInStatusBar:(iTermStatusBarViewController *)statusBarViewController {
    iTermStatusBarComposerComponent *component;
    component = [statusBarViewController visibleComponentWithIdentifier:[iTermStatusBarComposerComponent statusBarComponentIdentifier]];
    if (component) {
        [component makeFirstResponder];
        return;
    }
    component = [iTermStatusBarComposerComponent castFrom:_statusBarViewController.temporaryRightComponent];
    if (component && component == _component) {
        [component makeFirstResponder];
        return;
    }
    NSDictionary *knobs = @{ iTermStatusBarPriorityKey: @(INFINITY) };
    NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    iTermVariableScope *scope = [self.delegate composerManagerScope:self];
    component = [[iTermStatusBarComposerComponent alloc] initWithConfiguration:configuration
                                                                         scope:scope];
    _statusBarViewController = statusBarViewController;
    _statusBarViewController.temporaryRightComponent = component;
    _component = component;
    _component.stringValue = _saved ?: @"";
    component.composerDelegate = self;
    [component makeFirstResponder];
}

- (BOOL)minimalComposerRevealed {
    return _minimalViewController != nil;
}

- (void)showMinimalComposerInView:(NSView *)superview {
    if (_minimalViewController) {
        _saved = _minimalViewController.stringValue;
        [self dismissMinimalView];
        return;
    }
    _minimalViewController = [[iTermMinimalComposerViewController alloc] init];
    _minimalViewController.delegate = self;
    _minimalViewController.view.frame = NSMakeRect(20,
                                                    superview.frame.size.height - _minimalViewController.view.frame.size.height,
                                                    _minimalViewController.view.frame.size.width,
                                                    _minimalViewController.view.frame.size.height);
    _minimalViewController.view.appearance = [self.delegate composerManagerAppearance:self];
    [_minimalViewController setHost:[self.delegate composerManagerRemoteHost:self]
                   workingDirectory:[self.delegate composerManagerWorkingDirectory:self]
                              shell:[self.delegate composerManagerShell:self]
                     tmuxController:[self.delegate composerManagerTmuxController:self]];
    [_minimalViewController setFont:[self.delegate composerManagerFont:self]];
    [superview addSubview:_minimalViewController.view];
    if (_saved.length) {
        _minimalViewController.stringValue = _saved ?: @"";
        _saved = nil;
    }
    [_minimalViewController updateFrame];
    [_minimalViewController makeFirstResponder];
    _dropDownComposerViewIsVisible = YES;
}

- (BOOL)dismiss {
    if (!_dropDownComposerViewIsVisible) {
        return NO;
    }
    _saved = _minimalViewController.stringValue;
    [self dismissMinimalView];
    return YES;
}

- (void)layout {
    [_minimalViewController updateFrame];
}

#pragma mark - iTermStatusBarComposerComponentDelegate

- (void)statusBarComposerComponentDidEndEditing:(iTermStatusBarComposerComponent *)component {
    if (_statusBarViewController.temporaryRightComponent == _component &&
        component == _component) {
        _saved = _component.stringValue;
        _statusBarViewController.temporaryRightComponent = nil;
        _component = nil;
        [self.delegate composerManagerDidRemoveTemporaryStatusBarComponent:self];
    }
}

#pragma mark - iTermMinimalComposerViewControllerDelegate

- (void)minimalComposer:(nonnull iTermMinimalComposerViewController *)composer
            sendCommand:(nonnull NSString *)command {
    NSString *string = composer.stringValue;
    [self dismissMinimalView];
    if (command.length == 0) {
        _saved = string;
        return;
    }
    _saved = nil;
    [self.delegate composerManager:self sendCommand:[command stringByAppendingString:@"\n"]];
}

- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
    sendToAdvancedPaste:(NSString *)content {
    [self dismissMinimalView];
    _saved = nil;
    [self.delegate composerManager:self
               sendToAdvancedPaste:[content stringByAppendingString:@"\n"]];
}

- (void)dismissMinimalView {
    NSViewController *vc = _minimalViewController;
    [NSView animateWithDuration:0.125
                     animations:^{
        vc.view.animator.alphaValue = 0;
    }
                     completion:^(BOOL finished) {
        [vc.view removeFromSuperview];
    }];
    _minimalViewController = nil;
    _dropDownComposerViewIsVisible = NO;
    // You get into infinite recursion if you do ths inside resignFirstResponder.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate composerManagerDidDismissMinimalView:self];
    });
}

@end
