//
//  Coprocess.h
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// input = write end of coprocess's stdin pipe
// output = read end of coprocess's stdout pipe
@interface Coprocess : NSObject {
    NSTask *task_;  // nil after terminate is called.
    NSPipe *inputPipe_;
    NSPipe *outputPipe_;
    NSMutableData *outputBuffer_;
    NSMutableData *inputBuffer_;
    BOOL eof_;
}

@property (nonatomic, retain) NSTask *task;
@property (nonatomic, retain) NSPipe *inputPipe;
@property (nonatomic, retain) NSPipe *outputPipe;
@property (nonatomic, readonly) NSMutableData *outputBuffer;
@property (nonatomic, readonly) NSMutableData *inputBuffer;
@property (nonatomic, assign) BOOL eof;

+ (Coprocess *)coprocessWithTask:(NSTask *)task
                       inputPipe:(NSPipe *)inputPipe
                      outputPipe:(NSPipe *)outputPipe;

// Write from outputBuffer
- (int)write;

// Read to end of inputBuffer
- (int)read;
- (int)readFileDescriptor;
- (int)writeFileDescriptor;
- (int)errorFileDescriptor;
- (BOOL)wantToRead;
- (BOOL)wantToWrite;
- (void)mainProcessDidTerminate;
- (void)terminate;
- (pid_t)pid;

@end
