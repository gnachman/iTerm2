//
//  ContextMenuActionPrefsController.h
//  iTerm
//
//  Created by George Nachman on 11/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

@class VT100RemoteHost;

typedef NS_ENUM(NSInteger, ContextMenuActions) {
    kOpenFileContextMenuAction,
    kOpenUrlContextMenuAction,
    kRunCommandContextMenuAction,
    kRunCoprocessContextMenuAction,
    kSendTextContextMenuAction,
    kRunCommandInWindowContextMenuAction,
};

@protocol ContextMenuActionPrefsDelegate <NSObject>

- (void)contextMenuActionsChanged:(NSArray *)newActions;

@end


@interface ContextMenuActionPrefsController : NSWindowController <
    NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, assign) id<ContextMenuActionPrefsDelegate> delegate;
@property (nonatomic, assign) BOOL hasSelection;

+ (ContextMenuActions)actionForActionDict:(NSDictionary *)dict;

+ (NSString *)titleForActionDict:(NSDictionary *)dict
           withCaptureComponents:(NSArray *)components
                workingDirectory:(NSString *)workingDirectory
                      remoteHost:(VT100RemoteHost *)remoteHost;

+ (NSString *)parameterForActionDict:(NSDictionary *)dict
               withCaptureComponents:(NSArray *)components
                    workingDirectory:(NSString *)workingDirectory
                          remoteHost:(VT100RemoteHost *)remoteHost;

- (IBAction)ok:(id)sender;
- (void)setActions:(NSArray *)newActions;
- (IBAction)add:(id)sender;
- (IBAction)remove:(id)sender;

@end
