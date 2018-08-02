//
//  iTermEchoProbe.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/1/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermEchoProbeState) {
    iTermEchoProbeOff = 0,
    iTermEchoProbeWaiting = 1,
    iTermEchoProbeOneAsterisk = 2,
    iTermEchoProbeBackspaceOverAsterisk = 3,
    iTermEchoProbeSpaceOverAsterisk = 4,
    iTermEchoProbeBackspaceOverSpace = 5,
    iTermEchoProbeFailed = 6,
};

@class iTermEchoProbe;

@protocol iTermEchoProbeDelegate<NSObject>

- (void)echoProbeWriteData:(NSData *)data;
- (void)echoProbeWriteString:(NSString *)string;
- (void)echoProbeDidFail;

@end

@interface iTermEchoProbe : NSObject

@property (nonatomic, readonly) iTermEchoProbeState state;
@property (nonatomic, weak) id<iTermEchoProbeDelegate> delegate;

- (void)beginProbeWithBackspace:(NSData *)backspaceData
                       password:(NSString *)password;
- (void)updateEchoProbeStateWithBuffer:(char *)buffer length:(int)length;
- (void)enterPassword;

@end

NS_ASSUME_NONNULL_END
