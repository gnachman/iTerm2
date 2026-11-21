//
//  RuntimeSnapshotOwnershipCxxFixtures.mm
//  ModernTests
//
//  An Objective-C++ class with C++ members, used by
//  RuntimeSnapshotOwnershipTests.swift (docs/swift-migration/phase0.md
//  section 9). Compiled with ARC. A C++ member's destructor runs from the
//  class's .cxx_destruct, and the ivar layout describes only the words that
//  ARC itself retains or holds weakly: a std::vector<id> holds strong
//  references inside memory it allocates, which no layout can describe.
//
//  Changing anything here changes the expected snapshots in the tests.
//

#import <Foundation/Foundation.h>

#include <memory>
#include <string>
#include <vector>

// A C++ class with a user-declared destructor and an ARC-managed member. The
// layout covers its strong member like any struct field.
struct RuntimeSnapshotOwnershipCxxHolder {
    id object;
    int count;
    ~RuntimeSnapshotOwnershipCxxHolder() {}
};

// A plain struct with no object pointers.
struct RuntimeSnapshotOwnershipCxxPlain {
    int a;
    int b;
};

@interface RuntimeSnapshotOwnershipCxxFixture : NSObject
@end

@implementation RuntimeSnapshotOwnershipCxxFixture {
    std::string _name;                          // no layout words
    std::vector<id> _objects;                   // no layout words; owns its elements
    std::shared_ptr<int> _shared;               // no layout words
    RuntimeSnapshotOwnershipCxxHolder _holder;  // first word strong
    RuntimeSnapshotOwnershipCxxPlain _plain;    // no layout words
    id _plainObject;                            // strong
}
@end
