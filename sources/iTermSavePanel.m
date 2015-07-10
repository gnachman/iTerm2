//
//  iTermSavePanel.m
//  iTerm2
//
//  Created by George Nachman on 7/9/15.
//
//

#import "iTermSavePanel.h"
#import "DebugLogging.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "NSFileManager+iTerm.h"

static NSString *const kInitialDirectoryKey = @"Initial Directory";

@interface iTermSavePanel () <NSOpenSavePanelDelegate>
@property(nonatomic, copy) NSString *filename;  // Just the filename.
@property(nonatomic, copy) NSString *path;  // Full path.
@property(nonatomic, assign) iTermSavePanelReplaceorAppend replaceOrAppend;
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
    iTermSavePanel *delegate = [[[iTermSavePanel alloc] initWithOptions:options] autorelease];

    savePanel.delegate = delegate;
    BOOL retrying;
    do {
        NSInteger response = [savePanel runModal];

        if (response != NSOKButton) {
            // User canceled.
            return nil;
        }

        retrying = NO;
        if (options & kSavePanelOptionAppendOrReplace) {
            if (!delegate.filename) {
                // Something went wrong.
                DLog(@"Save panel's delegate has no filename!");
                return nil;
            }

            // The path contains random crap in the last path component. Use what we saved instead.
            NSString *directory = [savePanel.URL.path stringByDeletingLastPathComponent];
            delegate.path = [directory stringByAppendingPathComponent:delegate.filename];

            // Show the replace/append/cancel panel.
            retrying = [delegate checkForExistingFile];
        } else {
            delegate.path = savePanel.URL.path;
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

- (void)dealloc {
    [_filename release];
    [_path release];
    [super dealloc];
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
                                                                     heading:heading];
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

@end
