//
//  iTermRestorableStateSQLite.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

#import "iTermEncoderAdapter.h"
#import "iTermGraphEncoder.h"
#import "iTermRestorableStateRestorer.h"
#import "iTermRestorableStateSaver.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermRestorableStateSQLite : NSObject<iTermRestorableStateRestorer, iTermRestorableStateSaver>

@property (nonatomic, weak) id<iTermRestorableStateRestoring, iTermRestorableStateSaving> delegate;
@property (nonatomic) BOOL needsSave;

- (instancetype)initWithURL:(NSURL *)url
                      erase:(BOOL)erase NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
