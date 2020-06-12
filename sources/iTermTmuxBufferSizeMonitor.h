//
//  iTermTmuxBufferSizeMonitor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/6/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;

@class iTermTmuxBufferSizeMonitor;
@protocol iTermTmuxBufferSizeMonitorDelegate<NSObject>
- (void)tmuxBufferSizeMonitor:(iTermTmuxBufferSizeMonitor *)sender
                   updatePane:(int)wp
                          ttl:(NSTimeInterval)ttl
                      redzone:(BOOL)redzone;
@end

@interface iTermTmuxBufferSizeMonitor : NSObject
@property (nonatomic, weak) id<iTermTmuxBufferSizeMonitorDelegate> delegate;
@property (nonatomic, strong, readonly) TmuxController *controller;
@property (nonatomic, readonly) NSTimeInterval pauseAge;

- (instancetype)initWithController:(TmuxController *)controller
                          pauseAge:(NSTimeInterval)pauseAge NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setCurrentLatency:(NSTimeInterval)latency forPane:(int)wp;
- (void)resetPane:(int)wp;

@end

NS_ASSUME_NONNULL_END
