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

- (void)echoProbeWriteData:(NSData *)data;
- (void)echoProbeWriteString:(NSString *)string;
- (void)echoProbeDidFail;

@end

@interface iTermEchoProbe : NSObject

@property (nonatomic, weak) id<iTermEchoProbeDelegate> delegate;

- (void)beginProbeWithBackspace:(NSData *)backspaceData
                       password:(NSString *)password;
- (void)updateEchoProbeStateWithTokenCVector:(CVector *)vector;
- (void)enterPassword;

@end

NS_ASSUME_NONNULL_END
