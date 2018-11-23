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
- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe;
- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe;
- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe;
- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe;

@end

@interface iTermEchoProbe : NSObject

@property (nonatomic, weak) id<iTermEchoProbeDelegate> delegate;

- (void)beginProbeWithBackspace:(NSData *)backspaceData
                       password:(NSString *)password;
- (void)updateEchoProbeStateWithTokenCVector:(CVector *)vector;
- (void)enterPassword;

@end

NS_ASSUME_NONNULL_END
