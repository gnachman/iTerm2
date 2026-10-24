//
//  Coprocess.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "iTermWeakReference.h"

@class Coprocess;
@class iTermOwnedFileDescriptor;

@protocol iTermCoprocessDelegate<NSObject>
- (void)coprocess:(Coprocess *)coprocess didTerminateWithErrorOutput:(NSString *)errors;
@end

@interface Coprocess : NSObject

@property(nonatomic, assign) pid_t pid;  // -1 after termination
// Own the pipes to and from the child. -terminate closes them, or deallocation does.
@property(nonatomic, readonly) iTermOwnedFileDescriptor *ownedWriteFileDescriptor;
@property(nonatomic, readonly) iTermOwnedFileDescriptor *ownedReadFileDescriptor;
@property(nonatomic, readonly) NSMutableData *outputBuffer;
@property(nonatomic, readonly) NSMutableData *inputBuffer;
@property(nonatomic, assign) BOOL eof;
@property(nonatomic, assign) BOOL mute;
@property(nonatomic, retain) id<iTermCoprocessDelegate, iTermWeakReference> delegate;
@property(nonatomic, readonly) NSString *command;

+ (Coprocess *)launchedCoprocessWithCommand:(NSString *)command
                                environment:(NSDictionary<NSString *, NSString *> *)environment;

// Wraps an already-running process. Makes outputFd and inputFd non-blocking and takes ownership
// of all three file descriptors.
+ (Coprocess *)coprocessWithPid:(pid_t)pid
                        command:(NSString *)command
                       outputFd:(int)outputFd
                        inputFd:(int)inputFd
                        errorFd:(int)errorFd;

+ (NSArray *)mostRecentlyUsedCommands;
+ (void)setSilentlyIgnoreErrors:(BOOL)shouldIgnore fromCommand:(NSString *)command;
+ (BOOL)shouldIgnoreErrorsFromCommand:(NSString *)command;

// Write from outputBuffer
- (int)write;

// Read to end of inputBuffer
- (int)read;
- (BOOL)wantToRead;
- (BOOL)wantToWrite;
- (void)mainProcessDidTerminate;
- (void)terminate;

// Calls `completion` on the main queue once the child's stderr has reached EOF, with everything
// it wrote there.
- (void)notifyWhenErrorOutputIsComplete:(void (^)(NSString *errors))completion;

// Testing only. The read end of the child's stderr, which the coprocess owns. It is closed once
// error output is complete, after which the number may be reused. Never use it for I/O.
@property(nonatomic, readonly) int errorFileDescriptorForTesting;

@end
