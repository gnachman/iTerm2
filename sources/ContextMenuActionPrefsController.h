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
@protocol iTermObject;
@class iTermVariableScope;

typedef NS_ENUM(NSInteger, ContextMenuActions) {
    kOpenFileContextMenuAction,
    kOpenUrlContextMenuAction,
    kRunCommandContextMenuAction,
    kRunCoprocessContextMenuAction,
    kSendTextContextMenuAction,
    kRunCommandInWindowContextMenuAction,
};

@protocol ContextMenuActionPrefsDelegate <NSObject>

- (void)contextMenuActionsChanged:(NSArray *)newActions
           useInterpolatedStrings:(BOOL)useInterpolatedStrings;

@end


@interface ContextMenuActionPrefsController : NSWindowController <
    NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id<ContextMenuActionPrefsDelegate> delegate;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) BOOL useInterpolatedStrings;

+ (ContextMenuActions)actionForActionDict:(NSDictionary *)dict;

+ (NSString *)titleForActionDict:(NSDictionary *)dict
           withCaptureComponents:(NSArray *)components
                workingDirectory:(NSString *)workingDirectory
                      remoteHost:(VT100RemoteHost *)remoteHost;

// Use this as the keys into the dictionary that get passed to the `dict` parameter of
// computeParameterForActionDict:….
extern NSString *iTermSmartSelectionActionContextKeyAction;
extern NSString *iTermSmartSelectionActionContextKeyComponents;
extern NSString *iTermSmartSelectionActionContextKeyWorkingDirectory;
extern NSString *iTermSmartSelectionActionContextKeyRemoteHost;

+ (void)computeParameterForActionDict:(NSDictionary *)dict
                withCaptureComponents:(NSArray *)components
                     useInterpolation:(BOOL)useInterpolation
                                scope:(iTermVariableScope *)scope
                                owner:(id<iTermObject>)owner
                           completion:(void (^)(NSString *parameter))completion;

- (IBAction)ok:(id)sender;
- (void)setActions:(NSArray *)newActions;
- (IBAction)add:(id)sender;
- (IBAction)remove:(id)sender;

@end
