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

@protocol iTermCoprocessDelegate<NSObject>
- (void)coprocess:(Coprocess *)coprocess didTerminateWithErrorOutput:(NSString *)errors;
@end

@interface Coprocess : NSObject

@property(nonatomic, assign) pid_t pid;  // -1 after termination
@property(nonatomic, assign) int outputFd;  // for writing
@property(nonatomic, assign) int inputFd;  // for reading
@property(nonatomic, readonly) NSMutableData *outputBuffer;
@property(nonatomic, readonly) NSMutableData *inputBuffer;
@property(nonatomic, assign) BOOL eof;
@property(nonatomic, assign) BOOL mute;
@property(nonatomic, readonly) int readFileDescriptor;  // for reading
@property(nonatomic, readonly) int writeFileDescriptor;  // for writing
@property(nonatomic, retain) id<iTermCoprocessDelegate, iTermWeakReference> delegate;
@property(nonatomic, readonly) NSString *command;

+ (Coprocess *)launchedCoprocessWithCommand:(NSString *)command;

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

@end
