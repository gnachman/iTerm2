// -*- mode:objc -*-
// $Id: Tree.h,v 1.4 2008-09-18 18:03:05 yfabian Exp $
//
/*
 **  Tree.h
 **
 **  Copyright (c) 2002-2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Headertree structure for bookmarks. 
 **				  Adapted from Apple's example code.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Foundation/Foundation.h>

@interface NSArray (MyExtensions)
- (BOOL)containsObjectIdenticalTo: (id)object;
@end

@interface NSMutableArray (MyExtensions)
- (void) insertObjectsFromArray:(NSArray *)array atIndex:(int)index;
@end


@interface TreeNode : NSObject 
{
    TreeNode *nodeParent;
	BOOL isLeaf;
	NSMutableArray *nodeChildren;
    NSMutableDictionary *nodeData;
}
+ (id) treeFromDictionary:(NSDictionary*)dict;
- (id) initWithData:(NSDictionary *)data parent:(TreeNode*)parent children:(NSArray*)children;
- (id) initFromDictionary:(NSDictionary*)dict;
- (NSDictionary *) dictionary;

- (void)setNodeData:(NSDictionary *)data;
- (NSDictionary *) nodeData;

- (void)setNodeParent:(TreeNode*)parent;
- (TreeNode*)nodeParent;

- (BOOL) isLeaf;
- (void) setIsLeaf: (BOOL) flag;
- (BOOL)isGroup;

- (void)insertChild:(TreeNode*)child atIndex:(int)index;
- (void)insertChildren:(NSArray*)children atIndex:(int)index;
- (void)removeChild:(TreeNode*)child;
- (void)removeFromParent;

- (int)indexOfChild:(TreeNode*)child;
- (int)indexOfChildIdenticalTo:(TreeNode*)child;

- (int)numberOfChildren;
- (NSArray*)children;
- (TreeNode*)firstChild;
- (TreeNode*)lastChild;
- (TreeNode*)childAtIndex:(int)index;

- (BOOL)isDescendantOfNode:(TreeNode*)node;
    // returns YES if 'node' is an ancestor.

- (BOOL)isDescendantOfNodeInArray:(NSArray*)nodes;
    // returns YES if any 'node' in the array 'nodes' is an ancestor of ours.

- (void)recursiveSortChildren;
    // sort children using the compare: method in TreeNodeData
- (NSComparisonResult) compare: (id) comparator;

- (int) indexForNode: (id) node;
- (id) nodeForIndex: (int) index;

	// Returns the minimum nodes from 'allNodes' required to cover the nodes in 'allNodes'.
	// This methods returns an array containing nodes from 'allNodes' such that no node in
	// the returned array has an ancestor in the returned array.
+ (NSArray *)minimumNodeCoverFromNodesInArray: (NSArray *)allNodes;

@end
