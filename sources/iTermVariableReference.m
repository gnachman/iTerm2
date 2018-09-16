//
//  iTermVariableReference.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/12/18.
//

#import "iTermVariableReference.h"
#import "iTermVariables.h"
#import "NSObject+iTerm.h"

@interface iTermVariableReferenceLink : NSObject
@property (nonatomic, weak) iTermVariables *variables;
@property (nonatomic, copy) NSString *localPath;

+ (instancetype)linkToVariables:(iTermVariables *)variables localPath:(NSString *)localPath;

@end

@implementation iTermVariableReferenceLink

+ (instancetype)linkToVariables:(iTermVariables *)variables localPath:(NSString *)localPath {
    iTermVariableReferenceLink *link = [[iTermVariableReferenceLink alloc] init];
    link.variables = variables;
    link.localPath = localPath;
    return link;
}

@end

@implementation iTermVariableReference {
    NSMutableArray *_links;
}

- (instancetype)initWithPath:(NSString *)path
                       scope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _path = [path copy];
        _scope = scope;
        _links = [NSMutableArray array];

        [scope addLinksToReference:self];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p path=%@ numlinks=%@>", NSStringFromClass(self.class), self, _path, @(_links.count)];
}

- (id)value {
    return [_scope valueForVariableName:_path];
}

- (void)setValue:(id)value {
    [_scope setValue:value forVariableNamed:_path];
}

- (void)addLinkToVariables:(iTermVariables *)variables localPath:(NSString *)path {
    [_links addObject:[iTermVariableReferenceLink linkToVariables:variables localPath:path]];
}

- (void)removeAllLinks {
    for (iTermVariableReferenceLink *link in _links) {
        [link.variables removeLinkToReference:self path:link.localPath];
    }
    [_links removeAllObjects];
}

- (void)invalidate {
    [self removeAllLinks];
    [_scope addLinksToReference:self];
    [self valueDidChange];
}

- (void)valueDidChange {
    if (self.onChangeBlock) {
        self.onChangeBlock();
    }
}

@end
