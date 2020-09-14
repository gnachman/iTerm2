//
//  iTermUntitledWindowStateMachine.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/24/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermUntitledWindowStateMachine;

@protocol iTermUntitledWindowStateMachineDelegate<NSObject>
- (void)untitledWindowStateMachineCreateNewWindow:(iTermUntitledWindowStateMachine *)sender;
@end

@interface iTermUntitledWindowStateMachine : NSObject
@property (nonatomic, weak) id<iTermUntitledWindowStateMachineDelegate> delegate;

- (void)maybeOpenUntitledFile;
- (void)didRestoreSomeWindows;
- (void)didFinishRestoringWindows;
- (void)didFinishInitialization;
- (void)disableInitialUntitledWindow;

@end

NS_ASSUME_NONNULL_END
