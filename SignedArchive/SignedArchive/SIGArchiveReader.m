//
//  SIGArchiveReader.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGArchiveReader.h"

#import "SIGArchiveBuilder.h"
#import "SIGArchiveChunk.h"
#import "SIGError.h"
#import "SIGPartialInputStream.h"

@implementation SIGArchiveReader {
    NSArray<SIGArchiveChunk *> *_chunks;
    BOOL _loaded;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        if (!url) {
            return nil;
        }
        _url = url;
    }
    return self;
}

- (NSString *)header:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagHeader];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoHeader];
        }
        return nil;
    }

    if (chunk != _chunks.firstObject) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
        return nil;
    }

    NSData *data = [chunk data:error];
    if (!data) {
        return nil;
    }

    NSString *string = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    if (!string) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedHeader];
        }
        return nil;
    }
    
    return string;
}

- (NSString *)metadata:(out NSError **)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagMetadata];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoMetadata];
        }
        return nil;
    }
    NSData *data = [chunk data:error];
    if (!data) {
        return nil;
    }
    NSString *string = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    if (!string) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
        }
        return nil;
    }
    
    return string;
}

- (NSData *)signature:(out NSError * _Nullable __autoreleasing *)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagSignature];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoSignature];
        }
        return nil;
    }
    return [chunk data:error];
}

- (NSArray<NSData *> *)signingCertificates:(out NSError * _Nullable __autoreleasing *)error {
    NSArray<SIGArchiveChunk *> *chunks = [self chunksWithTag:SIGArchiveTagCertificate];
    if (!chunks.count) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoCertificate];
        }
        return nil;
    }
    NSMutableArray<NSData *> *datas = [NSMutableArray array];
    for (SIGArchiveChunk *chunk in chunks) {
        NSData *data = [chunk data:error];
        if (!data) {
            return nil;
        }
        [datas addObject:data];
    }
    return datas;
}

- (NSInputStream *)payloadInputStream:(out NSError **)error {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagPayload];
    if (!chunk) {
        if (error) {
            *error = [SIGError errorWithCode:SIGErrorCodeNoPayload];
        }
        return nil;
    }
    return [[SIGPartialInputStream alloc] initWithURL:_url
                                                range:NSMakeRange(chunk.payloadOffset,
                                                                  chunk.payloadLength)];
}

- (long long)payloadLength {
    SIGArchiveChunk *chunk = [self chunkWithTag:SIGArchiveTagPayload];
    if (!chunk) {
        return 0;
    }
    return chunk.payloadLength;
}

- (BOOL)load:(out NSError **)errorOut {
    assert(!_loaded);
    _loaded = YES;
    
    NSError *error = nil;
    const NSInteger length = [[NSFileManager defaultManager] attributesOfItemAtPath:_url.path
                                                                              error:&error].fileSize;
    if (error) {
        if (errorOut) {
            *errorOut = [SIGError errorWrapping:error
                                           code:SIGErrorCodeIORead
                                         detail:@"Failed get get size of input file"];
        }
        return NO;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:_url
                                                                   error:&error];
    if (!fileHandle) {
        if (errorOut) {
            *errorOut = [SIGError errorWrapping:error
                                           code:SIGErrorCodeIORead
                                         detail:@"Error opening file"];
        }
        return NO;
    }
    NSMutableArray<SIGArchiveChunk *> *chunks = [NSMutableArray array];
    NSInteger offset = 0;
    while (offset < length) {
        SIGArchiveChunk *chunk = [SIGArchiveChunk chunkFromFileHandle:fileHandle
                                                             atOffset:offset
                                                                error:errorOut];
        if (!chunk) {
            return NO;
        }
        [chunks addObject:chunk];
        offset = chunk.payloadOffset + chunk.payloadLength;
    }
    if (offset > length) {
        if (errorOut) {
            *errorOut = [SIGError errorWithCode:SIGErrorCodeInputFileMalformed];
        }
        return NO;
    }
    _chunks = [chunks copy];
    return YES;
}

#pragma mark - Private

- (SIGArchiveChunk *)chunkWithTag:(SIGArchiveTag)tag {
    NSInteger index = [_chunks indexOfObjectPassingTest:^BOOL(SIGArchiveChunk * _Nonnull obj,
                                                              NSUInteger idx,
                                                              BOOL * _Nonnull stop) {
        return obj.tag == tag;
    }];

    if (index == NSNotFound) {
        return nil;
    }

    return _chunks[index];
}

- (NSArray<SIGArchiveChunk *> *)chunksWithTag:(SIGArchiveTag)tag {
    NSIndexSet *indexes = [_chunks indexesOfObjectsPassingTest:^BOOL(SIGArchiveChunk * _Nonnull obj,
                                                                     NSUInteger idx,
                                                                     BOOL * _Nonnull stop) {
        return obj.tag == tag;
    }];

    return [_chunks objectsAtIndexes:indexes];
}

@end
