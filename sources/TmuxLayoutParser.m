//
//  TmuxLayoutParser.m
//  iTerm
//
//  Created by George Nachman on 11/28/11.
//

// Parse this syntax:

// layout ::= singleton | h-split | v-split
// singleton ::= width,height,x-offset,y-offset
// h-split ::= parent-width,parent-height-parent-x-offset,parent-y-offset{layout,layout-array}
// v-split ::= parent-width,parent-height-parent-x-offset,parent-y-offset[layout,layout-array]
// layout_array ::= layout,layout_array |

#import "TmuxLayoutParser.h"
#import "RegexKitLite.h"

NSString *kLayoutDictChildrenKey = @"children";
NSString *kLayoutDictWidthKey = @"width";
NSString *kLayoutDictHeightKey = @"height";
NSString *kLayoutDictXOffsetKey = @"x";
NSString *kLayoutDictYOffsetKey = @"y";
NSString *kLayoutDictNodeType = @"type";
NSString *kLayoutDictPixelWidthKey = @"px-width";
NSString *kLayoutDictPixelHeightKey = @"px-height";
NSString *kLayoutDictWindowPaneKey = @"window-pane";
NSString *kLayoutDictHistoryKey = @"history";
NSString *kLayoutDictAltHistoryKey = @"alt-history";
NSString *kLayoutDictStateKey = @"state";
NSString *kLayoutDictHotkeyKey = @"hotkey";
NSString *kLayoutDictTabOpenedManually = @"manual-open";
NSString *kLayoutDictTabColorKey = @"x-tab-color";

@implementation TmuxLayoutParser

+ (TmuxLayoutParser *)sharedInstance
{
    static TmuxLayoutParser *instance;
    if (!instance) {
        instance = [[TmuxLayoutParser alloc] init];
    }
    return instance;
}

// When a child has the same node type as its parent, add its children to
// the parent's children.
- (NSMutableDictionary *)coalescedTree:(NSMutableDictionary *)node
{
    int nodeType = [[node objectForKey:kLayoutDictNodeType] intValue];
    if (nodeType == kVSplitLayoutNode || nodeType == kHSplitLayoutNode) {
        NSSize size;
        size.width = [[node objectForKey:kLayoutDictWidthKey] intValue];
        size.height = [[node objectForKey:kLayoutDictHeightKey] intValue];
        NSArray *children = [node objectForKey:kLayoutDictChildrenKey];
        NSMutableArray *coalescedChildren = [NSMutableArray array];
        for (NSMutableDictionary *child in children) {
            // Recursively apply this algorithm to the child (does nothing if it's a leaf node)
            NSMutableDictionary *coalescedChild = [self coalescedTree:child];

            if ([[coalescedChild objectForKey:kLayoutDictNodeType] intValue] == nodeType) {
                // The child is a split of the same orientation as this node.
                // Iterate over its children (this node's grandchildren) and hoist each up to
                // be a child of this node.
                [coalescedChildren addObjectsFromArray:[coalescedChild objectForKey:kLayoutDictChildrenKey]];
            } else {
                // The child is not a splitter of the same orientation, so just add it.
                [coalescedChildren addObject:coalescedChild];
            }
        }
        // Done coalescing children--if at all--and replace our existing children
        // with the new ones.
        [node setObject:coalescedChildren forKey:kLayoutDictChildrenKey];
    }
    return node;
}

- (NSMutableDictionary *)parsedLayoutFromString:(NSString *)layout
{
    NSMutableArray *temp = [NSMutableArray array];
    if ([self parseLayout:layout range:NSMakeRange(5, layout.length - 5) intoTree:temp]) {
        NSMutableDictionary *tree = [temp objectAtIndex:0];
        if ([[tree objectForKey:kLayoutDictNodeType] intValue] == kLeafLayoutNode) {
            // Add a do-nothing root splitter so that the root is always a splitter.
            NSMutableDictionary *oldRoot = tree;
            tree = [[oldRoot mutableCopy] autorelease];
            tree[kLayoutDictNodeType] = @(kVSplitLayoutNode);
            tree[kLayoutDictChildrenKey] = @[ oldRoot ];
            [tree removeObjectForKey:kLayoutDictWindowPaneKey];
        }
        // Get the size of the window.
        NSArray *components = [layout captureComponentsMatchedByRegex:@"^[0-9a-fA-F]{4},([0-9]+)x([0-9]+),[0-9]+,[0-9]+[\\[{]"];
        if (components.count == 3) {
            tree[kLayoutDictWidthKey] = @([components[1] intValue]);
            tree[kLayoutDictHeightKey] = @([components[2] intValue]);
        }
        return [self coalescedTree:tree];
    } else {
        return nil;
    }
}

- (id)depthFirstSearchParseTree:(NSMutableDictionary *)parseTree
                callingSelector:(SEL)selector
                       onTarget:(id)target
                     withObject:(id)obj
{
    if ([[parseTree objectForKey:kLayoutDictNodeType] intValue] == kLeafLayoutNode) {
        return [target performSelector:selector withObject:parseTree withObject:obj];
    } else {
        for (NSMutableDictionary *child in [parseTree objectForKey:kLayoutDictChildrenKey]) {
            id ret = [self depthFirstSearchParseTree:child
                                     callingSelector:selector
                                            onTarget:target
                                          withObject:obj];
            if (ret) {
                return ret;
            }
        }
        return nil;
    }
}

- (NSMutableDictionary *)windowPane:(int)windowPane inParseTree:(NSMutableDictionary *)parseTree
{
    return [self depthFirstSearchParseTree:parseTree
                           callingSelector:@selector(searchParseTree:forWindowPane:)
                                  onTarget:self
                                withObject:[NSNumber numberWithInt:windowPane]];
}

- (NSArray *)windowPanesInParseTree:(NSDictionary *)parseTree
{
    NSMutableArray *result = [NSMutableArray array];
    if ([[parseTree objectForKey:kLayoutDictNodeType] intValue] == kLeafLayoutNode) {
        [result addObject:[NSNumber numberWithInt:[[parseTree objectForKey:kLayoutDictWindowPaneKey] intValue]]];
    } else {
        for (NSDictionary *child in [parseTree objectForKey:kLayoutDictChildrenKey]) {
            [result addObjectsFromArray:[self windowPanesInParseTree:child]];
        }
    }
    return result;
}

#pragma mark - Private

- (LayoutNodeType)nodeTypeInLayout:(NSString *)layout range:(NSRange)range
{
    NSRange squareRange = [layout rangeOfString:@"["
                                        options:0
                                          range:range];
    NSRange curlyRange = [layout rangeOfString:@"{"
                                       options:0
                                         range:range];
    if (squareRange.location == NSNotFound &&
        curlyRange.location == NSNotFound) {
        return kLeafLayoutNode;
    } else if (squareRange.location != NSNotFound &&
               curlyRange.location != NSNotFound) {
        if (squareRange.location < curlyRange.location) {
            return kHSplitLayoutNode;
        } else {
            return kVSplitLayoutNode;
        }
    } else if (squareRange.location != NSNotFound) {
        return kHSplitLayoutNode;
    } else {
        return kVSplitLayoutNode;
    }
}


- (NSMutableDictionary *)dictForLeafNodeInLayout:(NSString *)layout range:(NSRange)range
{
    NSArray *components = [layout captureComponentsMatchedByRegex:@"([0-9]+)x([0-9]+),([0-9]+),([0-9]+),?([0-9]+)?"
                                                          options:0
                                                            range:range
                                                            error:nil];
    if (components.count != 6 && components.count != 5) {
        NSLog(@"Matched wrong number of components in singleton layout \"%@\"", [layout substringWithRange:range]);
        return nil;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   [components objectAtIndex:1], kLayoutDictWidthKey,
                                   [components objectAtIndex:2], kLayoutDictHeightKey,
                                   [components objectAtIndex:3], kLayoutDictXOffsetKey,
                                   [components objectAtIndex:4], kLayoutDictYOffsetKey,
                                   [NSNumber numberWithInt:kLeafLayoutNode], kLayoutDictNodeType,
                                   nil];
    if (components.count == 6) {
        [result setObject:[NSNumber numberWithInt:[[components objectAtIndex:5] intValue]]
                   forKey:kLayoutDictWindowPaneKey];
    }
    return result;
}

- (NSRange)rangeOfChildrenInLayout:(NSString *)layout
                             range:(NSRange)range
                              open:(NSString *)openChar
                             close:(NSString *)closeChar
{
    NSRange openRange = [layout rangeOfString:openChar options:0 range:range];
    int count = 0;
    for (int i = openRange.location; i < range.location + range.length; i++) {
        unichar c = [layout characterAtIndex:i];
        if (c == '[' || c == '{') {
            ++count;
        } else if (c == ']' || c == '}') {
            --count;
            if (!count) {
                return NSMakeRange(openRange.location + 1, i - openRange.location - 1);
            }
        }
    }
    NSLog(@"Unbalanced braces in children in layout: %@", [layout substringWithRange:range]);
    return NSMakeRange(NSNotFound, 0);
}

- (NSMutableDictionary *)splitDictWithType:(LayoutNodeType)nodeType
{
    return [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:nodeType]
                                              forKey:kLayoutDictNodeType];

}

- (NSString *)splitOffFirstLayoutInLayoutArray:(NSString *)layouts rest:(NSMutableString *)rest
{
    if (!layouts.length) {
        return nil;
    }

    // 204x50,0,0[204x25,0,0,204x12,0,26,204x11,0,39{102x11,0,39,101x11,103,39[101x5,103,39,101x5,103,45{50x5,103,45,50x5,154,45}]}]

    // <width>x<height>,<x>,<y>,...
    // <parent-width>x<parent-height>,<parent-x>,<parent-y>{...}
    // <parent-width>x<parent-height>,<parent-x>,<parent-y>[...]
    // Tolerate an optional comma at the beginning
    NSArray *components = [layouts captureComponentsMatchedByRegex:@"^(?:,?)([0-9]+x[0-9]+,[0-9]+,[0-9]+(?:(?:,[0-9]+)?))(.*)"];
    if (components.count != 3) {
        NSLog(@"Wrong number of components in layouts array \"%@\"", layouts);
        return nil;
    }
    NSString *suffix = [components objectAtIndex:2];
    if ([suffix length] == 0) {
        // only item in array
        NSString *result = [[layouts copy] autorelease];
        [rest setString:@""];
        return result;
    } else {
        unichar c = [suffix characterAtIndex:0];
        if (c == ',') {
            // First item is a singleton
            [rest setString:[suffix substringWithRange:NSMakeRange(1, suffix.length - 1)]];
            return [components objectAtIndex:1];
        } else if (c == '[' || c == '{') {
            // Find matching close bracket/brace
            NSRange childrenRange = [self rangeOfChildrenInLayout:suffix
                                                            range:NSMakeRange(0, suffix.length)
                                                             open:c == '[' ? @"[" : @"{"
                                                            close:c == '[' ? @"]" : @"}"];
            int nextItemOffset = childrenRange.location + childrenRange.length + 1;
            [rest setString:[suffix substringWithRange:NSMakeRange(nextItemOffset,
                                                                   suffix.length - nextItemOffset)]];
            return [NSString stringWithFormat:@"%@%@",
                    [components objectAtIndex:1],
                    [suffix substringWithRange:NSMakeRange(childrenRange.location - 1,
                                                           childrenRange.length + 2)]];
        } else {
            NSLog(@"Bad layouts (c=%d): %@", (int) c, layouts);
            return nil;
        }
    }
}

- (BOOL)parseLayoutArray:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree
{
    // layout,layout,...
    NSMutableString *rest = [NSMutableString string];
    NSString *first = [self splitOffFirstLayoutInLayoutArray:[layout substringWithRange:range]
                                                        rest:rest];
    while (first) {
        if (![self parseLayout:first
                         range:NSMakeRange(0, first.length)
                      intoTree:tree]) {
            return NO;
        }
        first = [self splitOffFirstLayoutInLayoutArray:rest
                                                  rest:rest];
    }
    return YES;
}

- (BOOL)parseLayout:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree
{
    NSString *openChar = @"[";
    NSString *closeChar = @"]";
    LayoutNodeType nodeType = [self nodeTypeInLayout:layout range:range];
    NSDictionary *dict;
    switch (nodeType) {
        case kLeafLayoutNode:
            dict = [self dictForLeafNodeInLayout:layout range:range];
            if (!dict) {
                return NO;
            }
            [tree addObject:dict];
            break;

        case kVSplitLayoutNode:
            openChar = @"{";
            closeChar = @"}";
            // fall through
        case kHSplitLayoutNode: {
            NSRange childrenRange = [self rangeOfChildrenInLayout:layout
                                                            range:range
                                                             open:openChar
                                                            close:closeChar];
            NSMutableArray *children = [NSMutableArray array];
            NSMutableDictionary *splitDict = [self splitDictWithType:nodeType];
            if (!splitDict) {
                return NO;
            }
            if (![self parseLayoutArray:layout range:childrenRange intoTree:children]) {
                return NO;
            }
            [splitDict setObject:children forKey:kLayoutDictChildrenKey];
            [tree addObject:splitDict];
            break;
        }
    }
    return YES;
}


- (NSMutableDictionary *)searchParseTree:(NSMutableDictionary *)parseTree
                           forWindowPane:(NSNumber *)wp
{
    if ([[parseTree objectForKey:kLayoutDictWindowPaneKey] intValue] == [wp intValue]) {
        return parseTree;
    } else {
        return  nil;
    }
}

@end
