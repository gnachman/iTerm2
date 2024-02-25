//
//  LineBlock+Private.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/7/23.
//

#import "LineBlock.h"

@class iTermLegacyAtomicMutableArrayOfWeakObjects;
@protocol iTermLineBlockMutationCertificate;
@class iTermCharacterBuffer;
@class iTermWeakBox<T>;

NS_ASSUME_NONNULL_BEGIN

@interface LineBlock() {
    int _startOffset;  // Index of the first non-dropped screen_char_t in _rawBuffer.

@public
    // The raw lines, end-to-end. There is no delimiter between each line.
    iTermCharacterBuffer *_characterBuffer;

    int first_entry;  // first valid cumulative_line_length


    // There will be as many entries in this array as there are lines in _characterBuffer.
    // The ith value is the length of the ith line plus the value of
    // cumulative_line_lengths[i-1] for i>0 or 0 for i==0.
    //    const int * const cumulative_line_lengths;
    int *cumulative_line_lengths;
    LineBlockMetadata *metadata_;

    // The number of elements allocated for cumulative_line_lengths.
    int cll_capacity;

    // The number of values in the cumulative_line_lengths array.
    int cll_entries;

    // If true, then the last raw line does not include a logical newline at its terminus.
    BOOL is_partial;

    // The number of wrapped lines if width==cached_numlines_width.
    int cached_numlines;

    // This is -1 if the cache is invalid; otherwise it specifies the width for which
    // cached_numlines is correct.
    int cached_numlines_width;

    NSString *_guid;

    NSObject *_cachedMutationCert;  // DON'T USE DIRECTLY THIS UNLESS YOU LOVE PAIN. Only -validMutationCertificate should touch it.

    __weak LineBlock *_progenitor;
    long long _absoluteBlockNumber;
}

// These are synchronized on [LineBlock class]. Sample graph:
//
// Begin with just one LineBlock, A:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o, o]
// | buffer    |o---> [malloced memory]       :  :
// +-----------+                    ^         :  :
//
// Now call -cowCopy on it to create B, and you get:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o]
// | buffer    |o---> [malloced memory]       :
// +-----------+                    ^         :
//       ^                          |         :
//       |             ,- - - - - - ) - - -  -'
//       |             :            |
//       |             V            |
//       |       B-----------+      |
//       |       | LineBlock |      |
//       |       |-----------|      |
//       |       | buffer    |o-----'
//       `------o| owner     |
//               | clients   |o---> []
//               +-----------+
//
// Calling -cowCopy again on either A or B gives C, resulting in this state:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o--------------------------> [o, o]
// | buffer    |o---> [malloced memory]       :  :
// +-----------+                    ^         :  :
//       ^                          |         :  :
//       |             ,- - - - - - ) - - -  -'  ` - - - -,
//       |             :            |                   :
//       |             V            |                   V
//       |       B-----------+      |             C-----------+
//       |       | LineBlock |      |             | LineBlock |
//       |       |-----------|      |             |-----------|
//       |       | buffer    |o-----+------------o| buffer    |
//       +------o| owner     |               .---o| owner     |
//       |       | clients   |o---> []       |    | clients   |o---> []
//       |       +-----------+               |    +-----------+
//       |                                   |
//       `-----------------------------------'
//
// If you modify A (an owner) then you get this situation:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o---> []
// | buffer    |o---> [copy of malloced memory]
// +-----------+
//                    [original malloced memory]
//                                  ^
//                                  |
//               B-----------+      |             C-----------+
//               | LineBlock |      |             | LineBlock |
//               |-----------|      |             |-----------|
//               | buffer    |o-----+------------o| buffer    |
//               | owner     |<------------------o| owner     |
//               | clients   |o---> [o]           | clients   |o---> []
//               +-----------+       |            +-----------+
//                                   |                  ^
//                                   |                  |
//                                   `------------------`
//  From here, if you modify C (a client) you get:
//
// A-----------+
// | LineBlock |
// |-----------|
// | owner     |o---> nil
// | clients   |o---> []
// | buffer    |o---> [copy of malloced memory]
// +-----------+
//                    [original malloced memory]
//                                  ^
//                                  |
//               B-----------+      |             C-----------+
//               | LineBlock |      |             | LineBlock |
//               |-----------|      |             |-----------|
//               | buffer    |o-----`             | buffer    |o---> [another copy of malloced memory]
//               | owner     |o---> nil           | owner     |o---> nil
//               | clients   |o---> []            | clients   |o---> []
//               +-----------+                    +-----------+
//
// Clients strongly retain their owners. That means that when a LineBlock is dealloced, it must have
// no clients and it is safe to free memory.
// When a client gets dealloced it does not need to free memory.
// An owner "owns" the memory and is responsible for freeing it.
// When owner is nonnil or clients is not empty, a copy must be made before mutation.
// Use -modifyWithBlock: to get a iTermLineBlockMutationCertificate which allows mutation safely because
// you can't get a certificate without copying (if needed).
@property(nonatomic, nullable) LineBlock *owner;  // nil if I am an owner. This is the line block that is responsible for freeing malloced data.
@property(nonatomic) iTermLegacyAtomicMutableArrayOfWeakObjects *clients;  // Copy-on write instances that still exist and have me as the owner.
@property(nonatomic, readwrite) NSInteger generation;
@property(atomic, readwrite) BOOL hasBeenCopied;

- (int)bufferStartOffset;
- (void)setBufferStartOffset:(ptrdiff_t)offset;
- (LineBlock *)copyDeep:(BOOL)deep absoluteBlockNumber:(long long)absoluteBlockNumber;
- (id<iTermLineBlockMutationCertificate>)validMutationCertificate;

@end

NS_ASSUME_NONNULL_END
