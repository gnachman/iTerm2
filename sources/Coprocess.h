//
//  Coprocess.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface Coprocess : NSObject {
    pid_t pid_;  // -1 after termination
    int outputFd_;
    int inputFd_;
    NSMutableData *outputBuffer_;
    NSMutableData *inputBuffer_;
    BOOL eof_;
    BOOL mute_;
}

@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) int outputFd;  // for writing
@property (nonatomic, assign) int inputFd;  // for reading
@property (nonatomic, readonly) NSMutableData *outputBuffer;
@property (nonatomic, readonly) NSMutableData *inputBuffer;
@property (nonatomic, assign) BOOL eof;
@property (nonatomic, assign) BOOL mute;

+ (Coprocess *)launchedCoprocessWithCommand:(NSString *)command;

// This has the side-effect of making the file descriptors non-blocking so
// it should only be called after exec.
+ (Coprocess *)coprocessWithPid:(pid_t)pid
                        outputFd:(int)outputFd
						 inputFd:(int)inputFd;
+ (NSArray *)mostRecentlyUsedCommands;

// Write from outputBuffer
- (int)write;

// Read to end of inputBuffer
- (int)read;
- (BOOL)wantToRead;
- (BOOL)wantToWrite;
- (void)mainProcessDidTerminate;
- (void)terminate;
@property (readonly) int readFileDescriptor;  // for reading
@property (readonly) int writeFileDescriptor;  // for writing

@end
