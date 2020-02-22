//
//  iTermRestorableStateController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermRestorableStateController;
@class NSCoding;
@class NSWindow;

@protocol iTermRestorableStateControllerDelegate<NSObject>

- (NSArray<NSWindow *> *)restorableStateControllerWindows:(iTermRestorableStateController *)restorableStateController;

- (void)restorableStateController:(iTermRestorableStateController *)restorableStateController
                 restoreWithCoder:(NSCoder *)coder
                       identifier:(NSString *)identifier
                       completion:(void (^)(NSWindow *, NSError *))completion;

- (BOOL)restorableStateController:(iTermRestorableStateController *)restorableStateController
           windowNeedsRestoration:(NSWindow *)window;

- (void)restorableStateController:(iTermRestorableStateController *)restorableStateController
                  encodeWithCoder:(NSCoder *)coder
                           window:(NSWindow *)window;

@end

@interface iTermRestorableStateController : NSObject
@property (nonatomic, weak) id<iTermRestorableStateControllerDelegate> delegate;

- (void)saveRestorableState;
- (void)restoreWindows;

@end

NS_ASSUME_NONNULL_END
