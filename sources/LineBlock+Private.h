//
//  LineBlock+Private.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/7/23.
//

#import "LineBlock.h"

@class iTermAtomicMutableArrayOfWeakObjects<T>;
@class iTermCompressibleCharacterBuffer;
@protocol iTermLineBlockObserver;
@class iTermWeakBox<T>;

NS_ASSUME_NONNULL_BEGIN

@interface LineBlock() {
    iTermCompressibleCharacterBuffer *_characterBuffer;
    int _startOffset;  // Index of the first non-dropped screen_char_t in _rawBuffer.
    NSMutableArray<iTermWeakBox<id<iTermLineBlockObserver>> *> *_observers;
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
@property(nonatomic) iTermAtomicMutableArrayOfWeakObjects<LineBlock *> *clients;  // Copy-on write instances that still exist and have me as the owner.
@property(nonatomic, readwrite) NSInteger generation;
@end

NS_ASSUME_NONNULL_END
