//
//  iTermStatusBarKnobActionViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import "iTermStatusBarKnobActionViewController.h"

#import "DebugLogging.h"
#import "iTermActionsModel.h"
#import "iTermEditKeyActionWindowController.h"

@interface iTermStatusBarKnobActionViewController ()

@end

@implementation iTermStatusBarKnobActionViewController {
    NSButton *_button;
    iTermEditKeyActionWindowController *_windowController;
}

- (instancetype)init {
    return [super initWithNibName:nil bundle:nil];
}

- (void)loadView {
    self.view = [[NSView alloc] init];
}

- (void)viewDidLoad {
    _button = [[NSButton alloc] init];
    [_button setButtonType:NSButtonTypeMomentaryPushIn];
    [_button setTarget:self];
    [_button setAction:@selector(buttonPressed:)];
    [_button setTitle:@"Configure Action…"];
    [_button setBezelStyle:NSBezelStyleTexturedRounded];
    [_button sizeToFit];
    [self.view addSubview:_button];
    [self sizeToFit];
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
}

- (void)sizeToFit {
    [_button sizeToFit];
    NSRect frame = self.view.frame;
    frame.size = _button.bounds.size;
    self.view.frame = frame;
}

- (CGFloat)controlOffset {
    return _button.bounds.size.width - 32;
}

- (void)buttonPressed:(id)sender {
    [_windowController close];
    _windowController = [self newEditKeyActionWindowControllerForAction:[[iTermAction alloc] initWithDictionary:_value]];
}

- (iTermEditKeyActionWindowController *)newEditKeyActionWindowControllerForAction:(iTermAction *)action {
    iTermEditKeyActionWindowController *windowController =
    [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                           mode:iTermEditKeyActionWindowControllerModeUnbound];
    windowController.titleIsInterpolated = YES;
    windowController.escaping = action.escaping;
    if (action) {
        windowController.label = action.title;
        windowController.isNewMapping = NO;
    } else {
        windowController.isNewMapping = YES;
    }
    [windowController setAction:action.action parameter:action.parameter applyMode:action.applyMode];
    [self.view.window beginSheet:windowController.window completionHandler:^(NSModalResponse returnCode) {
        [self editActionDidComplete:action];
    }];
    return windowController;
}

- (void)editActionDidComplete:(iTermAction *)original {
    if (_windowController.ok) {
        _value = _windowController.unboundAction.dictionaryValue;
    }
    [_windowController.window close];
    _windowController = nil;
}

- (void)setHelpURL:(NSURL *)url {
    ITAssertWithMessage(NO, @"Not supported");
}

@end
