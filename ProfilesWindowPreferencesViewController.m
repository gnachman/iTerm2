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

@end
