//
//  iTermRestorableStateDriver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermRestorableStateRecord<NSObject>
- (void)unlink;
- (NSKeyedUnarchiver *)unarchiver;
- (NSString *)identifier;
@end

@protocol iTermRestorableStateIndex<NSObject>

- (NSUInteger)restorableStateIndexNumberOfWindows;

- (void)restorableStateIndexUnlink;

- (id<iTermRestorableStateRecord>)restorableStateRecordAtIndex:(NSUInteger)i;

@end

@protocol iTermRestorableStateRestorer<NSObject>
- (id<iTermRestorableStateIndex>)restorableStateIndex;

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(void))completion;

@end

@interface iTermRestorableStateDriver : NSObject
@property (nonatomic, weak) id<iTermRestorableStateRestorer> restorer;
@property (nonatomic, readonly) BOOL restoring;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;

- (void)restoreWithCompletion:(void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
