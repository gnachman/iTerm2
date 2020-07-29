//
//  iTermRestorableStateRecord.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/19/20.
//

#import <Foundation/Foundation.h>
#import "iTermRestorableStateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermRestorableStateRecord : NSObject<iTermRestorableStateRecord>

// Crypto key for the saved state.
@property (nonatomic, readonly) NSData *key;

// Window identifier.
@property (nonatomic, readonly) NSString *identifier;

// Window number.
@property (nonatomic, readonly) NSInteger windowNumber;

// Saved state.
@property (nonatomic, readonly) NSData *plaintext;

// Metadata.
@property (nonatomic, readonly) id indexEntry;

// Where the blob is saved.
@property (nonatomic, readonly) NSURL *url;

// Reads, deserializes, and decrypts a record from its metadata entry.
+ (void)createWithIndexEntry:(id)indexEntry
                  completion:(void (^)(iTermRestorableStateRecord *record))completion;

- (instancetype)initWithWindowNumber:(NSInteger)windowNumber
                          identifier:(NSString *)identifier
                                 key:(NSData *)key
                           plaintext:(NSData *)plaintext NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIndexEntry:(id)indexEntry;

- (instancetype)init NS_UNAVAILABLE;

// Write record to disk. Blocks.
- (void)save;
- (iTermRestorableStateRecord *)withPlaintext:(NSData *)newPlaintext;
- (NSKeyedUnarchiver *)unarchiver;

@end

NS_ASSUME_NONNULL_END
