//
//  iTermSavePanel.m
//  iTerm2
//
//  Created by George Nachman on 7/9/15.
//
//

#import "iTermSavePanel.h"
#import "DebugLogging.h"
#import "iTermSavePanelFileFormatAccessory.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "NSFileManager+iTerm.h"

static NSString *const kInitialDirectoryKey = @"Initial Directory";

@interface iTermSavePanel () <NSOpenSavePanelDelegate>
@property(nonatomic, copy) NSString *filename;  // Just the filename.
@property(nonatomic, copy) NSString *path;  // Full path.
@property(nonatomic, assign) iTermSavePanelReplaceOrAppend replaceOrAppend;
@property(nonatomic, copy) NSString *requiredExtension;
@property(nonatomic, copy) NSString *forcedExtension;
@end

@implementation iTermSavePanel {
    NSInteger _options;
}

+ (NSString *)keyForIdentifier:(NSString *)identifier {
    return [NSString stringWithFormat:@"NoSyncSavePanelSavedSettings_%@", identifier];
}

+ (iTermSavePanel *)showWithOptions:(NSInteger)options
                         identifier:(NSString *)identifier
                   initialDirectory:(NSString *)initialDirectory
                    defaultFilename:(NSString *)defaultFilename {
    return [self showWithOptions:options
                      identifier:identifier
                initialDirectory:initialDirectory
                 defaultFilename:defaultFilename
                allowedFileTypes:nil];
}

+ (NSString *)nameForFileType:(NSString *)extension {
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                (__bridge CFStringRef)extension,
                                                                NULL);
    NSString *lowercaseDescription = (__bridge_transfer NSString *)UTTypeCopyDescription(fileUTI);

    CFRelease(fileUTI);

    lowercaseDescription = [lowercaseDescription stringByCapitalizingFirstLetter];
    NSRange range = [lowercaseDescription rangeOfString:[NSString stringWithFormat:@"(%@)", extension]];
    if (range.location == NSNotFound) {
        return lowercaseDescription;
    }
    return [lowercaseDescription stringByReplacingCharactersInRange:range withString:[extension uppercaseString]];
}

+ (iTermSavePanelFileFormatAccessory *)newFileFormatAccessoryViewControllerFileWithFileTypes:(NSArray<NSString *> *)fileTypes {
    iTermSavePanelFileFormatAccessory *accessory = [[iTermSavePanelFileFormatAccessory alloc] initWithNibName:@"iTermSavePanelFileFormatAccessory" bundle:[NSBundle bundleForClass:self]];
    [accessory view];
    NSInteger i = 0;
    for (NSString *fileType in fileTypes) {
        NSString *name = [self nameForFileType:fileType];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""];
        item.tag = i++;
        [accessory.popupButton.menu addItem:item];
    }
    return accessory;
}

+ (iTermSavePanel *)showWithOptions:(NSInteger)options
                         identifier:(NSString *)identifier
                   initialDirectory:(NSString *)initialDirectory
                    defaultFilename:(NSString *)defaultFilename
                   allowedFileTypes:(NSArray<NSString *> *)allowedFileTypes {
    NSString *key = [self keyForIdentifier:identifier];
    NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (savedSettings) {
        initialDirectory = savedSettings[kInitialDirectoryKey] ?: initialDirectory;
    }

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    if (initialDirectory) {
        savePanel.directoryURL = [NSURL fileURLWithPath:initialDirectory];
    }
    savePanel.nameFieldStringValue = defaultFilename;
    if (allowedFileTypes) {
        savePanel.extensionHidden = NO;
        savePanel.allowedFileTypes = allowedFileTypes;
    }
    iTermSavePanelFileFormatAccessory *accessoryViewController = nil;
    if (options & kSavePanelOptionFileFormatAccessory) {
        accessoryViewController = [self newFileFormatAccessoryViewControllerFileWithFileTypes:allowedFileTypes];
        savePanel.accessoryView = accessoryViewController.view;
    }
    iTermSavePanel *delegate = [[iTermSavePanel alloc] initWithOptions:options];
    accessoryViewController.onChange = ^(NSInteger i){
        [delegate setRequiredExtension:allowedFileTypes[i]];
    };
    if (options & kSavePanelOptionFileFormatAccessory) {
        delegate.requiredExtension = allowedFileTypes[0];
    }
    savePanel.delegate = delegate;
    BOOL retrying;
    do {
        NSInteger response = [savePanel runModal];

        if (response != NSModalResponseOK) {
            // User canceled.
            return nil;
        }

        NSURL *URL = savePanel.URL;
        if (delegate.forcedExtension) {
            URL = [[URL URLByDeletingPathExtension] URLByAppendingPathExtension:delegate.forcedExtension];
        }
        retrying = NO;
        if (options & kSavePanelOptionAppendOrReplace) {
            if (!delegate.filename) {
                // Something went wrong.
                DLog(@"Save panel's delegate has no filename!");
                return nil;
            }

            // The path contains random crap in the last path component. Use what we saved instead.
            NSString *directory = [URL.path stringByDeletingLastPathComponent];
            delegate.path = [directory stringByAppendingPathComponent:delegate.filename];
            if (allowedFileTypes.count && ![allowedFileTypes containsObject:delegate.path.pathExtension]) {
                delegate.path = [delegate.path stringByAppendingPathExtension:allowedFileTypes.firstObject];
            }

            // Show the replace/append/cancel panel.
            retrying = [delegate checkForExistingFile];
        } else {
            delegate.path = URL.path;
            if (allowedFileTypes.count && ![allowedFileTypes containsObject:delegate.path.pathExtension]) {
                delegate.path = [delegate.path stringByAppendingPathExtension:allowedFileTypes.firstObject];
            }
        }
    } while (retrying);

    if (delegate.path) {
        NSDictionary *settings =
            @{ kInitialDirectoryKey: [delegate.path stringByDeletingLastPathComponent] };
        [[NSUserDefaults standardUserDefaults] setObject:settings forKey:key];
    }

    return delegate.path ? delegate : nil;
}

- (instancetype)initWithOptions:(NSInteger)options {
    self = [super init];
    if (self) {
        _options = options;
    }
    return self;
}

#pragma mark - Private

// Returns YES if the save panel should be shown again because the user canceled.
- (BOOL)checkForExistingFile {
    BOOL retry = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:self.path]) {
        NSString *location = @"";
        NSString *directory = [self.path stringByDeletingLastPathComponent];
        if ([directory isEqualToString:NSHomeDirectory()]) {
            location = @" in your home directory";
        } else if ([directory isEqualToString:[fileManager desktopDirectory]]) {
            location = @" on the Desktop";
        }

        NSString *heading =
            [NSString stringWithFormat:@"“%@” already exists. Do you want to replace it or append to it?",
         [self.path lastPathComponent]];
        NSString *body = [NSString stringWithFormat:@"A file or folder with the same name already exists%@. "
                                                    @"Replacing it will overwrite its current contents.",
                          location];
        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:body
                                                                     actions:@[ @"Cancel", @"Replace", @"Append" ]
                                                                   accessory:nil
                                                                  identifier:nil
                                                                 silenceable:kiTermWarningTypePersistent
                                                                     heading:heading
                                                                      window:nil];
        switch (selection) {
            case kiTermWarningSelection0:
                self.replaceOrAppend = kSavePanelReplaceOrAppendSelectionNotApplicable;
                retry = YES;
                break;

            case kiTermWarningSelection1:
                self.replaceOrAppend = kSavePanelReplaceOrAppendSelectionReplace;
                break;

            case kiTermWarningSelection2:
                self.replaceOrAppend = kSavePanelReplaceOrAppendSelectionAppend;
                break;

            default:
                assert(false);
        }
    }
    return retry;
}

#pragma mark - NSOpenSavePanelDelegate

- (NSString *)panel:(id)sender userEnteredFilename:(NSString*)filename confirmed:(BOOL)okFlag {
    if (_options & kSavePanelOptionAppendOrReplace) {
        if (!okFlag) {
            // User is just typing.
            return filename;
        }
        // User pressed ok.

        // Save the file the user entered. He could've typed slashes, which the system would
        // turn into colons normally.
        self.filename = [filename stringByReplacingOccurrencesOfString:@"/" withString:@":"];

        // Return a filename that definitely doesn't exist to avoid the Replace panel.
        return [NSString uuid];
    } else {
        // Default behavior.
        return filename;
    }
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
    NSString *proposedExtension = url.pathExtension;
    self.forcedExtension = nil;
    if (!proposedExtension.length) {
        return YES;
    }
    if (!self.requiredExtension) {
        return YES;
    }
    if ([proposedExtension isEqualToString:self.requiredExtension]) {
        return YES;
    }
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"You can choose to use both, so that your file name ends in “.%@.%@”.", proposedExtension, _requiredExtension]
                                                                 actions:@[ [NSString stringWithFormat:@"Use .%@", _requiredExtension],
                                                                            @"Cancel",
                                                                            @"Use both" ]
                                                               accessory:nil
                                                              identifier:nil
                                                             silenceable:kiTermWarningTypePersistent
                                                                 heading:[NSString stringWithFormat:@"You cannot save this document with extension “.%@” at the end of the name. The required extension is “.%@”.",
                                                                          proposedExtension, _requiredExtension]
                                                                  window:nil];
    switch (selection) {
        case kiTermWarningSelection0:
            self.forcedExtension = self.requiredExtension;
            return YES;

        case kiTermWarningSelection1:
            return NO;

        case kiTermWarningSelection2:
            self.forcedExtension = [NSString stringWithFormat:@"%@.%@", proposedExtension, _requiredExtension];
            break;

        default:
            break;
    }
    return NO;
}

@end
