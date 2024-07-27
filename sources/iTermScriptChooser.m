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
@property (nonatomic, copy) void (^multiCompletion)(NSArray<NSURL *> *, SIGIdentity *, BOOL);
@property (nonatomic, strong) NSOpenPanel *panel;
@property (nonatomic) BOOL autoLaunchByDefault;
@end

@interface iTermSigningAccessoryView : NSView
@property (nonatomic, readonly) SIGIdentity *selectedSigningIdentity;
@property (nonatomic, readonly) BOOL autolaunch;
- (void)setAutolaunchByDefault:(BOOL)launch;
@end

@implementation iTermSigningAccessoryView {
    NSButton *_signButton;
    NSButton *_launchButton; // Declare the new button
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
        _signButton.buttonType = NSButtonTypeSwitch;
        _signButton.title = @"Code-sign exported script using identity: ";
        [_signButton sizeToFit];
        [self addSubview:_signButton];

        _identityButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(22, 0, 400, 22) pullsDown:NO];
        _identityButton.translatesAutoresizingMaskIntoConstraints = NO;
        _identityButton.enabled = NO;
        [self addSubview:_identityButton];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MM-dd-yyyy"
                                                                   options:0
                                                                    locale:[NSLocale currentLocale]];
        [_identities enumerateObjectsUsingBlock:^(SIGIdentity * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *formattedDate = [dateFormatter stringFromDate:obj.signingCertificate.expirationDate];
            NSString *title = [NSString stringWithFormat:@"%@, expires %@",
                               obj.signingCertificate.longDescription, formattedDate];
            NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                              action:nil
                                                       keyEquivalent:@""];
            menuItem.tag = idx;
            [self->_identityButton.menu addItem:menuItem];
        }];

        _launchButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 18, 18)];
        _launchButton.target = self;
        _launchButton.action = @selector(toggleAutoLaunch:);
        _launchButton.translatesAutoresizingMaskIntoConstraints = NO;
        _launchButton.buttonType = NSButtonTypeSwitch;
        _launchButton.title = @"Offer to launch automatically during installation";
        _launchButton.state = NSControlStateValueOff;
        _launchButton.enabled = NO;
        [_launchButton sizeToFit];
        [self addSubview:_launchButton];

        NSDictionary *views = NSDictionaryOfVariableBindings(_signButton, _identityButton, _launchButton);
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[_signButton]-10-[_identityButton]-10-|"
                                                                     options:0
                                                                     metrics:@{}
                                                                       views:views]];
        [self addConstraints:
         [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[_launchButton]-10-|"
                                                 options:0
                                                 metrics:@{}
                                                   views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-8-[_signButton]-8-[_launchButton]-8-|"
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
                               _signButton.state == NSControlStateValueOn);
    _launchButton.enabled = _identityButton.enabled;
}

- (SIGIdentity *)selectedSigningIdentity {
    if (_signButton.state != NSControlStateValueOn) {
        return nil;
    }
    return _identities[_identityButton.selectedTag];
}

- (void)toggleAutoLaunch:(id)sender {
    _autolaunch = (_launchButton.state == NSControlStateValueOn);
}

- (void)setAutolaunchByDefault:(BOOL)launch {
    _launchButton.state = launch ? NSControlStateValueOn : NSControlStateValueOff;
}

@end

@implementation iTermScriptChooser {
    iTermSigningAccessoryView *_signingAccessoryView;
}

+ (void)chooseMultipleWithValidator:(BOOL (^)(NSURL *))validator 
                autoLaunchByDefault:(BOOL)autoLaunchByDefault
                         completion:(void (^)(NSArray<NSURL *> *, 
                                              SIGIdentity *,
                                              BOOL))completion {
    iTermScriptChooser *chooser = [[self alloc] init];
    chooser.validator = validator;
    chooser.multiCompletion = completion;
    chooser.autoLaunchByDefault = autoLaunchByDefault;
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
    self.panel.allowsMultipleSelection = (self.multiCompletion != nil);
    _signingAccessoryView  = [self newSigningAccessoryView];
    [_signingAccessoryView setAutolaunchByDefault:self.autoLaunchByDefault];
    self.panel.accessoryView = _signingAccessoryView;
    [self.panel beginWithCompletionHandler:^(NSModalResponse result) {
        [self didChooseWithResult:result];
    }];
    self.panel.accessoryViewDisclosed = YES;
}

- (void)didChooseWithResult:(NSModalResponse)result {
    if (self.multiCompletion) {
        if (result != NSModalResponseOK) {
            self.multiCompletion(nil, nil, _signingAccessoryView.autolaunch);
        } else {
            self.multiCompletion(self.panel.URLs,
                                 _signingAccessoryView.selectedSigningIdentity,
                                 _signingAccessoryView.autolaunch);
        }
    } else {
        if (result != NSModalResponseOK) {
            self.completion(nil, nil);
        } else {
            self.completion(self.panel.URL, _signingAccessoryView.selectedSigningIdentity);
        }
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
