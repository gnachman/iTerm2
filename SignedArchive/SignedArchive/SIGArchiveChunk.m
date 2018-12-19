//
//  SIGArchiveChunk.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveChunk.h"

#import "SIGError.h"

static const NSInteger SIGArchiveChunkOverhead = sizeof(long long) * 2;
NSString *const SIGArchiveHeaderMagicString = @"signed-archive";

@implementation SIGArchiveChunk {
    NSData *_data;
}

+ (instancetype)chunkFromFileHandle:(NSFileHandle *)fileHandle
                           atOffset:(long long)offset
                              error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        [fileHandle seekToFileOffset:offset];
    } @catch (NSException *exception) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIORead detail:exception.reason];
        }
        return nil;
    }
    
    SIGArchiveTag tag;
    if (![self readIntegerFromFileHandle:fileHandle fromOffset:offset value:(long long *)&tag error:error]) {
        return nil;
    }

    long long length;
    if (![self readIntegerFromFileHandle:fileHandle fromOffset:offset + sizeof(long long) value:(long long *)&length error:error]) {
        return nil;
    }
    
    SIGArchiveChunk *chunk = [[SIGArchiveChunk alloc] initWithTag:tag
                                                           length:length
                                                           offset:offset + SIGArchiveChunkOverhead];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeUnknown
                                      detail:@"Failed to create chunk object"];
        }
        return nil;
    }
    
    chunk->_fileHandle = fileHandle;

    return chunk;
}

+ (NSData *)readDataFromFileHandle:(NSFileHandle *)fileHandle
                    expectedLength:(long long)expectedLength
                             error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    NSError *readError = nil;
    NSData *data = nil;
    @try {
        data = [fileHandle readDataOfLength:expectedLength];
    } @catch (NSException *exception) {
        readError = [SIGError errorWithCode:SIGErrorCodeIORead
                                     detail:[exception reason]];
    }
    if (!readError && data.length != expectedLength) {
        readError = [SIGError errorWithCode:SIGErrorCodeIORead
                                     detail:@"Short read"];
    }
    if (!data && !readError) {
        readError = [SIGError errorWithCode:SIGErrorCodeIORead
                                     detail:@"Uncaught read failure"];
    }
    if (error) {
        *error = readError;
    }
    if (readError) {
        return nil;
    }
    return data;
}

+ (NSData *)readDataFromFileHandle:(NSFileHandle *)fileHandle
                        fromOffset:(NSInteger)offset
                    expectedLength:(long long)expectedLength
                             error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        [fileHandle seekToFileOffset:offset];
    } @catch (NSException *exception) {
        NSError *readError = [SIGError errorWithCode:SIGErrorCodeIORead
                                              detail:[exception reason]];
        if (error) {
            *error = readError;
        }
        return nil;
    }

    return [self readDataFromFileHandle:fileHandle
                         expectedLength:expectedLength
                                  error:error];
}

+ (BOOL)readIntegerFromFileHandle:(NSFileHandle *)fileHandle
                       fromOffset:(NSInteger)offset
                            value:(out long long *)valuePointer
                            error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    NSData *data = [self readDataFromFileHandle:fileHandle
                                     fromOffset:offset
                                 expectedLength:sizeof(long long)
                                          error:error];
    if (data) {
        long long networkOrder;
        assert(data.length == sizeof(networkOrder));
        memmove(&networkOrder, data.bytes, data.length);
        *valuePointer = ntohll(networkOrder);
        return YES;
    }

    return NO;
}

- (instancetype)initWithTag:(SIGArchiveTag)tag
                     length:(long long)length
                     offset:(long long)offset {
    self = [super init];
    if (self) {
        _tag = tag;
        _payloadLength = length;
        _payloadOffset = offset;
    }
    return self;
}

- (long long)chunkLength {
    return self.payloadLength + SIGArchiveChunkOverhead;
}

- (NSData *)data:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    if (_data) {
        return _data;
    }

    NSError *readError = nil;
    _data = [SIGArchiveChunk readDataFromFileHandle:_fileHandle
                                         fromOffset:self.payloadOffset
                                     expectedLength:self.payloadLength
                                              error:&readError];
    if (readError) {
        if (error) {
            *error = readError;
        }
        _data = nil;
        _fileHandle = nil;
        return nil;
    }
    
    return _data;
}

#pragma mark - Reading

@end

@implementation SIGArchiveChunkWriter

- (BOOL)writeData:(NSData *)data
         toStream:(NSOutputStream *)stream
            error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    if (![self writeInteger:self.tag toStream:stream error:error]) {
        return NO;
    }
    if (data.length != self.payloadLength) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeConsistency
                                      detail:@"File changed during signing"];
        }
        return NO;
    }
    if (![self writeInteger:data.length toStream:stream error:error]) {
        return NO;
    }
    const long long length = [stream write:data.bytes
                                 maxLength:data.length];
    if (length != data.length) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite
                                      detail:@"Short write"];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)writeStream:(NSInputStream *)readStream
           toStream:(NSOutputStream *)writeStream
              error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    if (![self writeInteger:self.tag toStream:writeStream error:error]) {
        return NO;
    }
    if (![self writeInteger:self.payloadLength toStream:writeStream error:error]) {
        return NO;
    }
    NSInteger totalNumberOfBytes = 0;
    while (readStream.hasBytesAvailable) {
        uint8_t buffer[4096];
        const NSInteger numberOfBytesRead = [readStream read:buffer
                                                   maxLength:sizeof(buffer)];
        if (numberOfBytesRead == 0) {
            break;
        }
        if (numberOfBytesRead < 0) {
            if (error) {
                *error = [SIGError errorWrapping:readStream.streamError
                                          code:SIGErrorCodeIORead
                                          detail:@"Error reading file"];
            }
            return NO;
        }
        totalNumberOfBytes += numberOfBytesRead;
        if (totalNumberOfBytes > self.payloadLength) {
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeConsistency
                                          detail:@"File changed while reading"];
            }
            return NO;
        }
        NSInteger numberOfBytesWritten = [writeStream write:buffer maxLength:numberOfBytesRead];
        if (numberOfBytesWritten < numberOfBytesRead) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite
                                      detail:@"Short write"];
            return NO;
        }
    }
    return totalNumberOfBytes == self.payloadLength;
}

#pragma mark - Private

- (BOOL)writeInteger:(long long)integer
            toStream:(NSOutputStream *)stream
               error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    const long long networkOrder = htonll(integer);
    uint8_t buffer[sizeof(networkOrder)];
    memmove(&buffer, (void *)&networkOrder, sizeof(networkOrder));
    const NSInteger length = [stream write:buffer
                                 maxLength:sizeof(buffer)];
    if (error) {
        if (length < 0) {
            *error = [SIGError errorWrapping:stream.streamError
                                      code:SIGErrorCodeIOWrite
                                      detail:@"Error writing to file"];
        } else if (length != sizeof(buffer)) {
            *error = [SIGError errorWithCode:SIGErrorCodeIOWrite
                                      detail:@"Short write"];
        }
    }
    return length == sizeof(buffer);
}

@end
