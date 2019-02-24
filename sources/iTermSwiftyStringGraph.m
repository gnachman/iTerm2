//
//  iTermSwiftyStringGraph.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 23/02/19.
//

#import "iTermSwiftyStringGraph.h"

#import "iTermDirectedGraph.h"
#import "iTermSwiftyString.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"

@implementation iTermSwiftyStringGraph {
    iTermDirectedGraph<iTermVariableDesignator *> *_graph;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _graph = [[iTermDirectedGraph alloc] init];
    }
    return self;
}

- (void)addSwiftyString:(iTermSwiftyString *)swiftyString
         withFormatPath:(NSString *)formatPath
         evaluationPath:(NSString *)evaluationPath
                  scope:(nonnull iTermVariableScope *)scope {
    if (formatPath) {
        [self addEdgeFrom:[scope designatorForPath:formatPath]
                       to:[scope designatorForPath:evaluationPath]];
    }
    [swiftyString.refs enumerateObjectsUsingBlock:^(iTermVariableReference * _Nonnull ref, NSUInteger idx, BOOL * _Nonnull stop) {
        [self addEdgeFrom:[scope designatorForPath:ref.path]
                       to:[scope designatorForPath:evaluationPath]];
    }];
}

- (BOOL)containsCycle {
    return [[[iTermDirectedGraphCycleDetector alloc] initWithDirectedGraph:_graph] containsCycle];
}

- (void)addEdgeFromPath:(NSString *)fromPath
                 toPath:(NSString *)toPath
                  scope:(iTermVariableScope *)scope {
    [self addEdgeFrom:[scope designatorForPath:fromPath]
                   to:[scope designatorForPath:toPath]];
}

- (void)addEdgeFrom:(iTermVariableDesignator *)source to:(iTermVariableDesignator *)dest {
    if (source == nil || dest == nil) {
        return;
    }
    [_graph addEdgeFrom:source to:dest];
}

@end
