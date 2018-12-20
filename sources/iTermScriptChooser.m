//
//  iTermScriptChooser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import "iTermScriptChooser.h"
#import "NSFileManager+iTerm.h"
#import "SIGCertificate.h"
#import "SIGIdentity.h"

@interface iTermScriptChooser()<NSOpenSavePanelDelegate>
@property (nonatomic, copy) BOOL (^validator)(NSURL *);
@property (nonatomic, copy) void (^completion)(NSURL *, SIGIdentity *);
@property (nonatomic, strong) NSOpenPanel *panel;
@end

@interface iTermSigningAccessoryView : NSView
@property (nonatomic, readonly) SIGIdentity *selectedSigningIdentity;
@end

@implementation iTermSigningAccessoryView {
    NSButton *_signButton;
    NSPopUpButton *_identityButton;
    NSArray<SIGIdentity *> *_identities;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _identities = [[SIGIdentity allSigningIdentities] sortedArrayUsingComparator:^NSComparisonResult(SIGIdentity * _Nonnull obj1, SIGIdentity * _Nonnull obj2) {
            return [obj1.signingCertificate.longDescription compare:obj2.signingCertificate.longDescription];
        }];
        if (_identities.count == 0) {
            return nil;
        }
        _signButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 2, 18, 18)];
        [_signButton setTarget:self];
        [_signButton setAction:@selector(didToggleSignButton:)];
        _signButton.translatesAutoresizingMaskIntoConstraints = NO;
        _signButton.buttonType = NSSwitchButton;
        _signButton.title = @"Code-sign exported script using identity: ";
        [_signButton sizeToFit];
        [self addSubview:_signButton];

        _identityButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(22, 0, 400, 22) pullsDown:NO];
        _identityButton.translatesAutoresizingMaskIntoConstraints = NO;
        _identityButton.enabled = NO;
        [self addSubview:_identityButton];
        [_identities enumerateObjectsUsingBlock:^(SIGIdentity * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:obj.signingCertificate.longDescription
                                                              action:nil
                                                       keyEquivalent:@""];
            menuItem.tag = idx;
            [self->_identityButton.menu addItem:menuItem];
        }];

        [_signButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSDictionary *views = NSDictionaryOfVariableBindings(_signButton, _identityButton);
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[_signButton]-10-[_identityButton]-10-|"
                                                                     options:0
                                                                     metrics:@{}
                                                                       views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-8-[_identityButton]-8-|"
                                                                     options:0
                                                                     metrics:@{}
                                                                       views:views]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:_signButton
                                                         attribute:NSLayoutAttributeCenterY
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:_identityButton
                                                         attribute:NSLayoutAttributeCenterY
                                                        multiplier:1
                                                          constant:0]];
    }
    return self;
}

- (void)didToggleSignButton:(id)sender {
    _identityButton.enabled = (_identities.count > 0 &&
                               _signButton.state == NSOnState);
}

- (SIGIdentity *)selectedSigningIdentity {
    if (_signButton.state != NSOnState) {
        return nil;
    }
    return _identities[_identityButton.selectedTag];
}

@end

@implementation iTermScriptChooser {
    iTermSigningAccessoryView *_signingAccessoryView;
}

+ (void)chooseWithValidator:(BOOL (^)(NSURL *))validator
                 completion:(void (^)(NSURL *, SIGIdentity *))completion {
    iTermScriptChooser *chooser = [[self alloc] init];
    chooser.validator = validator;
    chooser.completion = completion;
    [chooser choose];
}

- (iTermSigningAccessoryView *)newSigningAccessoryView {
    return [[iTermSigningAccessoryView alloc] init];
}

- (void)choose {
    self.panel = [[NSOpenPanel alloc] init];
    self.panel.delegate = self;
    self.panel.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];
    self.panel.canChooseFiles = YES;
    self.panel.canChooseDirectories = YES;
    self.panel.allowsMultipleSelection = NO;
    _signingAccessoryView  = [self newSigningAccessoryView];
    self.panel.accessoryView = _signingAccessoryView;
    [self.panel beginWithCompletionHandler:^(NSModalResponse result) {
        [self didChooseWithResult:result];
    }];
    self.panel.accessoryViewDisclosed = YES;
}

- (void)didChooseWithResult:(NSModalResponse)result {
    if (result != NSFileHandlingPanelOKButton) {
        self.completion(nil, nil);
    } else {
        self.completion(self.panel.URL, _signingAccessoryView.selectedSigningIdentity);
    }
    self.panel = nil;
}

#pragma mark - NSOpenSavePanelDelegate

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    return self.validator(url);
}

- (void)panel:(id)sender didChangeToDirectoryURL:(nullable NSURL *)url {
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    const BOOL ok = [url.path hasPrefix:scriptsPath];
    if (!ok) {
        NSOpenPanel *openPanel = sender;
        openPanel.directoryURL = [NSURL fileURLWithPath:scriptsPath];
    }
}

@end
