//
//  iTermSavePanel.h
//  iTerm2
//
//  Created by George Nachman on 7/9/15.
//
//

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"

typedef NS_OPTIONS(NSInteger, iTermSavePanelOptions) {
    // If the file exists, ask the user if he'd like to append to it or replace it.
    // If this option is not set, the user will only be asked about replacing.
    kSavePanelOptionAppendOrReplace = (1 << 0),
    kSavePanelOptionFileFormatAccessory = (1 << 1),
    kSavePanelOptionLogPlainTextAccessory = (1 << 2),
    kSavePanelOptionIncludeTimestampsAccessory= (1 << 3)
};

typedef NS_ENUM(NSInteger, iTermSavePanelReplaceOrAppend) {
    kSavePanelReplaceOrAppendSelectionNotApplicable,  // No existing file or option not specified.
    kSavePanelReplaceOrAppendSelectionReplace,
    kSavePanelReplaceOrAppendSelectionAppend,
};

@interface iTermSavePanel : NSObject

// valid only if options includes kSavePanelOptionAppendOrReplace
@property(nonatomic, readonly) iTermSavePanelReplaceOrAppend replaceOrAppend;

// Path the user selected.
@property(nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) iTermLoggingStyle loggingStyle;
@property(nonatomic, readonly) BOOL timestamps;

+ (void)asyncShowWithOptions:(NSInteger)options
                  identifier:(NSString *)identifier
            initialDirectory:(NSString *)initialDirectory
             defaultFilename:(NSString *)defaultFilename
            allowedFileTypes:(NSArray<NSString *> *)allowedFileTypes
                      window:(NSWindow *)window
                  completion:(void (^)(iTermSavePanel *panel))completion;

@end
