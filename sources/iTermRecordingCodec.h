//
//  iTermRecordingCodec.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/8/18.
//

#import <Cocoa/Cocoa.h>

@class PTYSession;

@interface iTermRecordingCodec : NSObject

+ (void)loadRecording;
+ (void)loadRecording:(NSURL *)url;
+ (void)exportRecording:(PTYSession *)session;

@end
