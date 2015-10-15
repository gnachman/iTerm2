#import <Cocoa/Cocoa.h>


@interface AATreeNode : NSObject <NSCopying>

// AA tree properties.
@property(retain) AATreeNode *left;
@property(retain) AATreeNode *right;
@property(assign) int level;
@property(assign) BOOL deleted;

// Data properties.
@property(retain) id data;
@property(retain) id key;


/*!
 * @abstract				Initializes the node using the specified data
 *							and binds this node to the specified key.
 * @discussion				The node will have level 1, which is the default
 *							when adding a node to the AA tree.
 *
 * @param aDataObject		The data to include in the node.
 * @param aKey				The key the node is bound to.
 * @result					An initialized node.
 */ 
- (id) initWithData:(id)aDataObject boundToKey:(id)aKey;


/*!
 * @abstract				Adds the node in-order to the specified array.
 */
- (void) addKeyToArray:(NSMutableArray *)anArray;


/*!
 * @abstract				Print the node using NSlog().
 * @discussion				First display the right child, using a bigger indent,
 *							then display the node itself, using the specified indent,
 *							and lastly display the left node, using a bigger indent.
 *
 * @param ident				The indent to use.
 */
- (void) printWithIndent:(int)indent;


@end
