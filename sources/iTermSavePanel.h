//
//  iTermSavePanel.h
//  iTerm2
//
//  Created by George Nachman on 7/9/15.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_OPTIONS(NSInteger, iTermSavePanelOptions) {
    // If the file exists, ask the user if he'd like to append to it or replace it.
    // If this option is not set, the user will only be asked about replacing.
    kSavePanelOptionAppendOrReplace = (1 << 0)
};

typedef NS_ENUM(NSInteger, iTermSavePanelReplaceorAppend) {
    kSavePanelReplaceOrAppendSelectionNotApplicable,  // No existing file or option not specified.
    kSavePanelReplaceOrAppendSelectionReplace,
    kSavePanelReplaceOrAppendSelectionAppend,
};

@interface iTermSavePanel : NSObject

// valid only if options includes kSavePanelOptionAppendOrReplace
@property(nonatomic, readonly) iTermSavePanelReplaceorAppend replaceOrAppend;

// Path the user selected.
@property(nonatomic, readonly) NSString *path;

// Prompts the user and returns a new iTermSavePanel.
+ (iTermSavePanel *)showWithOptions:(NSInteger)options
                         identifier:(NSString *)identifier
                   initialDirectory:(NSString *)initialDirectory
                    defaultFilename:(NSString *)defaultFilename;

@end
