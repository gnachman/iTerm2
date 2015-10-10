//
//  iTermDirectoryTree.h
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import <Foundation/Foundation.h>

@class iTermDirectoryTreeNode;

@interface iTermDirectoryTree : NSObject {
    iTermDirectoryTreeNode *_root;
}

+ (NSMutableArray *)attributedComponentsInPath:(NSAttributedString *)path;
- (void)addPath:(NSString *)path;
- (NSIndexSet *)abbreviationSafeIndexesInPath:(NSString *)path;
- (void)removePath:(NSString *)path;

@end
