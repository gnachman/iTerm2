//
//  NSData+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import "NSData+iTerm.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "zlib.h"

#import <apr-1/apr_base64.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>

#include <sys/types.h>
#include <sys/stat.h>

@implementation NSData (iTerm)

+ (NSData *)dataWithBase64EncodedString:(NSString *)string {
    const char *buffer = [[string stringByReplacingOccurrencesOfRegex:@"[\x0a\x0d]" withString:@""] UTF8String];
    int destLength = apr_base64_decode_len(buffer);
    if (destLength <= 0) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    if (resultLength <= 0) {
        return nil;
    }
    [data setLength:resultLength];
    return data;
}

- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak {
    // Subtract because the result includes the trailing null. Take MAX in case it returns 0 for
    // some reason.
    int length = MAX(0, apr_base64_encode_len(self.length) - 1);
    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    if (buffer) {
        apr_base64_encode_binary(buffer.mutableBytes,
                                 self.bytes,
                                 self.length);
    }
    NSMutableString *string = [NSMutableString string];
    int remaining = length;
    int offset = 0;
    char *bytes = (char *)buffer.mutableBytes;
    while (remaining > 0) {
        @autoreleasepool {
            NSString *chunk = [[NSString alloc] initWithBytes:bytes + offset
                                                        length:MIN(77, remaining)
                                                     encoding:NSUTF8StringEncoding];
            [string appendString:chunk];
            [string appendString:lineBreak];
            remaining -= chunk.length;
            offset += chunk.length;
        }
    }
    return string;
}

+ (int)untarFromArchive:(NSURL *)tarfile to:(NSURL *)destinationFolder {
    NSArray<NSString *> *args = @[
        @"-x",
        @"-z",
        @"-C",
        destinationFolder.path,
        @"-f",
        tarfile.path ];
    
    NSTask *task = [[NSTask alloc] init];
    NSMutableDictionary<NSString *, NSString *> *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"COPYFILE_DISABLE"] = @"1";
    [task setEnvironment:environment];
    [task setLaunchPath:@"/usr/bin/tar"];
    [task setArguments:args];
    [task setStandardInput:[NSPipe pipe]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    NSData *data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
    DLog(@"%@", data);
    NSData *errorMessage = [[[task standardError] fileHandleForReading] readDataToEndOfFile];
    if (errorMessage.length) {
        DLog(@"%@ %@: %@", task.launchPath, [task.arguments componentsJoinedByString:@" "], [errorMessage stringWithEncoding:NSUTF8StringEncoding]);
    }
    [task waitUntilExit];
    return task.terminationStatus;
}

+ (NSData *)dataWithTGZContainingFiles:(NSArray<NSString *> *)files
                        relativeToPath:(NSString *)basePath
                  includeExtendedAttrs:(BOOL)includeExtendedAttrs
                                 error:(NSError **)error {
    NSArray<NSString *> *args = @[ @"-c",  // Create
                                   @"-z",  // gzip
                                   @"-b",
                                   @"1",  // Block size
                                   @"-f",
                                   @"-",  // write to stdout
                                   [NSString stringWithFormat:@"-C%@", basePath] ];  // Base path
    if (!includeExtendedAttrs) {
        args = [@[@"--no-xattrs"] arrayByAddingObjectsFromArray:args];
    }
    args = [args arrayByAddingObjectsFromArray:files];  // Files to zip

    NSTask *task = [[NSTask alloc] init];
    NSMutableDictionary<NSString *, NSString *> *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"COPYFILE_DISABLE"] = @"1";
    [task setEnvironment:environment];
    [task setLaunchPath:@"/usr/bin/tar"];
    [task setArguments:args];
    [task setStandardInput:[NSPipe pipe]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    NSData *data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
    NSData *errorMessage = [[[task standardError] fileHandleForReading] readDataToEndOfFile];
    if (error) {
        *error = nil;
    }
    if (errorMessage.length) {
        NSString *errorString = [errorMessage stringWithEncoding:NSUTF8StringEncoding];
        if (errorString) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.googlecode.iterm2" code:1 userInfo:@{ @"errorMessage": errorString }];
            }
        } else {
            XLog(@"Error %s", (const char *)errorMessage.bytes);
        }
    }
    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        return nil;
    }
    return data;
}

- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet {
    char flags[256];
    for (int i = 0; i < 256; i++) {
        flags[i] = [asciiSet characterIsMember:i];
    }
    const unsigned char *bytes = [self bytes];
    int length = [self length];
    for (int i = 0; i < length; i++) {
        if (flags[bytes[i]]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasPrefixOfBytes:(char *)bytes length:(int)length {
    if (self.length < length) {
        return NO;
    }
    char *myBytes = (char *)self.bytes;
    return !memcmp(myBytes, bytes, length);
}

- (NSString *)uniformTypeIdentifierForImageData {
    struct {
        const char *fingerprint;
        int length;
        CFStringRef uti;
    } identifiers[] = {
        { "BM", 2, kUTTypeBMP },
        { "GIF", 3, kUTTypeGIF },
        { "\xff\xd8\xff", 3, kUTTypeJPEG },
        { "\x00\x00\x01\x00", 4, kUTTypeICO },
        { "II\x2a\x00", 4, kUTTypeTIFF },
        { "MM\x00\x2a", 4, kUTTypeTIFF },
        { "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a", 8, kUTTypePNG },
        { "\x00\x00\x00\x0c\x6a\x50\x20\x20\x0d\x0a\x87\x0a", 12, kUTTypeJPEG2000 }
    };

    for (int i = 0; i < sizeof(identifiers) / sizeof(*identifiers); i++) {
        if (self.length >= identifiers[i].length &&
            !memcmp(self.bytes, identifiers[i].fingerprint, identifiers[i].length)) {
            return (__bridge NSString *)identifiers[i].uti;
        }
    }
    return nil;
}

- (BOOL)appendToFile:(NSString *)path addLineBreakIfNeeded:(BOOL)addNewline {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:path];
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fileHandle) {
            DLog(@"Failed to open for writing or create %@", path);
            return NO;
        }
    }

    @try {
        [fileHandle seekToEndOfFile];
        if (addNewline) {
            unsigned long long length = fileHandle.offsetInFile;
            if (length > 0) {
                [fileHandle seekToFileOffset:length - 1];
                NSData *data = [fileHandle readDataOfLength:1];
                if (data.length == 1) {
                    char lastByte = ((const char *)data.bytes)[0];
                    if (lastByte != '\r' && lastByte != '\n') {
                        [fileHandle seekToEndOfFile];
                        [fileHandle writeData:[NSData dataWithBytes:"\n" length:1]];
                    }
                }
            }
        }
        [fileHandle writeData:self];
        return YES;
    }
    @catch (NSException * e) {
        return NO;
    }
    @finally {
        [fileHandle closeFile];
    }
}

- (NSString *)stringWithEncoding:(NSStringEncoding)encoding {
    return [[NSString alloc] initWithData:self encoding:encoding];
}

+ (NSData *)it_dataWithArchivedObject:(id<NSCoding>)object {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    archiver.requiresSecureCoding = NO;
    [archiver encodeObject:object forKey:@"object"];
    [archiver finishEncoding];
    return archiver.encodedData;
}

- (id)it_unarchivedObjectOfClasses:(NSArray<Class> *)allowedClasses {
    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:self error:&error];
    if (error) {
        return nil;
    }
    unarchiver.requiresSecureCoding = NO;
    return [unarchiver decodeObjectOfClasses:[NSSet setWithArray:allowedClasses] forKey:@"object"];
}

+ (NSData *)it_dataWithSecurelyArchivedObject:(id<NSCoding>)object error:(NSError **)error {
    NSError *innerError = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:YES error:&innerError];
    if (innerError) {
        XLog(@"Error %@ encoding\n%@", innerError, object);
    }
    if (error) {
        *error = innerError;
    }
    return data;
}

- (id)it_unarchivedObjectOfBasicClassesWithError:(NSError **)error {
    NSArray<Class> *classes = @[ [NSDictionary class],
                                 [NSNumber class],
                                 [NSString class],
                                 [NSDate class],
                                 [NSData class],
                                 [NSArray class],
                                 [NSNull class],
                                 [NSValue class],
                                 [iTermTuple class] ];
    NSError *innerError = nil;
    id obj = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:classes]
                                                 fromData:self
                                                    error:&innerError];
    if (innerError) {
        XLog(@"Error %@ decoding %@", innerError, self);
    }
    if (error) {
        *error = innerError;
    }
    return obj;
}

- (BOOL)isEqualToByte:(unsigned char)byte {
    if (self.length != 1) {
        return NO;
    }
    unsigned char myByte = ((unsigned char *)self.bytes)[0];
    return byte == myByte;
}

- (NSData *)it_sha256 {
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(self.bytes, (CC_LONG)self.length, result);
    return [NSData dataWithBytes:result
                          length:CC_SHA256_DIGEST_LENGTH];
}

- (NSData *)hashWithSHA256 {
    return [self it_sha256];
}

- (NSString *)it_hexEncoded {
    NSMutableString *result = [NSMutableString string];
    const unsigned char *bytes = self.bytes;
    for (NSInteger i = 0; i < self.length; i++) {
        unsigned char c = bytes[i];
        [result appendFormat:@"%02x", ((int)c) & 0xff];
    }
    return result;
}

- (NSData *)it_compressedData {

    if (self.length == 0) {
        return self;
    }

    z_stream stream = {
        .next_in = (Bytef *)self.bytes,
        .avail_in = self.length,
        .total_in = 0,

        .next_out = Z_NULL,
        .avail_out = 0,
        .total_out = 0,

        .msg = Z_NULL,
        .state = Z_NULL,

        .zalloc = Z_NULL,
        .zfree = Z_NULL,
        .opaque = Z_NULL,

        .data_type = 0,
        .adler = 0,
        .reserved = 0
    };

    const int initError = deflateInit2(&stream,
                                       Z_DEFAULT_COMPRESSION,  // level: medium compression (6/9)
                                       Z_DEFLATED,             // method: this is the only option
                                       (15 + 16),              // windowBits: max compression plus gzip headers.
                                       8,                      // memLevel: use lots of memory and be fast.
                                       Z_DEFAULT_STRATEGY);    // stragegy: normal strategy
    if (initError != Z_OK) {
        DLog(@"deflateInit2 failed with error %@", @(initError));
        return nil;
    }

    // The docs say to create a destination that is 1% larger plus 12 bytes.
    NSMutableData *compressedData = [NSMutableData dataWithLength:ceil(self.length * 1.01) + 12];

    int deflateStatus;
    do {
        stream.next_out = compressedData.mutableBytes + stream.total_out;
        uLong avail_out = compressedData.length - stream.total_out;
        if (avail_out == 0) {
            // Shouldn't happen.
            compressedData.length = compressedData.length * 2;
            avail_out = compressedData.length - stream.total_out;
        }
        stream.avail_out = avail_out;
        deflateStatus = deflate(&stream, Z_FINISH);
    } while (deflateStatus == Z_OK);

    deflateEnd(&stream);

    if (deflateStatus != Z_STREAM_END) {
        DLog(@"deflate failed with %@", @(deflateStatus));
        return nil;
    }

    compressedData.length = stream.total_out;
    return compressedData;
}


- (NSData *)aesCBCEncryptedDataWithPCKS7PaddingAndKey:(NSData *)key
                                                   iv:(NSData *)iv {
    assert(iv.length == 16);
    assert(key.length == 16);
    
    NSMutableData *ciphertext = [NSMutableData dataWithLength:self.length + kCCBlockSizeAES128];
    
    size_t length;
    const CCCryptorStatus result = CCCrypt(kCCEncrypt,
                                           kCCAlgorithmAES,
                                           kCCOptionPKCS7Padding,
                                           key.bytes,
                                           key.length,
                                           iv.bytes,
                                           self.bytes,
                                           self.length,
                                           ciphertext.mutableBytes,
                                           ciphertext.length,
                                           &length);
    
    if (result == kCCSuccess) {
        ciphertext.length = length;
    } else {
        return nil;
    }
    
    return ciphertext;
}

- (NSData *)decryptedAESCBCDataWithPCKS7PaddingAndKey:(NSData *)key
                                                   iv:(NSData *)iv {
    assert(iv.length == 16);
    assert(key.length == 16);
    
    NSMutableData *plaintext = [NSMutableData dataWithLength:self.length];
    
    size_t length;
    const CCCryptorStatus result = CCCrypt(kCCDecrypt,
                                           kCCAlgorithmAES,
                                           kCCOptionPKCS7Padding,
                                           key.bytes,
                                           key.length,
                                           iv.bytes,
                                           self.bytes,
                                           self.length,
                                           plaintext.mutableBytes,
                                           plaintext.length,
                                           &length);
    
    if (result == kCCSuccess) {
        plaintext.length = length;
    } else {
        return nil;
    }
    
    return plaintext;

}

+ (NSData *)randomAESKey {
    const NSUInteger length = 16;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    
    const int result = SecRandomCopyBytes(kSecRandomDefault,
                                          length,
                                          data.mutableBytes);
    assert(result == 0);
    
    return data;
}

- (void)writeReadOnlyToURL:(NSURL *)url {
    // Use POSIX APIs to ensure that permissions are set before writing to the file.

    // Unlink file if it already exists.
    unlink(url.path.UTF8String);
    
    // Create it exclusively. If another instance of iTerm2 is trying to create it, back off.
    int fd = -1;
    do {
        fd = open(url.path.UTF8String, O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC | O_EXCL, 0600);
    } while (fd == -1 && errno == EINTR);
    if (fd == -1) {
        return;
    }
    
    // Append the data.
    NSUInteger written = 0;
    while (written < self.length) {
        ssize_t result = 0;
        do {
            result = write(fd, self.bytes + written, self.length - written);
        } while (result == -1 && errno == EINTR);
        if (result <= 0) {
            ftruncate(fd, 0);
            close(fd);
            unlink(url.path.UTF8String);
            return;
        }
        written += result;
    }

    close(fd);
}

- (NSData *)subdataFromOffset:(NSInteger)offset {
    if (offset <= 0) {
        return self;
    }
    if (offset >= self.length) {
        return [NSData data];
    }
    return [self subdataWithRange:NSMakeRange(offset, self.length - offset)];
}

- (NSString *)tastefulDescription {
    if (self.length < 10) {
        return [self description];
    }
    return [[self subdataWithRange:NSMakeRange(0, 10)] description];
}

- (NSData *)dataByAppending:(NSData *)other {
    NSMutableData *temp = [self mutableCopy];
    [temp appendData:other];
    return temp;
}

@end
