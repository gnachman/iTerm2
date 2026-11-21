//
//  RuntimeSnapshotOwnershipFixtures.m
//  ModernTests
//
//  Classes whose ivar layouts are known by construction, used by
//  RuntimeSnapshotOwnershipTests.swift to test how the runtime snapshot
//  reports ivar ownership (docs/swift-migration/phase0.md section 9). This
//  file is compiled with ARC, like every file in ModernTests.
//
//  The comments give each ivar's offset and its word index in the layout.
//  Layout words count from the class's instance start rounded up to a word,
//  which is 8 for a direct subclass of NSObject (its only ivar is isa). The
//  expected layout strings in the tests follow from these positions and from
//  clang's encoder (IvarLayoutBuilder::buildBitmap in CGObjCMac.cpp): one byte
//  per run, the high nibble the words to skip and the low nibble the words to
//  scan, 15 at most each, and a terminating zero byte.
//
//  Changing anything here changes the expected snapshots in the tests.
//

#import <Foundation/Foundation.h>

// A C struct with ARC-managed fields, which Objective-C allows since clang
// supports non-trivial C structs: the layout covers it word by word.
typedef struct {
    __strong id strongField;               // word +0
    NSInteger number;                      // word +1
    __weak id weakField;                   // word +2
    __unsafe_unretained id unretainedField; // word +3
} RuntimeSnapshotOwnershipMixedStruct;

@interface RuntimeSnapshotOwnershipARCFixture : NSObject
@end

@implementation RuntimeSnapshotOwnershipARCFixture {
    id _strongObject;                           // offset 8, word 0: strong
    __weak id _weakObject;                      // 16, word 1: weak
    __unsafe_unretained id _unretainedObject;   // 24, word 2: neither
    Class _classObject;                         // 32, word 3: neither (ARC leaves an unqualified Class unretained)
    void (^_block)(void);                       // 40, word 4: strong
    int _scalar;                                // 48
    char _byte;                                 // 52
    id _afterByte;                              // 56, word 6: strong
    void *_rawPointer;                          // 64, word 7: neither
    CFStringRef _cfString;                      // 72, word 8: neither
    __strong id *_objectPointer;                // 80, word 9: neither (a C pointer)
    SEL _selector;                              // 88, word 10
    unsigned _flagA : 1;                        // 96, word 11
    unsigned _flagB : 3;                        // 96, word 11
    NSRect _rect;                               // 104, words 12 to 15
    RuntimeSnapshotOwnershipMixedStruct _mixed; // 136, words 16 to 19: strong, -, weak, -
    __strong id _objects[3];                    // 168, words 20 to 22: strong
    union {
        int i;
        float f;
    } _union;                                   // 192, word 23
}
@end

// More than 15 words to skip and to scan, so the layout needs runs that
// continue in the next byte.
@interface RuntimeSnapshotOwnershipLongLayoutFixture : NSObject
@end

@implementation RuntimeSnapshotOwnershipLongLayoutFixture {
    // Words 0 to 19: not object references.
    NSInteger _s00, _s01, _s02, _s03, _s04, _s05, _s06, _s07, _s08, _s09;
    NSInteger _s10, _s11, _s12, _s13, _s14, _s15, _s16, _s17, _s18, _s19;
    // Words 20 to 36: strong.
    id _o00, _o01, _o02, _o03, _o04, _o05, _o06, _o07, _o08, _o09;
    id _o10, _o11, _o12, _o13, _o14, _o15, _o16;
    // Words 37 to 54: not object references.
    NSInteger _t00, _t01, _t02, _t03, _t04, _t05, _t06, _t07, _t08, _t09;
    NSInteger _t10, _t11, _t12, _t13, _t14, _t15, _t16, _t17;
    // Word 55: weak.
    __weak id _weak;
    // Word 56: strong.
    id _last;
}
@end

// No ivar is strong, so clang writes no strong layout at all, although the
// class is compiled with ARC.
@interface RuntimeSnapshotOwnershipNoStrongFixture : NSObject
@end

@implementation RuntimeSnapshotOwnershipNoStrongFixture {
    __weak id _weakObject;                      // word 0: weak
    __unsafe_unretained id _unretainedObject;   // word 1: neither
    NSInteger _number;                          // word 2
}
@end

// A subclass whose own ivars start after its superclass's, so its layout is
// relative to its own instance start, not to the start of the object.
@interface RuntimeSnapshotOwnershipSubclassFixture : RuntimeSnapshotOwnershipNoStrongFixture
@end

@implementation RuntimeSnapshotOwnershipSubclassFixture {
    NSInteger _subclassNumber;                  // offset 32, word 0
    id _subclassStrong;                         // 40, word 1: strong
}
@end

// A property-backed ivar of each ownership, as most classes have them.
@interface RuntimeSnapshotOwnershipPropertyFixture : NSObject
@property (nonatomic, strong) NSObject *strongProperty;
@property (nonatomic, weak) NSObject *weakProperty;
@property (nonatomic, assign) NSObject *assignProperty;
@property (nonatomic, copy) NSString *copiedProperty;
@end

@implementation RuntimeSnapshotOwnershipPropertyFixture
@end
