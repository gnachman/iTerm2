//
//  NSData+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (iTerm)

// Tries to guess, from the first bytes of data, what kind of image it is and
// returns the corresponding UTI string constant. Not guaranteed to be correct.
@property(nullable, nonatomic, readonly) NSString *uniformTypeIdentifierForImageData;

  // Base-64 decodes string and returns data or nil.
+ (NSData * _Nullable)dataWithBase64EncodedString:(NSString *)string;

// Returns termination status.
+ (int)untarFromArchive:(NSURL *)tarfile to:(NSURL *)destinationFolder;
+ (NSData * _Nullable)dataWithTGZContainingFiles:(NSArray<NSString *> *)files
                                  relativeToPath:(NSString *)basePath
                            includeExtendedAttrs:(BOOL)includeExtendedAttrs
                                           error:(NSError * _Nullable __autoreleasing * _Nullable)error;

// returns a string the the data base-64 encoded into 77-column lines divided by lineBreak.
- (NSString *)stringWithBase64EncodingWithLineBreak:(NSString *)lineBreak;

// Indicates if the data contains a single-byte code belonging to |asciiSet|.
- (BOOL)containsAsciiCharacterInSet:(NSCharacterSet *)asciiSet;

- (BOOL)hasPrefixOfBytes:(char *)bytes length:(int)length;


// Appends this data to the file at |path|. If |addNewline| is YES then a '\n' is appended if the
// file does not already end with \n or \r. This plays a little fast and loose with character
// encoding, but it gets the job done.
- (BOOL)appendToFile:(NSString *)path addLineBreakIfNeeded:(BOOL)addNewline;

// Converts data into a string using the given encoding.
- (NSString * _Nullable)stringWithEncoding:(NSStringEncoding)encoding;

+ (NSData *)it_dataWithArchivedObject:(id<NSCoding>)object;
- (id _Nullable)it_unarchivedObjectOfClasses:(NSArray<Class> *)allowedClasses;

+ (NSData *)it_dataWithSecurelyArchivedObject:(id<NSCoding>)object error:(NSError * _Nullable __autoreleasing * _Nullable)error;
- (id _Nullable)it_unarchivedObjectOfBasicClassesWithError:(NSError * _Nullable __autoreleasing * _Nullable)error;

- (BOOL)isEqualToByte:(unsigned char)byte;
- (NSData *)it_sha256;
- (NSString *)it_hexEncoded;
- (NSData * _Nullable)it_compressedData;

- (NSData * _Nullable)aesCBCEncryptedDataWithPCKS7PaddingAndKey:(NSData *)key
                                                             iv:(NSData *)iv;

- (NSData * _Nullable)decryptedAESCBCDataWithPCKS7PaddingAndKey:(NSData *)key
                                                             iv:(NSData *)iv;

+ (NSData *)randomAESKey;

- (void)writeReadOnlyToURL:(NSURL *)url;
- (NSData *)subdataFromOffset:(NSInteger)offset;
- (NSData *)dataByAppending:(NSData *)other;

@end

NS_ASSUME_NONNULL_END
