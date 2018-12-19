//
//  SIGArchiveChunk.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(long long, SIGArchiveTag) {
    SIGArchiveTagHeader = 0,
    SIGArchiveTagPayload = 1,
    SIGArchiveTagMetadata = 2,
    SIGArchiveTagSignature = 3,
    SIGArchiveTagCertificate = 4,
};

extern NSString *const SIGArchiveHeaderMagicString;

@interface SIGArchiveChunk : NSObject

@property (nonatomic, readonly) SIGArchiveTag tag;
@property (nonatomic, readonly) long long payloadLength;
@property (nonatomic, readonly) long long chunkLength;
@property (nonatomic, readonly) long long payloadOffset;
@property (nonatomic, readonly) NSFileHandle *fileHandle;

+ (instancetype)chunkFromFileHandle:(NSFileHandle *)fileHandle
                           atOffset:(long long)offset
                              error:(out NSError **)error;

- (instancetype)initWithTag:(SIGArchiveTag)tag
                     length:(long long)length
                     offset:(long long)offset NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSData *)data:(out NSError **)error;

@end

@interface SIGArchiveChunkWriter : SIGArchiveChunk

- (BOOL)writeData:(NSData *)data
         toStream:(NSOutputStream *)stream
            error:(out NSError **)error;

- (BOOL)writeStream:(NSInputStream *)readStream
           toStream:(NSOutputStream *)writeStream
              error:(out NSError **)error;

@end


NS_ASSUME_NONNULL_END
