//
//  iTermPresentationController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermPresentationController;

extern NSNotificationName const iTermScreenParametersDidChangeNontrivally;

@protocol iTermPresentationControllerManagedWindowController<NSObject>
- (BOOL)presentationControllerManagedWindowControllerIsFullScreen:(out BOOL *)lionFullScreen;
- (NSWindow *)presentationControllerManagedWindowControllerWindow;
@end

@protocol iTermPresentationControllerDelegate<NSObject>
- (NSArray<id<iTermPresentationControllerManagedWindowController>> *)presentationControllerManagedWindows;
@end

@interface iTermPresentationController : NSObject
@property (nonatomic, weak) id<iTermPresentationControllerDelegate> delegate;

+ (instancetype)sharedInstance;

// Show or hide the dock and menu bar by checking the state of the app and all managed windows
// and determining what the state ought to be, and then updating the application presentation
// options.
- (void)update;

// This is exposed simply to work around macOS bugs.
- (void)forceShowMenuBarAndDock;
@end

NS_ASSUME_NONNULL_END
