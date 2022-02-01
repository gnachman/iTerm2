//
//  iTermEchoProbe.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/1/18.
//

#import <Foundation/Foundation.h>
#import "CVector.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermEchoProbe;

@protocol iTermEchoProbeDelegate<NSObject>

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data;
- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string;

// Call -reset from this if you decide not to send the password anyway.
- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe;
- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe;
- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe;
- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe;

@end

@interface iTermEchoProbe : NSObject

@property (nonatomic, weak) id<iTermEchoProbeDelegate> delegate;
@property (nonatomic, readonly) BOOL isActive;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)beginProbeWithBackspace:(NSData *)backspaceData
                       password:(NSString *)password;
- (void)updateEchoProbeStateWithTokenCVector:(CVector *)vector;
- (void)enterPassword;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
