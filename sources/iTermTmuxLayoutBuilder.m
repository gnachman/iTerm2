//
//  iTermTmuxLayoutBuilder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/19.
//

// layout ::= checksum ',' info
// info ::= leaf-info | inner-info
// leaf-info ::= width 'x' height ',' xoff ',' yoff ',' 'wp-id'
// inner-info ::= width 'x' height ',' xoff ',' yoff childrenInfo
// childrenInfo ::= horizontal-childrenInfo | vertical-childrenInfo
// horizontal-childrenInfo ::= '[' siblings ']'
// vertical-childrenInfo ::= '{' siblings '}'
// siblings ::= info | info ',' siblings

#import "iTermTmuxLayoutBuilder.h"

#import "NSArray+iTerm.h"

@interface iTermTmuxLayoutBuilderNode ()
@property (nonatomic) VT100GridSize size;
@property (nonatomic) VT100GridCoord offset;
@property (nonatomic, readonly) NSString *info;
- (void)update;
@end

@implementation iTermTmuxLayoutBuilderNode

- (void)update {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSString *)info {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@end

@implementation  iTermTmuxLayoutBuilderLeafNode {
    int _windowPane;
}

- (instancetype)initWithSessionOfSize:(VT100GridSize)size windowPane:(int)windowPane {
    self = [super init];
    if (self) {
        self.size = size;
        _windowPane = windowPane;
    }
    return self;
}

// leaf-info ::= width 'x' height ',' xoff ',' yoff ',' 'wp-id'
- (NSString *)info {
    return [NSString stringWithFormat:@"%@x%@,%@,%@,%@",
            @(self.size.width),
            @(self.size.height),
            @(self.offset.x),
            @(self.offset.y),
            @(_windowPane)];
}

- (void)update {
}

@end

@implementation iTermTmuxLayoutBuilderInteriorNode {
    BOOL _verticalDividers;
    NSMutableArray<iTermTmuxLayoutBuilderNode *> *_children;
}

- (instancetype)initWithVerticalDividers:(BOOL)verticalDividers {
    self = [super init];
    if (self) {
        _verticalDividers = verticalDividers;
        _children = [NSMutableArray array];
    }
    return self;
}

- (void)addNode:(iTermTmuxLayoutBuilderNode *)node {
    [_children addObject:node];
}

// inner-info ::= width 'x' height ',' xoff ',' yoff childrenInfo
- (NSString *)info {
    VT100GridSize size = self.size;
    VT100GridCoord offset = self.offset;
    NSString *children = [self childrenInfo];
    return [NSString stringWithFormat:@"%@x%@,%@,%@%@",
            @(size.width),
            @(size.height),
            @(offset.x),
            @(offset.y),
            children];
}

// childrenInfo ::= horizontal-childrenInfo | vertical-childrenInfo
// horizontal-childrenInfo ::= '[' siblings ']'
// vertical-childrenInfo ::= '{' siblings '}'
- (NSString *)childrenInfo {
    if (_verticalDividers) {
        return [NSString stringWithFormat:@"{%@}", self.siblings];
    } else {
        return [NSString stringWithFormat:@"[%@]", self.siblings];
    }
}

// siblings ::= info | info ',' siblings
- (NSString *)siblings {
    return [[_children mapWithBlock:^id(iTermTmuxLayoutBuilderNode *child) {
        return [child info];
    }] componentsJoinedByString:@","];
}

- (void)updateChildren {
    for (iTermTmuxLayoutBuilderNode *obj in _children) {
        [obj update];
    }
}

- (void)updateOffsets {
    VT100GridCoord offset = self.offset;
    for (iTermTmuxLayoutBuilderNode *obj in _children) {
        obj.offset = offset;
        if (_verticalDividers) {
            offset.x += obj.size.width + 1;
        } else {
            offset.y += obj.size.height + 1;
        }
    }
}

- (void)updateSize {
    VT100GridSize size = VT100GridSizeMake(0, 0);
    for (iTermTmuxLayoutBuilderNode *obj in _children) {
        if (_verticalDividers) {
            size.width += obj.size.width;
            size.height = MAX(size.height, obj.size.height);
            if (obj != _children.firstObject) {
                size.width += 1;
            }
        } else {
            size.width = MAX(size.width, obj.size.width);
            size.height += obj.size.height;
            if (obj != _children.firstObject) {
                size.height += 1;
            }
        }
    }
    self.size = size;
}

- (void)update {
    [self updateChildren];
    [self updateOffsets];
    [self updateSize];
}

@end

@implementation iTermTmuxLayoutBuilder {
    iTermTmuxLayoutBuilderNode *_root;
}

- (instancetype)initWithRootNode:(iTermTmuxLayoutBuilderNode *)node {
    self = [super init];
    if (self) {
        _root = node;
    }
    return self;
}

- (NSString *)layoutString {
    [_root update];
    NSString *info = [self info];
    NSString *checksum = [self checksumForLayout:info];
    return [NSString stringWithFormat:@"%@,%@", checksum, info];
}

- (VT100GridSize)clientSize {
    [_root update];
    return _root.size;
}

// info ::= leaf-info | inner-info
- (NSString *)info {
    return _root.info;
}

- (NSString *)checksumForLayout:(NSString *)layoutString {
    const char *layout = layoutString.UTF8String;
    u_short csum;
    
    csum = 0;
    for (; *layout != '\0'; layout++) {
        csum = (csum >> 1) + ((csum & 1) << 15);
        csum += *layout;
    }
    return [NSString stringWithFormat:@"%04hx", csum];
}

@end
