/*
 * --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
 *
 * This is an implementation of the Arne Andersson Tree, which is a balanced binary search
 * tree. For more information on how the balancing, inserting and deletion algorithms
 * work, see http://en.wikipedia.org/wiki/Andersson_tree
 *
 * This class is set-up as an extension of the NSMutableDictionary class cluster, so all
 * of the methods in the NSMutableDictionary public abstract interface can be called on this
 * class also, with the exception of the initialize methods. The class supports the
 * NSCopying and NSFastEnumeration protocols, among others.
 *
 * The class has been suitable for any type of data, and more importantly, for any type
 * of key. When initializing the tree, one must supply a NSComparator block which contains
 * the logic to compare two keys. Do note that a copy of the key is created when inserted
 * into the tree, so it must implement the NSCopying protocol.
 *
 * One of the advantages of using a tree as data model, is it is easy to determine an
 * object closest to a key. This is why the method objectClosestToKey is included in the
 * interface.
 *
 * The tree is completely thread safe. It uses a readers/write lock pattern, so multiple
 * readers (threads) don't lock each other out. The only time the readers do get locked is
 * when a writer (thread) wants or has access to the tree for mutations. In short, the
 * accessors can be used in parallel, but will have to wait for possible mutations to finish.
 * This thread safety pattern is very suitable for a tree like this and, compared to
 * the other locking mechanisms in Objective-C, the fastest when the tree is accessed
 * more often that mutated.
 *
 * This class may be used, modified and distributed freely. Of course I would like to hear
 * about any updates, requests or bugs. I can be contacted at a.roemers@gmail.com
 *
 * --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
 *
 * Author		A. Roemers
 * Version		1.0
 * Date			2010-06-18
 *
 * --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
 *
 */

#import <Cocoa/Cocoa.h>
#import "AATreeNode.h"
#import <pthread.h>

@class AATree;

@protocol AATreeDelegate <NSObject>

- (void)aaTree:(AATree *)tree didChangeSubtreesAtNodes:(NSSet *)changedNodes;
- (void)aaTree:(AATree *)tree didChangeValueAtNode:(AATreeNode *)node;

@end

@interface AATree : NSMutableDictionary <NSCopying> {

	// The root node of the tree.
	AATreeNode *root;

	// The NSComparator used to compare the keys of the nodes.
	NSComparator keyComparator;

	// The number of nodes in the tree.
	NSUInteger count;

	// The readers/writer lock for thread safety.
	pthread_rwlock_t rwLock;

    // A list of nodes that changed in the current operation.
    NSMutableSet *changedNodes;
}

@property(assign) id<AATreeDelegate> delegate;

/*!
 * @abstract				Initializes the tree with the specified key comparator.
 * @discussion				The key comparator is used for comparing the keys with
 *							each other, for every concerning operation that is performed
 *							on the tree.
 *
 *							The supplied key comparator Block is copied, so it stored in
 *							the heap. This way, the actual declaration of the key comparator
 *							can	safely go out of scope.
 *
 *							Use only this initializer, otherwise no key comparator exists.
 *
 * @param akeyComparator	A NSComparator block which compares the keys with each other.
 * @result					An initialized AA tree object.
 */
- (id) initWithKeyComparator:(NSComparator)aKeyComparator;


/*!
 * @abstract				Creates a copy of the tree.
 * @discussion				Note that modifications on the returned copy do not
 *							influence the original tree. On the other hand, the
 *							actual data and keys in the tree are not copied, so
 *							the data and keys in the copy point to exactly the
 *							same objects as in the original.
 *
 * @param zone				The zone identifies an area of memory from which to
 *							allocate for the new instance.
 * @result					A new instance of the tree.
 */
- (id) copyWithZone:(NSZone *)zone;


/*!
 * @abstract				Returns the number of objects currently in the receiver.
 *
 * @result					The number of objects currently in the receiver.
 */
- (NSUInteger) count;


/*!
 * @abstract				Returns an enumerator which enumerates over the keys in the	tree.
 * @discussion				The keys in the enumerator are order in-order. This means the
 *							keys are ordered ascending. Also note that the enumerated keys
 *							are copies of the actual keys, so modifying the keys does not
 *							influence the tree.
 *
 * @result					A NSEnumerator instance for enumerating the keys.
 */
- (NSEnumerator *) keyEnumerator;


/*!
 * @abstract				This function returns the data object which is closest to the
 *							specified key.
 * @discussion				The returned data's key is always lower than (or equal to) the
 *							specified key. This also means that if the specified key is higher
 *							than the highest key in the tree, nil is returned. The key comparator,
 *							as specified at the initialization of this tree, is used for comparing
 *							the keys.
 *
 * @param aKey				The key to look for.
 * @result					The closest data object to the key.
 */
- (id) objectClosestToKey:(id)aKey;


/*!
 * @abstract				Get the data object bound to the specified key.
 * @discussion				The key comparator, as specified at the initialization
 *							of this tree, is used for comparing the keys.
 *
 * @param aKey				The key to look for.
 * @result					The data object found, or nil when no data has been found.
 */
- (id) objectForKey:(id)aKey;


/*!
 * @abstract				Display the tree using NSLog().
 */
- (void) print;


/*!
 * @abstract				Delete the data object bound to the specified key.
 * @discussion				The key comparator, as specified at the initialization
 *							of this tree, is used for comparing the keys. If no data is found
 *							for the specified key, the tree remains unaltered.
 *
 * @param aKey				The key to look for.
 */
- (void) removeObjectForKey:(id)aKey;


/*!
 * @abstract				Insert the specified data into the tree, bound to the specified key.
 * @discussion				If the specified key is already in the tree, the old data is replaced
 *							with the new data. Note that the key must not be nil and must implement
 *							the NSCopying protocol.
 *
 * @param anObject			The data object to insert, which must not be nil.
 * @param aKey				The key to bind the data object to, which must not be nil.
 */
- (void) setObject:(id)anObject forKey:(id)aKey;

// Call this when a node's value changes so that delegate callbacks will be made.
- (void) notifyValueChangedForKey:(id)aKey;

// Returns all nodes in path from node to root.
- (NSArray *)pathFromNode:(AATreeNode *)node;

// Returns the root node.
- (AATreeNode *)root;

@end
