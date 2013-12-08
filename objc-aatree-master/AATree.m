//
//  Implementation based on: http://www.eternallyconfuzzled.com/tuts/datastructures/jsw_tut_andersson.aspx
//

#import "AATree.h"

@interface AATree() // private methods.

@property(retain) AATreeNode *root;
@property(assign) NSUInteger count;
@property(copy) NSComparator keyComparator;

/*!
 * @abstract				Deletes the node bound to the specified key.
 * @discussion				The node is deleted by looking up the node with the
 *							specified key. The node is removed as in any binary
 *							search tree, with the added functionallity that the
 *							difference in levels between parent and child should
 *							be at most one. If it is more, this is fixed, which may
 *							lead to skew and split operations.
 */
- (AATreeNode *) __deleteNodeAtKey:(id)aKey atRoot:(AATreeNode *)aRoot;


/*!
 * @abstract				Insert the specified data in the AA tree.
 * @discussion				The data is inserted by looking up the correct leaf
 *							node, setting the node as the left or right child of
 *							the leaf. The function is recursive, so the skew and
 *							split operations are performed on all parents of the
 *							added node automatically. If a node with the same key
 *							as the new node is found, the data of the node is
 *							replaced with the new data.
 *
 * @param aRoot				The root node to add the new node.
 * @param aNode				The node to add.
 * @result					The possibly new root.
 */
- (AATreeNode *) __insertNode:(AATreeNode *)aNode atRoot:(AATreeNode *)aRoot;


/*!
 * @abstract				Lock the tree for reading.
 * @discussion				See the header file for more information on the current
 *							implementation of thread safety.
 */
- (void) __lockForReading;


/*!
 * @abstract				Lock the tree for writing.
 * @discussion				See the header file for more information on the current
 *							implementation of thread safety.
 */
- (void) __lockForWriting;


/*!
 * @abstract				Retrieves the node bound to the specified key.
 * @discussion				This function uses the key comparator, as specified on
 *							initialization of the tree.
 *
 * @param aKey				The key to look for.
 * @result					An AATreeNode pointer.
 */
- (AATreeNode *) __nodeAtKey:(id)aKey;


/*!
 * @abstract				Retrieves the node which comes closest to the specified key.
 * @discussion				This function uses the key comparator, as specified on
 *							initialization of the tree. The returned node's key won't
 *							surpass the specified key. If no node with a key lower than
 *							the specified key can be found, nil is returned. This function
 *							performs its operation recursive.
 *
 * @param aKey				The key to look for.
 * @param aRoot				The root to search from.
 * @result					An AATreeNode pointer.
 */
- (AATreeNode *) __nodeClosestToKey:(id)aKey atRoot:(AATreeNode *)aRoot;


/*!
 * @abstract				Performs a recursive skew operation.
 * @discussion				This function makes sure that every violation of the first
 *							balance rule, which states that no left horizontal logical links
 *							are allowed, are fixed. It does this by rotating right at the
 *							parent of the left horizontal logical link.
 *
 * @param aRoot				The root node to check.
 * @result					The possibly new root after the skew, or the same if nothing
 *							has been skewed.
 */
- (AATreeNode *) __skew:(AATreeNode *)aRoot;


/*!
 * @abstract				Performs a recursive split operation.
 * @discussion				This function makes sure that every violation of the second
 *							balance rule, which states that no two consecutive right
 *							horizontal logical links are allowed, are fixed. It does this
 *							by rotating left and increasing the level of the parent.
 *
 * @param aRoot				The root node to check.
 * @result					The possibly new root after the split, or the same if nothing
 *							has been split.
 */
- (AATreeNode *) __split:(AATreeNode *)aRoot;


/*!
 * @abstract				Unlock the lock securing thread safety.
 */
- (void) __unlock;

@end


@implementation AATree

// --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
// -- public methods --
// --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

- (id) initWithKeyComparator:(NSComparator)aKeyComparator {
	
	if (self = [super init]) {
		keyComparator = [aKeyComparator copy];
		pthread_rwlock_init(&rwLock, NULL);
	}
	return self;
}


- (id) init {
	
	@throw [NSException exceptionWithName:@"MethodNotAllowedException" reason:@"Initialize an AATree with the 'initWithKeyComparator:' method." userInfo:nil];
}


- (id) copyWithZone:(NSZone *)zone {
	
	AATree *copy = [[AATree alloc] initWithKeyComparator:keyComparator];
	
	[self __lockForReading];
	copy.root = [[root copy] autorelease];
	copy.count = count;
	[self __unlock];
	
	return copy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p root=%@>", self.class, self, self.root];
}

- (void)setCount:(NSUInteger)newCount {
    count = newCount;
}

- (NSUInteger) count {
    
	return count;
}



- (NSEnumerator *) keyEnumerator {
	
	NSMutableArray *keys = [NSMutableArray arrayWithCapacity:count];
    
	[self __lockForReading];
	[root addKeyToArray:keys];
	[self __unlock];
    
	return [keys objectEnumerator];
}


- (id) objectClosestToKey:(id)aKey {
	
	[self __lockForReading];
	id object = [self __nodeClosestToKey:aKey atRoot:root].data;
	[self __unlock];
	
	return object;
}


- (id) objectForKey:(id)aKey {
	
	[self __lockForReading];
	id data = [self __nodeAtKey:aKey].data;
	[self __unlock];
    
	return data;
}


- (void) print {
	
	[root printWithIndent:0];
}


- (void) removeObjectForKey:(id)aKey {
    
	[self __lockForWriting];
    changedNodes = [[NSMutableSet alloc] init];
    AATreeNode *prevRoot = self.root;
	self.root = [self __deleteNodeAtKey:aKey atRoot:root];
    if (prevRoot != self.root) {
        if (self.root) {
            [changedNodes addObject:self.root];
        }
        if (prevRoot) {
            [changedNodes addObject:prevRoot];
        }
    }
    if (changedNodes.count > 0) {
        [_delegate aaTree:self didChangeSubtreesAtNodes:changedNodes];
    }
    [changedNodes release];
    changedNodes = nil;
	[self __unlock];
}


- (void) setObject:(id)anObject forKey:(id)aKey {
    
	NSParameterAssert(anObject);
	NSParameterAssert(aKey);
	NSAssert([aKey conformsToProtocol:@protocol(NSCopying)], @"The supplied key does not conform to the NSCopying protocol.");
	
	[self __lockForWriting];
    changedNodes = [[NSMutableSet alloc] init];
	AATreeNode *newNode = [[[AATreeNode alloc] initWithData:anObject boundToKey:[[aKey copy] autorelease]] autorelease];
    AATreeNode *prevRoot = self.root;
	self.root = [self __insertNode:newNode atRoot:root];
    if (prevRoot != self.root) {
        if (self.root) {
            [changedNodes addObject:self.root];
        }
        if (prevRoot) {
            [changedNodes addObject:prevRoot];
        }
    }
    if (changedNodes.count > 0) {
        [_delegate aaTree:self didChangeSubtreesAtNodes:changedNodes];
    }
    [changedNodes release];
    changedNodes = nil;
	[self __unlock];
}

- (void) notifyValueChangedForKey:(id)aKey {
    [_delegate aaTree:self didChangeValueAtNode:[self __nodeAtKey:aKey]];
}

- (NSArray *)pathFromNode:(AATreeNode *)node {
    NSMutableArray *parents = [NSMutableArray array];
    
    // Begin at the root of the tree.
    AATreeNode *current = root;
    
    // While still at a node, check whether we have found the correct node or
    // travel left or right.
    while (current) {
        [parents insertObject:current atIndex:0];
        NSComparisonResult compareResult = keyComparator(node.key, current.key);
        if (compareResult == NSOrderedSame)	return parents;
        else if (compareResult == NSOrderedAscending) current = current.left;
        else current = current.right;
    }
    
    // Nothing found, return nil.
    return nil;
}

- (void) dealloc
{
	[root release];
	[keyComparator release];
	[super dealloc];
}


// --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
// -- private methods --
// --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

@synthesize root;
@synthesize count;
@synthesize keyComparator;

- (AATreeNode *) __deleteNodeAtKey:(id)aKey atRoot:(AATreeNode *)aRoot {
    
	if (aRoot) {
		
		// If we found the correct node, remove it.
		NSComparisonResult compareResult = keyComparator(aKey, aRoot.key);
		if (compareResult == NSOrderedSame) {
			
			// Check whether we are at an easy to remove node (zero to one children) or
			// a more difficult node.
			if (aRoot.left && aRoot.right) {
				
				// Get the in-order predecessor (heir).
				AATreeNode *heir = aRoot.left;
				while (heir.right) heir = heir.right;
                
				// Replace the data.
				aRoot.key = heir.key;
				aRoot.data = heir.data;
				
				// Delete the in-order predecessor (heir).
				aRoot.left = [self __deleteNodeAtKey:aRoot.key atRoot:aRoot.left];
                [changedNodes addObject:aRoot];
                if (aRoot.left) {
                    [changedNodes addObject:aRoot.left];
                }
			} else if (aRoot.left) {
                aRoot.deleted = YES;
				aRoot = aRoot.left;
			} else {
                aRoot.deleted = YES;
				aRoot = aRoot.right; // which could be nil.
			}
			
			count--;
            
            // Otherwise, travel left or right.
		} else if (compareResult == NSOrderedAscending) {
            AATreeNode *prevLeft = aRoot.left;
			aRoot.left = [self __deleteNodeAtKey:aKey atRoot:aRoot.left];
            if (prevLeft != aRoot.left) {
                [changedNodes addObject:aRoot];
                [changedNodes addObject:prevLeft];
            }
		} else {
            AATreeNode *prevRight = aRoot.right;
			aRoot.right = [self __deleteNodeAtKey:aKey atRoot:aRoot.right];
            if (prevRight != aRoot.right) {
                [changedNodes addObject:aRoot];
                [changedNodes addObject:prevRight];
            }
		}
		
		// Check whether the levels or the children are not more than one
		// lower than the current.
		if (aRoot.left.level < aRoot.level - 1 || aRoot.right.level < aRoot.level - 1) {
			
			// Decrease the level by one.
			aRoot.level--;
			
			// Decrease the right child's level also, when it is higher than its parent.
			if (aRoot.right.level > aRoot.level) {
                aRoot.right.level = aRoot.level;
            }
			
            AATreeNode *prevRoot = aRoot;
			aRoot = [self __skew:aRoot];
            if (aRoot != prevRoot) {
                [changedNodes addObject:prevRoot];
                [changedNodes addObject:aRoot];
            }
            prevRoot = aRoot;
			aRoot = [self __split:aRoot];
            if (aRoot != prevRoot) {
                [changedNodes addObject:prevRoot];
                [changedNodes addObject:aRoot];
            }
		}
	}
	
	return aRoot;
}


- (AATreeNode *) __insertNode:(AATreeNode *)aNode atRoot:(AATreeNode *)aRoot {
    
	// If the root is not nil, we have not reached an empty child of a leaf node.
	if (aRoot) {
		
		// Decide which way to travel through the tree.
		NSComparisonResult compareResult = keyComparator(aNode.key, aRoot.key);
		
		// If the key of the new node is equal to the current root, just replace the data.
		if (compareResult == NSOrderedSame)	{
			aRoot.data = aNode.data;
            [changedNodes addObject:aRoot];
            // Otherwise, travel left or right through the tree.
		} else {
			if (compareResult == NSOrderedAscending) {
                aRoot.left = [self __insertNode:aNode atRoot:aRoot.left];
                [changedNodes addObject:aRoot];
                [changedNodes addObject:aRoot.left];
            } else {
                aRoot.right = [self __insertNode:aNode atRoot:aRoot.right];
                [changedNodes addObject:aRoot];
                [changedNodes addObject:aRoot.right];
            }
			
			// After the node has been added, skew and split the (possibly new) root.
			// Because of the recursive nature of this function, all parents of the
			// new node will get skewed and split, all the way up to the root of the tree.
            AATreeNode *prevRoot = aRoot;
			aRoot = [self __skew:aRoot];
            if (aRoot != prevRoot) {
                [changedNodes addObject:aRoot];
                [changedNodes addObject:prevRoot];
            }
            prevRoot = aRoot;
			aRoot = [self __split:aRoot];
            if (aRoot != prevRoot) {
                [changedNodes addObject:aRoot];
                [changedNodes addObject:prevRoot];
            }
		}
		
        // Otherwise, insert the node.
	} else {
		aRoot = aNode;
		count++;
	}
	
	return aRoot;
}


- (void) __lockForReading {
	
	pthread_rwlock_rdlock(&rwLock);
}


- (void) __lockForWriting {
	
	pthread_rwlock_wrlock(&rwLock);
}


- (AATreeNode *) __nodeAtKey:(id)aKey {
	
	// Begin at the root of the tree.
	AATreeNode *current = root;
	
	// While still at a node, check whether we have found the correct node or
	// travel left or right.
	while (current) {
		NSComparisonResult compareResult = keyComparator(aKey, current.key);
		if (compareResult == NSOrderedSame)	return current;
		else if (compareResult == NSOrderedAscending) current = current.left;
		else current = current.right;
	}
	
	// Nothing found, return nil.
	return nil;
}


- (AATreeNode *) __nodeClosestToKey:(id)aKey atRoot:(AATreeNode *)aRoot {
    
	// Start with no result.
	AATreeNode *result = nil;
	
	// If we are still at a node, compare it to the specified key.
	if (aRoot) {
		NSComparisonResult compareResult = keyComparator(aKey, aRoot.key);
		
		// If the keys are equal, we have found an exact match and we are done.
		if (compareResult == NSOrderedSame)	result = aRoot;
		
		// Otherwise, travel left or right until a leaf node is surpassed.
		else if (compareResult == NSOrderedAscending) result = [self __nodeClosestToKey:aKey atRoot:aRoot.left];
		else result = [self __nodeClosestToKey:aKey atRoot:aRoot.right];
        
		// If no result has been found lower in the tree, test whether this node
		// is the closest.
		if (!result && compareResult == NSOrderedDescending) result = aRoot;
	}
	
	return result;
}


- (AATreeNode *) __skew:(AATreeNode *)aRoot {
    
	if (aRoot) {
		
		// Check for a logical horizontal left link.
		if (aRoot.left.level == aRoot.level) {
			// Perform a right rotation.
			AATreeNode *save = aRoot;
			aRoot = aRoot.left;
			save.left = aRoot.right;
			aRoot.right = save;
		}
		// Skew the right side of the (new) root.
		aRoot.right = [self __skew:aRoot.right];
        [changedNodes addObject:aRoot];
	}
	
	return aRoot;
}


- (AATreeNode *) __split:(AATreeNode *)aRoot {
	
	// Check for a consecutive logical horizontal right link.
	if (aRoot && aRoot.right.right.level == aRoot.level) {
		// Perform a left rotation.
		AATreeNode *save = aRoot;
		aRoot = aRoot.right;
		save.right = aRoot.left;
		aRoot.left = save;
		
		// Increase the level of the new root.
		aRoot.level++;
        
		// Split the right side of the new root.
		aRoot.right = [self __split:aRoot.right];
        [changedNodes addObject:aRoot];
	}
	
	return aRoot;
}


- (void) __unlock {
	
	pthread_rwlock_unlock(&rwLock);
}

@end
