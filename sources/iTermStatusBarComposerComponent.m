//
//  iTermStatusBarComposerComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarComposerComponent.h"

#import "iTermController.h"
#import "iTermShellHistoryController.h"
#import "iTermsStatusBarComposerViewController.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "PTYSession.h"

@interface iTermStatusBarComposerComponent() <iTermsStatusBarComposerViewControllerDelegate>
@end

@implementation iTermStatusBarComposerComponent {
    iTermsStatusBarComposerViewController *_viewController;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return INFINITY;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    NSRect frame = view.frame;
    frame.size.width = width;
    view.frame = frame;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 200;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Composer";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Adds a text field for composing command lines.";
}

- (id)statusBarComponentExemplar {
    return @"ls -l -R";
}

- (CGFloat)statusBarComponentVerticalOffset {
    return 0;
}

- (iTermsStatusBarComposerViewController *)viewController {
    if (!_viewController) {
        _viewController = [[iTermsStatusBarComposerViewController alloc] initWithNibName:@"iTermsStatusBarComposerViewController" bundle:[NSBundle bundleForClass:self.class]];
        _viewController.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(commandHistoryDidChange:)
                                                     name:kCommandHistoryDidChangeNotificationName
                                                   object:nil];
        // Give the session a chance to finish initializing and then reload data.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_viewController reloadData];
        });
    }
    return _viewController;
}

- (PTYSession *)session {
    NSString *sessionID = [self.scope valueForVariableName:iTermVariableKeySessionID];
    return [[iTermController sharedInstance] sessionWithGUID:sessionID];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithObject:iTermVariableKeySessionHostname];
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [self.viewController reloadData];
}


#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.viewController.view;
}

#pragma mark - iTermsStatusBarComposerViewControllerDelegate

- (void)statusBarComposer:(iTermsStatusBarComposerViewController *)composer
              sendCommand:(NSString *)command {
    [self.session writeTask:[command stringByAppendingString:@"\n"]];
}

- (NSArray<NSString *> *)statusBarComposerSuggestions:(iTermsStatusBarComposerViewController *)composer {
    NSArray<NSString *> *commands = [[[[self.session commandUses] mapWithBlock:^id(iTermCommandHistoryCommandUseMO *anObject) {
        return anObject.command;
    }] reverseObjectEnumerator] allObjects];
    return commands;
}

#pragma mark - Notifications

- (void)commandHistoryDidChange:(NSNotification *)notification {
    // TODO: This is not very efficient.
    [_viewController reloadData];
}

@end
