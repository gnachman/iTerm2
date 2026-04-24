//
//  iTermDirectedGraph.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 23/02/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermDirectedGraph<T> : NSObject
@property (nonatomic, readonly) NSSet<T> *vertexes;
@property (nonatomic, readonly) NSDictionary<T, NSMutableSet *> *edges;

- (void)addEdgeFrom:(T)fromVertex to:(T)toVertex;
@end

@interface iTermDirectedGraphCycleDetector : NSObject
- (instancetype)initWithDirectedGraph:(iTermDirectedGraph *)directedGraph;
- (BOOL)containsCycle;
@end

NS_ASSUME_NONNULL_END
