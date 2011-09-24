//
//  Coprocess.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "Coprocess.h"

const int kMaxInputBufferSize = 1024;
const int kMaxOutputBufferSize = 1024;

@implementation Coprocess

@synthesize task = task_;
@synthesize inputPipe = inputPipe_;
@synthesize outputPipe = outputPipe_;
@synthesize inputBuffer = inputBuffer_;
@synthesize outputBuffer = outputBuffer_;
@synthesize eof = eof_;

+ (Coprocess *)coprocessWithTask:(NSTask *)task
                       inputPipe:(NSPipe *)inputPipe
                      outputPipe:(NSPipe *)outputPipe
{
    Coprocess *result = [[[Coprocess alloc] init] autorelease];
    result.task = task;
    result.inputPipe = inputPipe;
    result.outputPipe = outputPipe;
    return result;
}

- (id)init
{
    self = [super init];
    if (self) {
        inputBuffer_ = [[NSMutableData alloc] init];
        outputBuffer_ = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [task_ release];
    [inputPipe_ release];
    [outputPipe_ release];
    [inputBuffer_ release];
    [outputBuffer_ release];
    [super dealloc];
}

- (int)write
{
    if (!task_) {
        return -1;
    }
    int fd = [self writeFileDescriptor];
    int n = write(fd, [outputBuffer_ bytes], [outputBuffer_ length]);
    if (n < 0 && (!(errno == EAGAIN || errno == EINTR))) {
        eof_ = YES;
    } else if (n == 0) {
        eof_ = YES;
    } else if (n > 0) {
        [outputBuffer_ replaceBytesInRange:NSMakeRange(0, n)
                                 withBytes:""
                                    length:0];
    }
    return n;
}

- (int)read
{
    if (!task_) {
        return -1;
    }
    int rc = 0;
    int fd = [self readFileDescriptor];
    while (inputBuffer_.length < kMaxInputBufferSize) {
        char buffer[1024];
        int n = read(fd, buffer, sizeof(buffer));
        if (n == 0) {
            rc = 0;
            eof_ = YES;
            break;
        } else if (n < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                eof_ = YES;
                rc = n;
                break;
            }
        } else {
            rc += n;
            [inputBuffer_ appendBytes:buffer length:n];
        }
        if (n < sizeof(buffer)) {
            break;
        }
    }
    return rc;
}

- (int)readFileDescriptor
{
    if (!task_) {
        return -1;
    }
    return [[outputPipe_ fileHandleForReading] fileDescriptor];
}

- (int)writeFileDescriptor
{
    if (!task_) {
        return -1;
    }
    return [[self.inputPipe fileHandleForWriting] fileDescriptor];
}

- (int)errorFileDescriptor
{
    return [self writeFileDescriptor];
}

- (BOOL)wantToRead
{
    return task_ && !eof_ && (inputBuffer_.length < kMaxInputBufferSize);
}

- (BOOL)wantToWrite
{
    return task_ && !eof_ && (outputBuffer_.length > 0);
}

- (void)mainProcessDidTerminate
{
    [self terminate];
}

- (void)terminate
{
    if (task_) {
        kill([task_ processIdentifier], 1);
        [task_ release];
        task_ = nil;
        eof_ = YES;
    }
}

- (pid_t)pid
{
    return [task_ processIdentifier];
}

@end
