//
//  iTermRestorableStateController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import <Foundation/Foundation.h>
#import "iTermRestorableStateRestorer.h"
#import "iTermRestorableStateSaver.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermRestorableStateController;
@class NSCoding;
@class NSWindow;

@protocol iTermRestorableStateControllerDelegate<iTermRestorableStateSaving, iTermRestorableStateRestoring>
@end

@interface iTermRestorableStateController : NSObject
@property (nonatomic, weak) id<iTermRestorableStateControllerDelegate> delegate;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;

- (void)saveRestorableState;
- (void)restoreWindows;

@end

NS_ASSUME_NONNULL_END
