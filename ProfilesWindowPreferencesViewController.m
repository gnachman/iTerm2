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
#import "iTermWarning.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

@interface ProfilesWindowPreferencesViewController ()

@property(nonatomic, copy) NSString *backgroundImageFilename;

@end

@implementation ProfilesWindowPreferencesViewController {
    IBOutlet NSSlider *_transparency;
    IBOutlet NSButton *_useBlur;
    IBOutlet NSSlider *_blurRadius;
    IBOutlet NSButton *_useBackgroundImage;
    IBOutlet NSImageView *_backgroundImagePreview;
    IBOutlet NSButton *_backgroundImageTiled;
    IBOutlet NSSlider *_blendAmount;
    IBOutlet NSTextField *_columnsField;
    IBOutlet NSTextField *_rowsField;
    IBOutlet NSButton *_hideAfterOpening;
    IBOutlet NSPopUpButton *_windowStyle;
    IBOutlet NSPopUpButton *_screen;
    IBOutlet NSTextField *_screenLabel;
    IBOutlet NSPopUpButton *_space;
    IBOutlet NSTextField *_columnsLabel;
    IBOutlet NSTextField *_rowsLabel;
    IBOutlet NSTextField *_windowStyleLabel;
    IBOutlet NSTextField *_spaceLabel;
    IBOutlet NSButton *_syncTitle;
    IBOutlet NSButton *_disableWindowResizing;
    IBOutlet NSButton *_preventTab;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_backgroundImageFilename release];
    [super dealloc];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfile)  // In superclass
                                                 name:kReloadAllProfiles
                                               object:nil];

    PreferenceInfo *info;
    [self defineControl:_transparency
                    key:KEY_TRANSPARENCY
                   type:kPreferenceInfoTypeSlider];
    
    info = [self defineControl:_useBlur
                           key:KEY_BLUR
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { _blurRadius.enabled = (_useBlur.state == NSOnState); };
    
    [self defineControl:_blurRadius
                    key:KEY_BLUR_RADIUS
                   type:kPreferenceInfoTypeSlider];
    
    [self defineControl:_backgroundImageTiled
                    key:KEY_BACKGROUND_IMAGE_TILED
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_blendAmount
                    key:KEY_BLEND
                   type:kPreferenceInfoTypeSlider];
    
    info = [self defineControl:_columnsField
                           key:KEY_COLUMNS
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100000);  // An arbitrary but hopefully reasonable limit.

    info = [self defineControl:_rowsField
                           key:KEY_ROWS
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(1, 100000);  // An arbitrary but hopefully reasonable limit.
    
    [self defineControl:_hideAfterOpening
                    key:KEY_HIDE_AFTER_OPENING
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_windowStyle
                    key:KEY_WINDOW_TYPE
                   type:kPreferenceInfoTypePopup];
    
    [self defineControl:_screen
                    key:KEY_SCREEN
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self screenDidChange]; }
                 update:^BOOL{ [self updateScreen]; return YES; }];
    
    info = [self defineControl:_space
                           key:KEY_SPACE
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        if ([_space selectedTag] > 0) {
            [self maybeWarnAboutSpaces];
        }
    };
    
    [self defineControl:_syncTitle
                    key:KEY_SYNC_TITLE
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_disableWindowResizing
                    key:KEY_DISABLE_WINDOW_RESIZING
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_preventTab
                    key:KEY_PREVENT_TAB
                   type:kPreferenceInfoTypeCheckbox];
}

- (void)layoutSubviewsForSingleBookmarkMode {
    NSArray *viewsToDisable = @[ _columnsField,
                                 _rowsField,
                                 _hideAfterOpening,
                                 _windowStyle,
                                 _screen,
                                 _space ];
    for (id view in viewsToDisable) {
        [view setEnabled:NO];
    }
    
    NSArray *labelsToDisable = @[ _screenLabel,
                                  _columnsLabel,
                                  _rowsLabel,
                                  _spaceLabel,
                                  _windowStyleLabel ];
    for (NSTextField *field in labelsToDisable) {
        [field setLabelEnabled:NO];
    }
}

- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict {
    NSString *value = [self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION];;
    if (value) {
        dict[KEY_BACKGROUND_IMAGE_LOCATION] = value;
    } else {
        [dict removeObjectForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    }
}

- (void)reloadProfile {
    [super reloadProfile];
    [self loadBackgroundImageWithFilename:[self stringForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
}

#pragma mark - Actions

// Opens a file picker and updates views and state.
- (IBAction)useBackgroundImageDidChange:(id)sender {
    NSOpenPanel *panel;
    int sts;
    NSString *filename = nil;
    
    if ([_useBackgroundImage state] == NSOnState) {
        panel = [NSOpenPanel openPanel];
        [panel setAllowsMultipleSelection:NO];
        
        sts = [panel legacyRunModalForDirectory:NSHomeDirectory()
                                           file:@""
                                          types:[NSImage imageFileTypes]];
        if (sts == NSOKButton && [[panel legacyFilenames] count] > 0) {
            filename = [[panel legacyFilenames] objectAtIndex:0];
        }
    }
    [self loadBackgroundImageWithFilename:filename];
    [self setString:self.backgroundImageFilename forKey:KEY_BACKGROUND_IMAGE_LOCATION];
}

#pragma mark - Background Image

// Sets _backgroundImagePreview and _useBackgroundImage.
- (void)loadBackgroundImageWithFilename:(NSString *)filename {
    NSImage *anImage = filename.length > 0 ? [[NSImage alloc] initWithContentsOfFile:filename] : nil;
    if (anImage) {
        [_backgroundImagePreview setImage:[anImage autorelease]];
        [_useBackgroundImage setState:NSOnState];
        self.backgroundImageFilename = filename;
    } else {
        [_backgroundImagePreview setImage:nil];
        [_useBackgroundImage setState:NSOffState];
        self.backgroundImageFilename = nil;
    }
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
    const int numScreens = [[NSScreen screens] count];
    for (i = 0; i < numScreens; i++) {
        if (i == 0) {
            [_screen addItemWithTitle:[NSString stringWithFormat:@"Main Screen"]];
        } else {
            [_screen addItemWithTitle:[NSString stringWithFormat:@"Screen %d", i+1]];
        }
        [[_screen lastItem] setTag:i];
    }
    if (selectedTag >= 0 && selectedTag < i) {
        [_screen selectItemWithTag:selectedTag];
    } else {
        [_screen selectItemWithTag:-1];
    }
    if ([_windowStyle selectedTag] == WINDOW_TYPE_NORMAL) {
        [_screen setEnabled:NO];
        [_screenLabel setEnabled:NO];
        [_screen selectItemWithTag:-1];
    } else if ([self.delegate profilePreferencesCurrentModel] == [ProfileModel sharedInstance]) {
        [_screen setEnabled:YES];
        [_screenLabel setEnabled:YES];
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
                           silenceable:kiTermWarningTypePermanentlySilenceable];
}


@end
