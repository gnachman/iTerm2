//
//  iTermRestorableStateRecord.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/19/20.
//

#import "iTermRestorableStateRecord.h"

#import "DebugLogging.h"
#import "NSData+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermRestorableStateRecord

- (instancetype)initWithWindowNumber:(NSInteger)windowNumber
                          identifier:(NSString *)identifier
                                 key:(NSData *)key
                           plaintext:(NSData *)plaintext {
    self = [super init];
    if (self) {
        _windowNumber = windowNumber;
        _identifier = [identifier copy];
        _key = [key copy];
        _plaintext = plaintext;
    }
    return self;
}

+ (void)createWithIndexEntry:(id)indexEntry
                  completion:(void (^)(iTermRestorableStateRecord *record))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        iTermRestorableStateRecord *record = [[self alloc] initWithIndexEntry:indexEntry];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(record);
        });
    });
}

- (instancetype)initWithIndexEntry:(id)indexEntry {
    NSDictionary *dict = [NSDictionary castFrom:indexEntry];
    if (!dict) {
        return nil;
    }
    NSNumber *windowNumber = [NSNumber castFrom:dict[@"windowNumber"]];
    if (!windowNumber) {
        return nil;
    }
    NSString *identifier = [NSString castFrom:dict[@"identifier"]];
    if (!identifier) {
        return nil;
    }
    NSData *key = [NSData castFrom:dict[@"key"]];
    if (!key) {
        return nil;
    }
    self = [self initWithWindowNumber:[dict[@"windowNumber"] integerValue]
                           identifier:identifier
                                  key:key
                            plaintext:[NSData data]];
    if (self) {
        NSData *blob = [NSData dataWithContentsOfURL:[self url]];
        if (!blob) {
            return nil;
        }
        NSData *ciphertext = [self ciphertextFromBlob:blob];
        if (!ciphertext) {
            return nil;
        }
        NSData *iv = [NSMutableData dataWithLength:16];
        _plaintext = [ciphertext decryptedAESCBCDataWithPCKS7PaddingAndKey:self.key
                                                                        iv:iv];
        if (!_plaintext) {
            return nil;
        }
    }
    return self;
}

#pragma mark - iTermRestorableStateRecord

- (void)didFinishRestoring {
    unlink(self.url.path.UTF8String);
}

#pragma mark - APIs

- (void)save {
    [self.data writeReadOnlyToURL:self.url];
}

- (id)indexEntry {
    return @{ @"identifier": self.identifier ?: @"",
              @"windowNumber": @(self.windowNumber),
              @"key": self.key };
}

- (iTermRestorableStateRecord *)withPlaintext:(NSData *)newPlaintext {
    return [[iTermRestorableStateRecord alloc] initWithWindowNumber:_windowNumber
                                                         identifier:_identifier
                                                                key:_key
                                                          plaintext:newPlaintext];
}

#pragma mark - Saving

// You might wonder why we bother to encrypt the file and then save the key in the
// same directory. I do it only because Apple did it, just in case there's a good
// reason for it that I haven't thought of yet.
- (NSData *)ciphertext {
    NSData *iv = [[NSMutableData alloc] initWithLength:self.key.length];
    return [self.plaintext aesCBCEncryptedDataWithPCKS7PaddingAndKey:self.key iv:iv];
}

- (NSData *)data {
    NSMutableData *buffer = [NSMutableData data];
    [buffer appendData:[self magic]];
    [buffer appendData:[self version]];
    NSData *ciphertext = [self ciphertext];
    [buffer appendData:[self word:ciphertext.length]];
    [buffer appendData:ciphertext];
    return buffer;
}

#pragma mark - Loading

- (NSData *)ciphertextFromBlob:(NSData *)blob {
    NSInteger offset = 0;
    
    NSArray<NSData *> *expectedValues = @[ self.magic, self.version ];
    for (NSData *expected in expectedValues) {
        if (blob.length < offset + expected.length ||
            ![[blob subdataWithRange:NSMakeRange(offset, expected.length)] isEqualToData:expected]) {
            return nil;
        }
        offset += expected.length;
    }
    if (blob.length < offset + sizeof(NSUInteger)) {
        return nil;
    }
    NSData *lengthWord = [blob subdataWithRange:NSMakeRange(offset, sizeof(NSUInteger))];
    offset += sizeof(NSUInteger);
    const NSUInteger length = [self decodeWord:lengthWord];
    if (blob.length < offset + length) {
        return nil;
    }
    return [blob subdataWithRange:NSMakeRange(offset, length)];
}

- (NSUInteger)decodeWord:(NSData *)data {
    NSUInteger w = 0;
    assert(sizeof(w) == data.length);
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    for (int i = 0; i < 8; i++) {
        w <<= 8;
        w |= bytes[i];
    }
    return w;
}

#pragma mark - Common

- (NSURL *)url {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *savedState = [appSupport stringByAppendingPathComponent:@"SavedState"];

    NSURL *url = [NSURL fileURLWithPath:savedState];
    [url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    url = [url URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.data", @(self.windowNumber)]];
    return [url URLByResolvingSymlinksInPath];
}

- (NSData *)magic {
    return [NSData dataWithBytes:"itws" length:4];
}

- (NSData *)version {
    return [self word:1];
}

- (NSData *)word:(NSUInteger)value {
    char temp[8];
    assert(sizeof(temp) == sizeof(value));
    NSUInteger w = value;
    for (int i = 7; i >= 0; i--) {
        temp[i] = (w & 0xff);
        w >>= 8;
    }
    return [NSData dataWithBytes:temp length:sizeof(temp)];
}

- (NSKeyedUnarchiver *)unarchiver {
    DLog(@"Restore %@", @(self.windowNumber));
    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:self.plaintext
                                                                                error:&error];
    unarchiver.requiresSecureCoding = NO;
    if (error) {
        DLog(@"Restoration failed with %@", error);
        unlink(self.url.path.UTF8String);
        return nil;
    }

    return unarchiver;
}

- (nonnull id<iTermRestorableStateRecord>)recordWithPayload:(nonnull id)payload {
    return [self withPlaintext:payload];
}

@end
