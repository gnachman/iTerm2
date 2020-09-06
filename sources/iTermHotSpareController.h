//
//  iTermHotSpareController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/5/20.
//

#import <Foundation/Foundation.h>

#import "iTermClientServerProtocolMessageBox.h"
#import "iTermMultiServerProtocol.h"
#import "PTYTask.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermHotSpareController;

@protocol iTermHotSpareControllerDelegate<NSObject>
- (void)hotSpareControllerCreateHotSpare:(iTermHotSpareController *)sender
                                  report:(iTermClientServerProtocolMessageBox *)boxedReport
                              completion:(void (^)(void))completion;
@end

@interface iTermHotSpareController : NSObject
@property (nonatomic, weak) id<iTermHotSpareControllerDelegate> delegate;
@property (nonatomic, readonly) dispatch_queue_t queue;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)didLaunchRegularChildWithReport:(iTermMultiServerReportChild)report;

- (void)addHotSpareWithChildReport:(iTermMultiServerReportChild)report;

- (BOOL)requestHotSpareForLaunchRequest:(const iTermMultiServerRequestLaunch *)launchRequest
                                handler:(void (^ NS_NOESCAPE)(iTermMultiServerReportChild report))handler;

@end

NS_ASSUME_NONNULL_END
