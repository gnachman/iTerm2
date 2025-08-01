//
//  ProfilesWindowPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "ProfilesWindowPreferencesViewController.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermImageWell.h"
#import "iTermPreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTermSystemVersion.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "PreferencePanel.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// On macOS 10.13, we see that blur over 26 can turn red (issue 6138).
// On macOS 10.14, we have evidence that it's safe up to 64 (issue 9438).
// On macOS 10.15, this doesn't seem to be a problem and it works up to 64 (issue 9229).
CGFloat iTermMaxBlurRadius(void) {
    return 64;
}

@interface ProfilesWindowPreferencesViewController ()<iTermImageWellDelegate>

@property(nonatomic, copy) NSString *backgroundImageFilename;

@end

@implementation ProfilesWindowPreferencesViewController {
    IBOutlet NSSlider *_transparency;
    IBOutlet NSTextField *_transparencyLabel;
    IBOutlet NSButton *_useBlur;
    IBOutlet NSButton *_initialUseTransparency;
    IBOutlet NSSlider *_blurRadius;
    IBOutlet NSButton *_useBackgroundImage;
    IBOutlet NSTextField *_backgroundImageTextField;
    IBOutlet NSTextField *_transparencyOverrideNotice;
    iTermFunctionCallTextFieldDelegate *_backgroundImageTextFieldDelegate;

    IBOutlet iTermImageWell *_backgroundImagePreview;
    IBOutlet NSButton *_backgroundImageMode;
    IBOutlet NSSlider *_blendAmount;
    IBOutlet NSTextField *_blendAmountLabel;
    IBOutlet NSTextField *_columnsField;
    IBOutlet NSTextField *_rowsField;

    IBOutlet NSTextField *_widthField;
    IBOutlet NSTextField *_heightField;

    IBOutlet NSTextField *_columnsLabel;
    IBOutlet NSButton *_hideAfterOpening;
    IBOutlet NSPopUpButton *_windowStyle;
    IBOutlet NSPopUpButton *_screen;
    IBOutlet NSTextField *_screenLabel;
    IBOutlet NSPopUpButton *_space;
    IBOutlet NSTextField *_rowsLabel;
    IBOutlet NSTextField *_windowStyleLabel;
    IBOutlet NSTextField *_spaceLabel;
    IBOutlet NSButton *_preventTab;
    IBOutlet NSButton *_transparencyAffectsOnlyDefaultBackgroundColor;
    IBOutlet NSButton *_openToolbelt;
    IBOutlet NSButton *_useCustomWindowTitle;
    IBOutlet NSTextField *_customWindowTitle;
    IBOutlet NSView *_settingsForNewWindows;
    IBOutlet NSTextField *_largeBlurRadiusWarning;
    iTermFunctionCallTextFieldDelegate *_customWindowTitleDelegate;

    IBOutlet NSButton *_useCustomTabTitle;
    IBOutlet NSTextField *_customTabTitle;
    iTermFunctionCallTextFieldDelegate *_customTabTitleDelegate;
    NSString *_lastGuid;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)  // In superclass
                                                 name:kReloadAllProfiles
                                               object:nil];
    _backgroundImagePreview.layer.masksToBounds = YES;

    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;
    info = [self defineControl:_backgroundImageTextField
                           key:KEY_BACKGROUND_IMAGE_LOCATION
                   relatedView:nil
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf backgroundImageTextFieldDidChange];
    };
    _backgroundImageTextFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                    passthrough:self
                                                                                  functionsOnly:NO];
    _backgroundImageTextField.delegate = _backgroundImageTextFieldDelegate;
    _useBackgroundImage.state = [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION] != nil ? NSControlStateValueOn : NSControlStateValueOff;
    _backgroundImageTextField.enabled = _useBackgroundImage.state == NSControlStateValueOn;

    info = [self defineControl:_transparency
                           key:KEY_TRANSPARENCY
                   relatedView:_transparencyLabel
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL haveTransparency = (strongSelf->_transparency.doubleValue > 0);
        strongSelf->_transparencyAffectsOnlyDefaultBackgroundColor.enabled = haveTransparency;
        strongSelf->_blurRadius.enabled = (strongSelf->_useBlur.state == NSControlStateValueOn) && haveTransparency;
        strongSelf->_useBlur.enabled = haveTransparency;
        strongSelf->_transparencyOverrideNotice.hidden = !haveTransparency;
    };

    [self defineControl:_initialUseTransparency
                    key:KEY_INITIAL_USE_TRANSPARENCY
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_useBlur
                           key:KEY_BLUR
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL haveTransparency = (strongSelf->_transparency.doubleValue > 0);
        strongSelf->_blurRadius.enabled = (strongSelf->_useBlur.state == NSControlStateValueOn) && haveTransparency;
        [strongSelf updateBlurRadiusWarning];
    };

    _blurRadius.maxValue = iTermMaxBlurRadius();
    info = [self defineControl:_blurRadius
                           key:KEY_BLUR_RADIUS
                   displayName:@"Blur radius"
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^{
        [weakSelf updateBlurRadiusWarning];
    };
    [self updateBlurRadiusWarning];

    info = [self defineControl:_backgroundImageMode
                           key:KEY_BACKGROUND_IMAGE_MODE
                   displayName:@"Background image scaling mode"
                          type:kPreferenceInfoTypePopup];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        switch ((iTermBackgroundImageMode)strongSelf->_backgroundImageMode.selectedTag) {
            case iTermBackgroundImageModeTile:
                self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                break;
            case iTermBackgroundImageModeStretch:
                self->_backgroundImagePreview.imageScaling = NSImageScaleAxesIndependently;
                break;
            case iTermBackgroundImageModeScaleAspectFit:
                self->_backgroundImagePreview.imageScaling = NSImageScaleProportionallyDown;
                break;
            case iTermBackgroundImageModeScaleAspectFill: {
                self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                NSString *filename = [self.backgroundImageFilename stringByExpandingTildeInPath];
                if (filename) {
                    NSImage *anImage = [[NSImage alloc] initWithContentsOfFile:filename];
                    strongSelf->_backgroundImagePreview.image = [anImage it_imageFillingSize:strongSelf->_backgroundImagePreview.frame.size];
                    self->_backgroundImagePreview.imageScaling = NSImageScaleNone;
                    self.backgroundImageFilename = filename;
                }
                break;
            }
        }
    };

    [self defineControl:_blendAmount
                    key:KEY_BLEND
            displayName:@"Background image blending"
                   type:kPreferenceInfoTypeSlider];

    info = [self defineControl:_columnsField
                           key:KEY_COLUMNS
                   displayName:@"Window width in columns"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_rowsField
                           key:KEY_ROWS
                   displayName:@"Window height in rows"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_widthField
                           key:KEY_WIDTH
                   displayName:@"Window width in pixels"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_heightField
                           key:KEY_HEIGHT
                   displayName:@"Window height in pixels"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);


    [self defineControl:_hideAfterOpening
                    key:KEY_HIDE_AFTER_OPENING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_windowStyle
                           key:KEY_WINDOW_TYPE
                   displayName:@"Window style for new windows"
                          type:kPreferenceInfoTypePopup];
    info.onUpdate = ^BOOL{
        // Reading KEY_WINDOW_TYPE can give a value for which the popup has no tag because when
        // the theme is compact some window types are rewritten to compact-specific values by
        // iTermThemedWindowType(). Therefore we must modify the value in user defaults to properly
        // select an item in the popup.
        return [weakSelf updateWindowTypeControlFromSettings];
    };
    [self defineControl:_screen
                    key:KEY_SCREEN
            displayName:@"Initial screen for new windows"
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self screenDidChange]; }
                 update:^BOOL{ [weakSelf updateScreen]; return YES; }];

    info = [self defineControl:_space
                           key:KEY_SPACE
                   displayName:@"Initial desktop/space for new windows"
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if ([strongSelf->_space selectedTag] > 0) {
            [strongSelf maybeWarnAboutSpaces];
        }
    };

    [self defineControl:_preventTab
                    key:KEY_PREVENT_TAB
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_transparencyAffectsOnlyDefaultBackgroundColor
                    key:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_openToolbelt
                    key:KEY_OPEN_TOOLBELT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // Custom window title
    {
        info = [self defineControl:_useCustomWindowTitle
                               key:KEY_USE_CUSTOM_WINDOW_TITLE
                       displayName:@"Enable custom window title for new windows"
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomWindowTitleEnabled];
        };

        _customWindowTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customWindowTitleDelegate.canWarnAboutContextMistake = YES;
        _customWindowTitleDelegate.contextMistakeText = @"This interpolated string is evaluated in the window’s context, not the session’s context. To access variables in the current session, use currentTab.currentSession.sessionVariableNameHere";
        _customWindowTitle.delegate = _customWindowTitleDelegate;
        [self defineControl:_customWindowTitle
                        key:KEY_CUSTOM_WINDOW_TITLE
                displayName:@"Custom window title for new windows"
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomWindowTitleEnabled];
    }

    // Custom tab title
    {
        info = [self defineControl:_useCustomTabTitle
                               key:KEY_USE_CUSTOM_TAB_TITLE
                       displayName:@"Enable custom tab title for new tabs"
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomTabTitleEnabled];
        };

        _customTabTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customTabTitleDelegate.canWarnAboutContextMistake = YES;
        _customTabTitleDelegate.contextMistakeText = @"This interpolated string is evaluated in the tab’s context, not the session’s context. To access variables in the current session, use currentSession.sessionVariableNameHere";
        _customTabTitle.delegate = _customTabTitleDelegate;
        [self defineControl:_customTabTitle
                        key:KEY_CUSTOM_TAB_TITLE
                displayName:@"Custom tab title for new tabs"
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomTabTitleEnabled];
    }

    [self addViewToSearchIndex:_useBackgroundImage
                   displayName:@"Background image enabled"
                       phrases:@[]
                           key:nil];
}

- (BOOL)updateWindowTypeControlFromSettings {
    PreferenceInfo *info = [self infoForControl:_windowStyle];
    [_windowStyle selectItemWithTag:iTermUnthemedWindowType([self intForKey:info.key])];
    if (info.observer) {
        info.observer();
    }
    return YES;
}

- (void)backgroundImageTextFieldDidChange {
    [self loadBackgroundImageWithFilename:[self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
    _useBackgroundImage.state = [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION] != nil ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)updateBlurRadiusWarning {
    if (@available(macOS 10.15, *)) {
        // It seems to get slow around this point on some machines circa 2017.
        if ([self boolForKey:KEY_BLUR] && [self floatForKey:KEY_BLUR_RADIUS] > 26) {
            _largeBlurRadiusWarning.hidden = NO;
            return;
        }
    }
    _largeBlurRadiusWarning.hidden = YES;
}

- (void)updateCustomWindowTitleEnabled {
    _customWindowTitle.enabled = [self boolForKey:KEY_USE_CUSTOM_WINDOW_TITLE];
}

- (void)updateCustomTabTitleEnabled {
    _customTabTitle.enabled = [self boolForKey:KEY_USE_CUSTOM_TAB_TITLE];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _settingsForNewWindows.hidden = YES;
    iTermSizeRememberingView *sizeRememberingView = (iTermSizeRememberingView *)self.view;
    CGSize size = sizeRememberingView.originalSize;
    size.height -= NSHeight(_settingsForNewWindows.frame);
    sizeRememberingView.originalSize = size;
}

#pragma mark - Notifications

// This is also a superclass method.
- (void)reloadProfile {
    [super reloadProfile];
    [self loadBackgroundImageWithFilename:[self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
    [self updateCustomWindowTitleEnabled];
    [self updateCustomTabTitleEnabled];
    [_customWindowTitle it_removeWarning];
    [_customTabTitle it_removeWarning];
    if (![[self stringForKey:KEY_GUID] isEqual:_lastGuid]) {
        _customTabTitleDelegate.canWarnAboutContextMistake = YES;
        _customWindowTitleDelegate.canWarnAboutContextMistake = YES;
        _lastGuid = [self stringForKey:KEY_GUID];
    }
}

#pragma mark - Actions

// Opens a file picker and updates views and state.
- (IBAction)useBackgroundImageDidChange:(id)sender {
    if ([_useBackgroundImage state] == NSControlStateValueOn) {
        [self openFilePicker];
    } else {
        [self loadBackgroundImageWithFilename:nil];
        [self setString:nil forKey:KEY_BACKGROUND_IMAGE_LOCATION];
    }
    _backgroundImageTextField.enabled = _useBackgroundImage.state == NSControlStateValueOn;
}

- (void)openFilePicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    [panel setAllowedContentTypes:[NSImage.imageTypes mapWithBlock:^id _Nullable(NSString *ext) {
        return [UTType typeWithIdentifier:ext];
    }]];

    void (^completion)(NSInteger) = ^(NSInteger result) {
        if (result == NSModalResponseOK) {
            NSURL *url = [[panel URLs] objectAtIndex:0];
            [self checkImage:url.path];
            [self loadBackgroundImageWithFilename:[url path]];
            [self setString:self.backgroundImageFilename forKey:KEY_BACKGROUND_IMAGE_LOCATION];
        } else {
            NSString *previous = [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION];
            [self loadBackgroundImageWithFilename:previous];
        }
    };

    [panel beginSheetModalForWindow:self.view.window completionHandler:completion];
}

#pragma mark - iTermImageWellDelegate

- (void)imageWellDidClick:(iTermImageWell *)imageWell {
    [self openFilePicker];
}

- (void)imageWellDidPerformDropOperation:(iTermImageWell *)imageWell filename:(NSString *)filename {
    [self checkImage:filename];
    [self loadBackgroundImageWithFilename:filename];
    [self setString:filename forKey:KEY_BACKGROUND_IMAGE_LOCATION];
}

#pragma mark - Background Image

// Sets _backgroundImagePreview and _useBackgroundImage.
- (void)loadBackgroundImageWithFilename:(NSString *)filename {
    NSImage *anImage = filename.length > 0 ? [[NSImage alloc] initWithContentsOfFile:[filename stringByExpandingTildeInPath]] : nil;
    if (anImage) {
        [_backgroundImagePreview setImage:anImage];
        self.backgroundImageFilename = filename;
    } else {
        [_backgroundImagePreview setImage:nil];
        self.backgroundImageFilename = nil;
    }
    [self updatePrivateNonDefaultInicators];
}

- (void)updateNonDefaultIndicators {
    [super updateNonDefaultIndicators];
    [self updatePrivateNonDefaultInicators];
}

- (void)updatePrivateNonDefaultInicators {
    _useBackgroundImage.it_showNonDefaultIndicator = [iTermPreferences boolForKey:kPreferenceKeyIndicateNonDefaultValues] && _useBackgroundImage.state == NSControlStateValueOn;
}

- (BOOL)checkImage:(NSString *)filename {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filename options:0 error:&error];
    if (!data) {
        [iTermWarning showWarningWithTitle:error.localizedDescription
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    if (data.length == 0) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The image “%@” could not be loaded because the file is empty.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    if (![[NSImage alloc] initWithData:data]) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The image “%@” could not be loaded because it is corrupt or not a supported format.", filename.lastPathComponent]
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Problem Loading Image"
                                    window:self.view.window];
        return NO;
    }
    return YES;
}

#pragma mark - Screen

- (void)screenDidChange {
    [self repopulateScreen];
    [self setInt:[_screen selectedTag] forKey:KEY_SCREEN];
}

// Refreshes the entries in the list of screens and tries to preserve the current selection.
- (void)repopulateScreen {
    int selectedTag = [_screen selectedTag];
    [_screen removeAllItems];
    int i = 0;
    [_screen addItemWithTitle:@"No Preference"];
    [[_screen lastItem] setTag:-1];
    [_screen addItemWithTitle:@"Screen with Cursor"];
    [[_screen lastItem] setTag:-2];
    NSArray<NSScreen *> *screens = [NSScreen screens];
    [_screen.menu addItem:[NSMenuItem separatorItem]];
    const int numScreens = [screens count];
    for (i = 0; i < numScreens; i++) {
        if (i == 0) {
            [_screen addItemWithTitle:[NSString stringWithFormat:@"Main Screen"]];
        } else {
            [_screen addItemWithTitle:screens[i].it_uniqueName];
        }
        [[_screen lastItem] setTag:i];
    }
    if (selectedTag >= 0 && selectedTag < i) {
        [_screen selectItemWithTag:selectedTag];
    } else if (selectedTag == -1 || selectedTag == -2) {
        [_screen selectItemWithTag:selectedTag];
    } else {
        [_screen selectItemWithTag:-1];
    }
}

- (void)updateScreen {
    [self repopulateScreen];
    if (![_screen selectItemWithTag:[self intForKey:KEY_SCREEN]]) {
        [_screen selectItemWithTag:-1];
    }
}

#pragma mark - Spaces

- (void)maybeWarnAboutSpaces
{
    [iTermWarning showWarningWithTitle:@"To have a new window open in a specific space, "
                                       @"make sure that Spaces is enabled in System "
                                       @"Preferences and that it is configured to switch directly "
                                       @"to a space with ^ Number Keys."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutSpaces"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                                window:self.view.window];
}


@end
