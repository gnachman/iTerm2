//
//  iTermDirectedGraph.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 23/02/19.
//

#import "iTermDirectedGraph.h"

@interface NSMutableDictionary (Graph)
- (void)addObject:(id)object toMutableSetWithKey:(id)key;
@end

@implementation NSMutableDictionary (Graph)

- (void)addObject:(id)object toMutableSetWithKey:(id)key {
    NSMutableSet *set = self[key];
    if (!set) {
        set = [NSMutableSet set];
        self[key] = set;
    }
    [set addObject:object];
}

@end

@implementation iTermDirectedGraph {
    NSMutableSet *_vertexes;
    NSMutableDictionary<id, NSMutableSet *> *_edges;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _vertexes = [NSMutableSet set];
        _edges = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addEdgeFrom:(id)fromVertex to:(id)toVertex {
    [_vertexes addObject:fromVertex];
    [_vertexes addObject:toVertex];
    [_edges addObject:toVertex toMutableSetWithKey:fromVertex];
}

@end

@implementation iTermDirectedGraphCycleDetector {
    iTermDirectedGraph *_graph;
    NSMutableSet *_unexploredVertexes;
    NSMutableSet *_currentVertexes;
}

- (instancetype)initWithDirectedGraph:(iTermDirectedGraph *)directedGraph {
    self = [super init];
    if (self) {
        _graph = directedGraph;
    }
    return self;
}

- (BOOL)containsCycle {
    _unexploredVertexes = _graph.vertexes.mutableCopy;
    _currentVertexes = [NSMutableSet set];

    while (_unexploredVertexes.count) {
        if ([self searchForCycleBeginningAnywhere]) {
            return YES;
        }
        assert(_currentVertexes.count == 0);
    }
    return NO;
}

- (BOOL)searchForCycleBeginningAnywhere {
    id start = _unexploredVertexes.anyObject;
    assert(start);
    return [self searchFrom:start];
}

- (BOOL)searchFrom:(id)current {
    if ([_currentVertexes containsObject:current]) {
        return YES;
    }
    [_currentVertexes addObject:current];
    [_unexploredVertexes removeObject:current];
    for (id child in _graph.edges[current]) {
        if ([self searchFrom:child]) {
            return YES;
        }
    }
    [_currentVertexes removeObject:current];
    return NO;
}

@end
