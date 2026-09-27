//
//  iTermTabGroupBuiltInFunctions.h
//  iTerm2SharedARC
//
//  Python API functions that mutate a tab group by its id.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// App-scope Python API functions that rename, recolor, or collapse a tab group
// identified by its id, regardless of which window currently hosts it.
//
// A group's identity (a UUID) rides its member tabs, so it survives the tabs
// being dragged to another window. These functions resolve the owning window at
// call time rather than binding to the window the group was fetched from, so
// they keep working after such a move. Membership changes (create/add/remove)
// stay window-scoped methods on PseudoTerminal because they operate on tabs
// whose window is known at call time.
@interface iTermTabGroupBuiltInFunctions : NSObject
+ (void)registerBuiltInFunction;
@end

NS_ASSUME_NONNULL_END
