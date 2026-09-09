//
//  ProfilesWindowPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/16/14.
//
//

#import "ProfilesWindowPreferencesViewController.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermImageWell.h"
#import "iTermPreferences.h"
#import "iTermSizeRememberingView.h"
#import "iTerm2SharedARC-Swift.h"
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

typedef NS_ENUM(NSUInteger, iTermWindowUnitsTag) {
    iTermWindowUnitsTagCells = 0,
    iTermWindowUnitsTagScreenPercentage = 1
};

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
    IBOutlet NSPopUpButton *_backgroundImageSourceMode;
    IBOutlet NSTextField *_backgroundImageLabel;  // text swaps between "Image:" and "Folder:"
    IBOutlet NSTextField *_backgroundImageTextField;
    IBOutlet NSTextField *_rotationIntervalUnitsLabel;
    IBOutlet NSTextField *_backgroundImageFolderTextField;
    IBOutlet NSTextField *_backgroundImageFolderIntervalLabel;
    IBOutlet NSTextField *_backgroundImageFolderIntervalField;
    IBOutlet NSTextField *_transparencyOverrideNotice;
    iTermFunctionCallTextFieldDelegate *_backgroundImageTextFieldDelegate;

    IBOutlet iTermImageWell *_backgroundImagePreview;
    IBOutlet NSButton *_backgroundImageMode;
    IBOutlet NSSlider *_blendAmount;
    IBOutlet NSTextField *_columnsField;
    IBOutlet NSTextField *_rowsField;

    IBOutlet NSTextField *_widthField;
    IBOutlet NSTextField *_heightField;
    IBOutlet NSTextField *_percentageWidthField;
    IBOutlet NSTextField *_percentageHeightField;
    IBOutlet NSTextField *_widthLabel;
    IBOutlet NSTextField *_heightLabel;
    IBOutlet NSPopUpButton *_columnsUnitsButton;
    IBOutlet NSPopUpButton *_rowsUnitsButton;
    IBOutlet NSTextField *_byLabel;

    IBOutlet NSButton *_hideAfterOpening;
    IBOutlet NSButton *_lockSizeAutomatically;
    IBOutlet NSPopUpButton *_windowStyle;
    IBOutlet NSPopUpButton *_screen;
    IBOutlet NSTextField *_screenLabel;
    IBOutlet NSPopUpButton *_space;
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
    _backgroundImagePreview.acceptsFolders = YES;

    __weak __typeof(self) weakSelf = self;
    PreferenceInfo *info;
    info = [self defineControl:_backgroundImageTextField
                           key:KEY_BACKGROUND_IMAGE_LOCATION
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImagePathDisplayName", nil, [NSBundle mainBundle], @"Path to background image", @"Display name for the background-image path field.")
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf backgroundImageTextFieldDidChange];
    };
    _backgroundImageTextFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                    passthrough:self
                                                                                  functionsOnly:NO];
    _backgroundImageTextField.delegate = _backgroundImageTextFieldDelegate;
    _backgroundImageFolderTextField.delegate = _backgroundImageTextFieldDelegate;
    info = [self defineControl:_backgroundImageSourceMode
                           key:KEY_BACKGROUND_IMAGE_SOURCE_MODE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageSourceMode", nil, [NSBundle mainBundle], @"Background image source mode", @"Display name for the background-image source mode control.")
                          type:kPreferenceInfoTypePopup];
    info.observer = ^{
        [weakSelf synchronizeBackgroundImageEnabledState];
        [weakSelf updateBackgroundImageUI];
        [weakSelf loadBackgroundImageForCurrentSource];
    };
    info = [self defineControl:_backgroundImageFolderTextField
                           key:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageFolderPath", nil, [NSBundle mainBundle], @"Path to background image folder", @"Display name for the background-image folder path field.")
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf backgroundImageFolderTextFieldDidChange];
    };
    info = [self defineControl:_backgroundImageFolderIntervalField
                           key:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageFolderInterval", nil, [NSBundle mainBundle], @"Background image folder interval", @"Display name for the background-image folder rotation interval field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.observer = ^{
        [weakSelf sanitizeBackgroundImageFolderInterval];
    };

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
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BlurRadius", nil, [NSBundle mainBundle], @"Blur radius", @"Display name for the blur radius slider.")
                          type:kPreferenceInfoTypeSlider];
    info.observer = ^{
        [weakSelf updateBlurRadiusWarning];
    };
    [self updateBlurRadiusWarning];

    info = [self defineControl:_backgroundImageMode
                           key:KEY_BACKGROUND_IMAGE_MODE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageScalingMode", nil, [NSBundle mainBundle], @"Background image scaling mode", @"Display name for the background-image scaling mode picker.")
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
            displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageBlending", nil, [NSBundle mainBundle], @"Background image blending", @"Display name for the background-image blending slider.")
                   type:kPreferenceInfoTypeSlider];
    [self updateBackgroundImageUI];
    [self loadBackgroundImageForCurrentSource];

    info = [self defineControl:_columnsField
                           key:KEY_COLUMNS
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.WidthInColumns", nil, [NSBundle mainBundle], @"Window width in columns", @"Display name for the window width (in character columns) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_rowsField
                           key:KEY_ROWS
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.HeightInRows", nil, [NSBundle mainBundle], @"Window height in rows", @"Display name for the window height (in character rows) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_widthField
                           key:KEY_WIDTH
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.WidthInPixels", nil, [NSBundle mainBundle], @"Window width in pixels", @"Display name for the window width (in pixels) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);

    info = [self defineControl:_percentageWidthField
                           key:KEY_WIDTH_PERCENTAGE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.WidthInPercent", nil, [NSBundle mainBundle], @"Window width in percentage of screen width", @"Display name for the window width (as a percentage of screen width) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100);

    info = [self defineControl:_percentageHeightField
                           key:KEY_HEIGHT_PERCENTAGE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.HeightInPercent", nil, [NSBundle mainBundle], @"Window height in percentage of screen height", @"Display name for the window height (as a percentage of screen height) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100);

    info = [self defineControl:_heightField
                           key:KEY_HEIGHT
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.HeightInPixels", nil, [NSBundle mainBundle], @"Window height in pixels", @"Display name for the window height (in pixels) field.")
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, iTermMaxInitialSessionSize);


    [self defineControl:_hideAfterOpening
                    key:KEY_HIDE_AFTER_OPENING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lockSizeAutomatically
                    key:KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_windowStyle
                           key:KEY_WINDOW_TYPE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.WindowStyle", nil, [NSBundle mainBundle], @"Window style for new windows", @"Display name for the window style picker.")
                          type:kPreferenceInfoTypePopup];
    info.onUpdate = ^BOOL{
        // Reading KEY_WINDOW_TYPE can give a value for which the popup has no tag because when
        // the theme is compact some window types are rewritten to compact-specific values by
        // iTermThemedWindowType(). Therefore we must modify the value in user defaults to properly
        // select an item in the popup.
        return [weakSelf updateWindowTypeControlFromSettings];
    };
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf saveWindowType];
    };
    [self defineControl:_screen
                    key:KEY_SCREEN
            displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.InitialScreen", nil, [NSBundle mainBundle], @"Initial screen for new windows", @"Display name for the initial screen picker.")
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self screenDidChange]; }
                 update:^BOOL{ [weakSelf updateScreen]; return YES; }];

    info = [self defineControl:_space
                           key:KEY_SPACE
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.InitialSpace", nil, [NSBundle mainBundle], @"Initial desktop/space for new windows", @"Display name for the initial desktop/space picker.")
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
                       displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.EnableCustomWindowTitle", nil, [NSBundle mainBundle], @"Enable custom window title for new windows", @"Display name for the checkbox enabling a custom window title for new windows.")
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomWindowTitleEnabled];
        };

        _customWindowTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customWindowTitleDelegate.canWarnAboutContextMistake = YES;
        _customWindowTitleDelegate.contextMistakeText = NSLocalizedStringWithDefaultValue(@"Profiles.Window.WindowTitleContextMistake", nil, [NSBundle mainBundle], @"This interpolated string is evaluated in the window’s context, not the session’s context. To access variables in the current session, use currentTab.currentSession.sessionVariableNameHere", @"Warning shown when a custom window title references session variables directly instead of through the window’s context.");
        _customWindowTitle.delegate = _customWindowTitleDelegate;
        [self defineControl:_customWindowTitle
                        key:KEY_CUSTOM_WINDOW_TITLE
                displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.CustomWindowTitle", nil, [NSBundle mainBundle], @"Custom window title for new windows", @"Display name for the custom window title text field.")
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomWindowTitleEnabled];
    }

    // Custom tab title
    {
        info = [self defineControl:_useCustomTabTitle
                               key:KEY_USE_CUSTOM_TAB_TITLE
                       displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.EnableCustomTabTitle", nil, [NSBundle mainBundle], @"Enable custom tab title for new tabs", @"Display name for the checkbox enabling a custom tab title for new tabs.")
                              type:kPreferenceInfoTypeCheckbox];
        info.onChange = ^{
            [weakSelf updateCustomTabTitleEnabled];
        };

        _customTabTitleDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                                                        passthrough:self
                                                                                      functionsOnly:NO];
        _customTabTitleDelegate.canWarnAboutContextMistake = YES;
        _customTabTitleDelegate.contextMistakeText = NSLocalizedStringWithDefaultValue(@"Profiles.Window.TabTitleContextMistake", nil, [NSBundle mainBundle], @"This interpolated string is evaluated in the tab’s context, not the session’s context. To access variables in the current session, use currentSession.sessionVariableNameHere", @"Warning shown when a custom tab title references session variables directly instead of through the tab’s context.");
        _customTabTitle.delegate = _customTabTitleDelegate;
        [self defineControl:_customTabTitle
                        key:KEY_CUSTOM_TAB_TITLE
                displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.CustomTabTitle", nil, [NSBundle mainBundle], @"Custom tab title for new tabs", @"Display name for the custom tab title text field.")
                       type:kPreferenceInfoTypeStringTextField];
        [self updateCustomTabTitleEnabled];
    }

    [self addViewToSearchIndex:_useBackgroundImage
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageEnabled", nil, [NSBundle mainBundle], @"Background image enabled", @"Search index display name for the background-image enabled toggle.")
                       phrases:@[]
                           key:nil];
    [self addViewToSearchIndex:_backgroundImageSourceMode
                   displayName:NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImageSourceMode", nil, [NSBundle mainBundle], @"Background image source mode", @"Display name for the background-image source mode control.")
                       phrases:@[]
                           key:nil];
}

- (NSDictionary *)dictionaryToSaveWindowType:(iTermWindowType)windowType {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[KEY_WINDOW_TYPE] = @(windowType);
    switch ((iTermWindowUnitsTag)_rowsUnitsButton.selectedTag) {
        case iTermWindowUnitsTagScreenPercentage: {
            NSInteger height = _percentageHeightField.integerValue;
            if (height < 0) {
                height = 50;
            }
            dict[KEY_HEIGHT_PERCENTAGE] = @(height);
            break;
        }
        case iTermWindowUnitsTagCells:
            dict[KEY_HEIGHT_PERCENTAGE] = @-1;
            dict[KEY_ROWS] = @(_rowsField.integerValue);
            break;
    }

    switch ((iTermWindowUnitsTag)_columnsUnitsButton.selectedTag) {
        case iTermWindowUnitsTagScreenPercentage: {
            NSInteger width = _percentageWidthField.integerValue;
            if (width < 0) {
                width = 25;
            }
            dict[KEY_WIDTH_PERCENTAGE] = @(width);
            break;
        }
        case iTermWindowUnitsTagCells:
            dict[KEY_WIDTH_PERCENTAGE] = @-1;
            dict[KEY_COLUMNS] = @(_columnsField.integerValue);
            break;
    }
    return dict;
}

- (void)saveWindowType {
    const BOOL percentage = (_columnsUnitsButton.selectedTag == iTermWindowUnitsTagScreenPercentage ||
                             _rowsUnitsButton.selectedTag == iTermWindowUnitsTagScreenPercentage);
    switch ((iTermWindowType)_windowStyle.selectedTag) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_CENTERED:
        case WINDOW_TYPE_COMPACT_CENTERED:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:_windowStyle.selectedTag]];
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            [self setInteger:_windowStyle.selectedTag
                      forKey:KEY_WINDOW_TYPE];
            break;

        case WINDOW_TYPE_TOP_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_TOP_PERCENTAGE : WINDOW_TYPE_TOP_CELLS]];
            break;
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_BOTTOM_PERCENTAGE : WINDOW_TYPE_BOTTOM_CELLS]];
            break;
        case WINDOW_TYPE_LEFT_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_LEFT_PERCENTAGE : WINDOW_TYPE_LEFT_CELLS]];
            break;
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
            [self setObjectsFromDictionary:[self dictionaryToSaveWindowType:percentage ? WINDOW_TYPE_RIGHT_PERCENTAGE : WINDOW_TYPE_RIGHT_CELLS]];
            break;

        case WINDOW_TYPE_BOTTOM_CELLS:
        case WINDOW_TYPE_TOP_CELLS:
        case WINDOW_TYPE_LEFT_CELLS:
        case WINDOW_TYPE_RIGHT_CELLS:
            assert(NO);
            break;
    }
}

- (BOOL)updateWindowTypeControlFromSettings {
    PreferenceInfo *info = [self infoForControl:_windowStyle];
    iTermWindowType type = iTermUnthemedWindowType([self intForKey:info.key]);
    // Unit pop-up titles, shared across the window-type cases below. The "%" is literal (these are
    // titles, never format strings) so it stays unescaped.
    NSString *columnsUnitTitle = NSLocalizedStringWithDefaultValue(@"Profiles.Window.UnitColumns", nil, [NSBundle mainBundle], @"Columns", @"Window-size unit: measure width in character columns.");
    NSString *percentOfScreenWidthTitle = NSLocalizedStringWithDefaultValue(@"Profiles.Window.UnitPercentOfScreenWidth", nil, [NSBundle mainBundle], @"% of screen width", @"Window-size unit: measure width as a percentage of the screen width.");
    NSString *rowsUnitTitle = NSLocalizedStringWithDefaultValue(@"Profiles.Window.UnitRows", nil, [NSBundle mainBundle], @"Rows", @"Window-size unit: measure height in character rows.");
    NSString *percentOfScreenHeightTitle = NSLocalizedStringWithDefaultValue(@"Profiles.Window.UnitPercentOfScreenHeight", nil, [NSBundle mainBundle], @"% of screen height", @"Window-size unit: measure height as a percentage of the screen height.");
    switch (type) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP_PERCENTAGE:
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
        case WINDOW_TYPE_LEFT_PERCENTAGE:
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_CENTERED:
        case WINDOW_TYPE_COMPACT_CENTERED:
            [_windowStyle selectItemWithTag:type];
            break;
        case WINDOW_TYPE_BOTTOM_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_BOTTOM_PERCENTAGE];
            break;
        case WINDOW_TYPE_TOP_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_TOP_PERCENTAGE];
            break;
        case WINDOW_TYPE_LEFT_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_LEFT_PERCENTAGE];
            break;
        case WINDOW_TYPE_RIGHT_CELLS:
            [_windowStyle selectItemWithTag:WINDOW_TYPE_RIGHT_PERCENTAGE];
            break;
    }
    if (info.observer) {
        info.observer();
    }
    _columnsUnitsButton.hidden = YES;
    _rowsUnitsButton.hidden = YES;
    const BOOL columnsIsCells = (![self valueIsExplicitlySetForKey:KEY_WIDTH_PERCENTAGE] ||
                                 [self doubleForKey:KEY_WIDTH_PERCENTAGE] < 0);
    const BOOL rowsIsCells = (![self valueIsExplicitlySetForKey:KEY_HEIGHT_PERCENTAGE] ||
                              [self doubleForKey:KEY_HEIGHT_PERCENTAGE] < 0);

    switch (type) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_CENTERED:
        case WINDOW_TYPE_COMPACT_CENTERED:
        case WINDOW_TYPE_NO_TITLE_BAR:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            _columnsUnitsButton.hidden = NO;
            _columnsUnitsButton.menu.itemArray[0].title = columnsUnitTitle;
            _columnsUnitsButton.menu.itemArray[1].title = percentOfScreenWidthTitle;
            [_columnsUnitsButton selectItemWithTag:columnsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _rowsUnitsButton.hidden = NO;
            _rowsUnitsButton.menu.itemArray[0].title = rowsUnitTitle;
            _rowsUnitsButton.menu.itemArray[1].title = percentOfScreenHeightTitle;
            [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_ACCESSORY:
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            _widthLabel.hidden = NO;
            _heightLabel.hidden = NO;

            _widthLabel.stringValue = NSLocalizedStringWithDefaultValue(@"Profiles.Window.ColumnsBy", nil, [NSBundle mainBundle], @"columns by", @"Label between the columns field and the rows field in the window-size row.");
            _heightLabel.stringValue = NSLocalizedStringWithDefaultValue(@"Profiles.Window.Rows", nil, [NSBundle mainBundle], @"rows", @"Label after the rows field in the window-size row.");

            _byLabel.hidden = YES;
            break;

        case WINDOW_TYPE_BOTTOM_CELLS:
        case WINDOW_TYPE_TOP_CELLS:
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            _columnsUnitsButton.hidden = NO;
            _columnsUnitsButton.menu.itemArray[0].title = columnsUnitTitle;
            _columnsUnitsButton.menu.itemArray[1].title = percentOfScreenWidthTitle;
            [_columnsUnitsButton selectItemWithTag:columnsIsCells ? 0 : 1];

            _rowsUnitsButton.hidden = NO;
            _rowsUnitsButton.menu.itemArray[0].title = rowsUnitTitle;
            _rowsUnitsButton.menu.itemArray[1].title = percentOfScreenHeightTitle;
            [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_LEFT_CELLS:
        case WINDOW_TYPE_RIGHT_CELLS: {
            _columnsField.enabled = YES;
            _columnsField.hidden = NO;

            _rowsField.enabled = YES;
            _rowsField.hidden = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            _columnsUnitsButton.hidden = NO;
            _columnsUnitsButton.menu.itemArray[0].title = columnsUnitTitle;
            _columnsUnitsButton.menu.itemArray[1].title = percentOfScreenWidthTitle;
            [_columnsUnitsButton selectItemWithTag:columnsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _rowsUnitsButton.hidden = NO;
            _rowsUnitsButton.menu.itemArray[0].title = rowsUnitTitle;
            _rowsUnitsButton.menu.itemArray[1].title = percentOfScreenHeightTitle;
            [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = YES;
            break;
        }

        case WINDOW_TYPE_TOP_PERCENTAGE:
        case WINDOW_TYPE_BOTTOM_PERCENTAGE:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            _columnsUnitsButton.hidden = NO;
            _columnsUnitsButton.menu.itemArray[0].title = columnsUnitTitle;
            _columnsUnitsButton.menu.itemArray[1].title = percentOfScreenWidthTitle;
            [_columnsUnitsButton selectItemWithTag:columnsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _rowsUnitsButton.hidden = NO;
            _rowsUnitsButton.menu.itemArray[0].title = rowsUnitTitle;
            _rowsUnitsButton.menu.itemArray[1].title = percentOfScreenHeightTitle;
            [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = NO;
            break;

        case WINDOW_TYPE_LEFT_PERCENTAGE:
        case WINDOW_TYPE_RIGHT_PERCENTAGE:
            _columnsField.hidden = !columnsIsCells;
            _rowsField.hidden = !rowsIsCells;
            _percentageWidthField.hidden = columnsIsCells;
            _percentageHeightField.hidden = rowsIsCells;

            _columnsField.enabled = YES;
            _rowsField.enabled = YES;
            _percentageWidthField.enabled = YES;
            _percentageHeightField.enabled = YES;

            _columnsUnitsButton.hidden = NO;
            _columnsUnitsButton.menu.itemArray[0].title = columnsUnitTitle;
            _columnsUnitsButton.menu.itemArray[1].title = percentOfScreenWidthTitle;
            [_columnsUnitsButton selectItemWithTag:columnsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _rowsUnitsButton.hidden = NO;
            _rowsUnitsButton.menu.itemArray[0].title = rowsUnitTitle;
            _rowsUnitsButton.menu.itemArray[1].title = percentOfScreenHeightTitle;
            [_rowsUnitsButton selectItemWithTag:rowsIsCells ? iTermWindowUnitsTagCells : iTermWindowUnitsTagScreenPercentage];

            _widthLabel.hidden = YES;
            _heightLabel.hidden = YES;

            _byLabel.hidden = YES;
            break;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            _columnsField.hidden = NO;
            _columnsField.enabled = NO;

            _rowsField.hidden = NO;
            _rowsField.enabled = NO;

            _percentageWidthField.hidden = YES;
            _percentageHeightField.hidden = YES;

            _columnsUnitsButton.hidden = YES;
            _rowsUnitsButton.hidden = YES;
            _widthLabel.hidden = NO;
            _heightLabel.hidden = NO;

            _widthLabel.stringValue = NSLocalizedStringWithDefaultValue(@"Profiles.Window.ColumnsBy", nil, [NSBundle mainBundle], @"columns by", @"Label between the columns field and the rows field in the window-size row.");
            _heightLabel.stringValue = NSLocalizedStringWithDefaultValue(@"Profiles.Window.Rows", nil, [NSBundle mainBundle], @"rows", @"Label after the rows field in the window-size row.");

            _byLabel.hidden = YES;
            break;
    }
    NSArray<NSView *> *views = @[ _columnsField,           // Editable number of columns
                                  _percentageWidthField,   // Editable percent of screen width
                                  _widthLabel,             // "columns by"
                                  _columnsUnitsButton,      // Popup [Columns / % of screen width]
                                  _byLabel,                // "by"
                                  _rowsField,              // Editable number of rows
                                  _percentageHeightField,  // Editable percent of screen height
                                  _heightLabel,            // "rows"
                                  _rowsUnitsButton          // Popup [Rows / % of screen height]
    ];
    CGFloat x = 0;
    for (NSView *view in views) {
        if (view.isHidden) {
            continue;
        }
        NSTextField *textField = [NSTextField castFrom:view];
        if (textField && !textField.isEditable) {
            [textField sizeToFit];
        }
        [[NSButton castFrom:view] sizeToFit];

        NSRect frame = view.frame;
        frame.origin.x = x;
        view.frame = frame;
        DLog(@"Set frame of %@ to %@", view.identifier, NSStringFromRect(frame));
        x += frame.size.width;
    }
    return YES;
}

- (void)backgroundImageTextFieldDidChange {
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

- (void)backgroundImageFolderTextFieldDidChange {
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

- (void)sanitizeBackgroundImageFolderInterval {
    const NSInteger minimumInterval = (NSInteger)iTermBackgroundImageRotationManager.minimumInterval;
    NSInteger interval = [self integerForKey:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL];
    if (interval < minimumInterval) {
        [self setInteger:minimumInterval forKey:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL];
        _backgroundImageFolderIntervalField.integerValue = minimumInterval;
    }
}

- (void)updateBlurRadiusWarning {
    // It seems to get slow around this point on some machines circa 2017.
    if ([self boolForKey:KEY_BLUR] && [self floatForKey:KEY_BLUR_RADIUS] > 26) {
        _largeBlurRadiusWarning.hidden = NO;
        return;
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
    [self sanitizeBackgroundImageFolderInterval];
    [self synchronizeBackgroundImageEnabledState];
    [self updateBackgroundImageUI];
    [self loadBackgroundImageForCurrentSource];
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

- (IBAction)unitsChanged:(id)sender {
    [self saveWindowType];
    [self updateWindowTypeControlFromSettings];
}

// Opens a file picker and updates views and state.
- (IBAction)useBackgroundImageDidChange:(id)sender {
    if ([_useBackgroundImage state] == NSControlStateValueOn) {
        [self openBackgroundPathPicker];
    } else {
        [self loadBackgroundImageWithFilename:nil];
        if ([self backgroundImageUsesFolderRotation]) {
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
        } else {
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_LOCATION];
        }
    }
    [self updateBackgroundImageUI];
}

- (void)openBackgroundPathPicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.message = NSLocalizedStringWithDefaultValue(@"Profiles.Window.BackgroundImagePickerMessage", nil, [NSBundle mainBundle], @"Choose an image for the background, or a folder to rotate through its images.", @"Prompt in the open panel for choosing a background image or folder.");
    // Image-only filter dims non-image files. Folders stay selectable because
    // canChooseDirectories=YES treats them as containers, not content.
    panel.allowedContentTypes = [NSImage.imageTypes mapWithBlock:^id _Nullable(NSString *ext) {
        return [UTType typeWithIdentifier:ext];
    }];

    void (^completion)(NSInteger) = ^(NSInteger result) {
        if (result == NSModalResponseOK) {
            [self applyBackgroundImageSelectionAtPath:[[panel URLs] firstObject].path];
        } else {
            [self loadBackgroundImageForCurrentSource];
        }
    };

    [panel beginSheetModalForWindow:self.view.window completionHandler:completion];
}

// Applies a user-chosen path (from picker or drop) to the appropriate key and
// source mode, switching mode as needed.
- (void)applyBackgroundImageSelectionAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        [self loadBackgroundImageForCurrentSource];
        return;
    }
    if (isDirectory) {
        if (![self checkFolder:path]) {
            [self loadBackgroundImageForCurrentSource];
            return;
        }
        if ([iTermBackgroundImageRotationManager firstImagePathInFolder:path] == nil) {
            [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.FolderNoImagesMessage", nil, [NSBundle mainBundle], @"The folder “%@” contains no images, so no background image will be shown.", @"Warning body when a chosen background-image folder has no images. %@ is the folder name."), path.lastPathComponent]
                                       actions:@[ iTermLocalizedOK() ]
                                     accessory:nil
                                    identifier:@"BackgroundFolderEmpty"
                                   silenceable:kiTermWarningTypePersistent
                                       heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.EmptyFolderHeading", nil, [NSBundle mainBundle], @"Empty Folder", @"Warning heading shown when a chosen background-image folder contains no images.")
                                        window:self.view.window];
            [self setString:nil forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
            [self updateControlForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
            [self synchronizeBackgroundImageEnabledState];
            [self loadBackgroundImageForCurrentSource];
            [self updateBackgroundImageUI];
            return;
        }
        [self setString:path forKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
        [self setUnsignedInteger:iTermBackgroundImageSourceModeFolderRotation
                          forKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
        [self updateControlForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
    } else {
        [self checkImage:path];
        [self setString:path forKey:KEY_BACKGROUND_IMAGE_LOCATION];
        [self setUnsignedInteger:iTermBackgroundImageSourceModeSingleImage
                          forKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
        [self updateControlForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    }
    [self updateControlForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE];
    [self synchronizeBackgroundImageEnabledState];
    [self loadBackgroundImageForCurrentSource];
    [self updateBackgroundImageUI];
}

#pragma mark - iTermImageWellDelegate

- (void)imageWellDidClick:(iTermImageWell *)imageWell {
    [self openBackgroundPathPicker];
}

- (void)imageWellDidPerformDropOperation:(iTermImageWell *)imageWell filename:(NSString *)filename {
    [self applyBackgroundImageSelectionAtPath:filename];
}

#pragma mark - Background Image

- (BOOL)backgroundImageUsesFolderRotation {
    return [self unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE] == iTermBackgroundImageSourceModeFolderRotation;
}

- (NSString *)backgroundImageConfigurationPathForCurrentSource {
    if ([self backgroundImageUsesFolderRotation]) {
        return [self stringForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION];
    }
    return [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION];
}

- (void)updateBackgroundImageUI {
    const BOOL usesFolderRotation = [self backgroundImageUsesFolderRotation];
    _backgroundImageLabel.stringValue = usesFolderRotation ? @"Folder:" : @"Image:";
    // The image and folder text fields share the same xib rect, so hide the
    // inactive one. Disabled NSControls still consume hit-testing and would
    // block clicks to the field underneath.
    _backgroundImageTextField.hidden = usesFolderRotation;
    _backgroundImageFolderTextField.hidden = !usesFolderRotation;
    _backgroundImageFolderIntervalLabel.labelEnabled = usesFolderRotation;
    _rotationIntervalUnitsLabel.labelEnabled = usesFolderRotation;
    _backgroundImageFolderIntervalField.enabled = usesFolderRotation;
}

- (void)synchronizeBackgroundImageEnabledState {
    _useBackgroundImage.state = self.backgroundImageConfigurationPathForCurrentSource.length > 0 ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)loadBackgroundImageForCurrentSource {
    if ([self backgroundImageUsesFolderRotation]) {
        [self loadBackgroundImageWithFilename:[self firstImageFilenameInFolder:[self stringForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION]]];
    } else {
        [self loadBackgroundImageWithFilename:[self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
    }
}

- (NSString *)firstImageFilenameInFolder:(NSString *)folderPath {
    return [iTermBackgroundImageRotationManager firstImagePathInFolder:folderPath];
}

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
                                   actions:@[ iTermLocalizedOK() ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ProblemLoadingImageHeading", nil, [NSBundle mainBundle], @"Problem Loading Image", @"Warning heading shown when a background image cannot be loaded.")
                                    window:self.view.window];
        return NO;
    }
    if (data.length == 0) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ImageEmptyMessage", nil, [NSBundle mainBundle], @"The image “%@” could not be loaded because the file is empty.", @"Warning body when a background image file is empty. %@ is the image file name."), filename.lastPathComponent]
                                   actions:@[ iTermLocalizedOK() ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ProblemLoadingImageHeading", nil, [NSBundle mainBundle], @"Problem Loading Image", @"Warning heading shown when a background image cannot be loaded.")
                                    window:self.view.window];
        return NO;
    }
    if (![[NSImage alloc] initWithData:data]) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ImageCorruptMessage", nil, [NSBundle mainBundle], @"The image “%@” could not be loaded because it is corrupt or not a supported format.", @"Warning body when a background image is corrupt or an unsupported format. %@ is the image file name."), filename.lastPathComponent]
                                   actions:@[ iTermLocalizedOK() ]
                                 accessory:nil
                                identifier:@"BackgroundImageUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ProblemLoadingImageHeading", nil, [NSBundle mainBundle], @"Problem Loading Image", @"Warning heading shown when a background image cannot be loaded.")
                                    window:self.view.window];
        return NO;
    }
    return YES;
}

- (BOOL)checkFolder:(NSString *)filename {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&isDirectory] || !isDirectory) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.FolderNotDirectoryMessage", nil, [NSBundle mainBundle], @"The folder “%@” could not be used because it does not exist or is not a directory.", @"Warning body when a chosen background-image folder is missing or is not a directory. %@ is the folder name."), filename.lastPathComponent]
                                   actions:@[ iTermLocalizedOK() ]
                                 accessory:nil
                                identifier:@"BackgroundFolderUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ProblemLoadingFolderHeading", nil, [NSBundle mainBundle], @"Problem Loading Folder", @"Warning heading shown when a background-image folder cannot be loaded.")
                                    window:self.view.window];
        return NO;
    }
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:filename isDirectory:YES]
                                                               includingPropertiesForKeys:nil
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];
    if (!contents) {
        [iTermWarning showWarningWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.FolderUnreadableMessage", nil, [NSBundle mainBundle], @"The folder “%@” could not be read.", @"Warning body when a chosen background-image folder cannot be read. %@ is the folder name."), filename.lastPathComponent]
                                   actions:@[ iTermLocalizedOK() ]
                                 accessory:nil
                                identifier:@"BackgroundFolderUnreadable"
                               silenceable:kiTermWarningTypePersistent
                                   heading:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ProblemLoadingFolderHeading", nil, [NSBundle mainBundle], @"Problem Loading Folder", @"Warning heading shown when a background-image folder cannot be loaded.")
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
    [_screen addItemWithTitle:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ScreenNoPreference", nil, [NSBundle mainBundle], @"No Preference", @"Initial-screen picker option: no preference for which display a new window opens on.")];
    [[_screen lastItem] setTag:-1];
    [_screen addItemWithTitle:NSLocalizedStringWithDefaultValue(@"Profiles.Window.ScreenWithCursor", nil, [NSBundle mainBundle], @"Screen with Cursor", @"Initial-screen picker option: open new windows on whichever display has the mouse cursor.")];
    [[_screen lastItem] setTag:-2];
    NSArray<NSScreen *> *screens = [NSScreen screens];
    [_screen.menu addItem:[NSMenuItem separatorItem]];
    const int numScreens = [screens count];
    for (i = 0; i < numScreens; i++) {
        if (i == 0) {
            [_screen addItemWithTitle:[NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"Profiles.Window.MainScreen", nil, [NSBundle mainBundle], @"Main Screen", @"Menu item title for the primary display in the initial-screen picker.")]];
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
    [iTermWarning showWarningWithTitle:NSLocalizedStringWithDefaultValue(@"Profiles.Window.SpacesWarning", nil, [NSBundle mainBundle], @"To have a new window open in a specific space, "
                                       @"make sure that Spaces is enabled in System "
                                       @"Preferences and that it is configured to switch directly "
                                       @"to a space with ^ Number Keys.", @"Warning explaining how to configure Spaces so new windows can open in a specific space.")
                               actions:@[ iTermLocalizedOK() ]
                            identifier:@"NeverWarnAboutSpaces"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                                window:self.view.window];
}


@end
