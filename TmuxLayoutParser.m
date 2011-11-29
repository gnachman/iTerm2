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

@interface TmuxLayoutParser (Private)

- (LayoutNodeType)nodeTypeInLayout:(NSString *)layout range:(NSRange)range;
- (NSMutableDictionary *)dictForLeafNodeInLayout:(NSString *)layout range:(NSRange)range;
- (NSRange)rangeOfChildrenInLayout:(NSString *)layout
                             range:(NSRange)range
                              open:(NSString *)openChar
                             close:(NSString *)closeChar;
- (NSMutableDictionary *)splitDictWithType:(LayoutNodeType)nodeType;
- (NSString *)splitOffFirstLayoutInLayoutArray:(NSString *)layouts rest:(NSMutableString *)rest;
- (void)parseLayoutArray:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree;
- (void)parseLayout:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree;

@end

@implementation TmuxLayoutParser

+ (TmuxLayoutParser *)sharedInstance
{
    static TmuxLayoutParser *instance;
    if (!instance) {
        instance = [[TmuxLayoutParser alloc] init];
    }
    return instance;
}

- (NSMutableDictionary *)parsedLayoutFromString:(NSString *)layout
{
    NSMutableArray *temp = [NSMutableArray array];
    [self parseLayout:layout range:NSMakeRange(5, layout.length - 5) intoTree:temp];
    return [temp objectAtIndex:0];
}

- (id)depthFirstSearchParseTree:(NSMutableDictionary *)parseTree
                callingSelector:(SEL)selector
                       onTarget:(id)target
                     withObject:(id)obj
{
    if ([[parseTree objectForKey:kLayoutDictNodeType] intValue] == kLeafLayoutNode) {
        return [target performSelector:selector withObject:parseTree withObject:obj];
    } else {
        for (NSDictionary *child in [parseTree objectForKey:kLayoutDictChildrenKey]) {
            id ret = [target performSelector:selector withObject:parseTree withObject:obj];
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

@end

@implementation TmuxLayoutParser (Private)

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
            return kVSplitLayoutNode;
        } else {
            return kHSplitLayoutNode;
        }
    } else if (squareRange.location != NSNotFound) {
        return kVSplitLayoutNode;
    } else {
        return kHSplitLayoutNode;
    }
}


- (NSMutableDictionary *)dictForLeafNodeInLayout:(NSString *)layout range:(NSRange)range
{
    NSArray *components = [layout captureComponentsMatchedByRegex:@"([0-9]+)x([0-9]+),([0-9]+),([0-9]+),([0-9na]+)"
                                                          options:0
                                                            range:range
                                                            error:nil];
    if (components.count != 6) {
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
    if (![[components objectAtIndex:5] isEqualToString:@"na"]) {
        [result setObject:[components objectAtIndex:5] forKey:kLayoutDictWindowPaneKey];
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
    for (int i = openRange.location; i < range.length; i++) {
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
    // 204x50,0,0[204x25,0,0,204x12,0,26,204x11,0,39{102x11,0,39,101x11,103,39[101x5,103,39,101x5,103,45{50x5,103,45,50x5,154,45}]}]
    
    // <width>x<height>,<x>,<y>,...
    // <parent-width>x<parent-height>,<parent-x>,<parent-y>{...}
    // <parent-width>x<parent-height>,<parent-x>,<parent-y>[...]
    NSArray *components = [layouts captureComponentsMatchedByRegex:@"(^[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+)(.*)"];
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
            [rest setString:[components objectAtIndex:2]];
            return [components objectAtIndex:1];
        } else if (c == '[' || c == '{') {
            // Find matching close bracket/brace
            NSRange childrenRange = [self rangeOfChildrenInLayout:suffix
                                                            range:NSMakeRange(0, suffix.length)
                                                             open:c == '[' ? @"[" : @"{"
                                                            close:c == '[' ? @"]" : @"}"];
            int nextItemOffset = childrenRange.location + childrenRange.length + 2;
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

- (void)parseLayoutArray:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree
{
    // layout,layout,...
    NSMutableString *rest = [NSMutableString string];
    NSString *first = [self splitOffFirstLayoutInLayoutArray:[layout substringWithRange:range]
                                                        rest:rest];
    while (first) {
        [self parseLayout:first
                    range:NSMakeRange(0, first.length)
                 intoTree:tree];
        first = [self splitOffFirstLayoutInLayoutArray:rest
                                                  rest:rest];
    }
}

- (void)parseLayout:(NSString *)layout range:(NSRange)range intoTree:(NSMutableArray *)tree
{
    NSString *openChar = @"[";
    NSString *closeChar = @"]";
    LayoutNodeType nodeType = [self nodeTypeInLayout:layout range:range];
    switch (nodeType) {
        case kLeafLayoutNode:
            [tree addObject:[self dictForLeafNodeInLayout:layout range:range]];
            break;
            
        case kHSplitLayoutNode:
            openChar = @"{";
            closeChar = @"}";
            // fall through
        case kVSplitLayoutNode: {
            NSRange childrenRange = [self rangeOfChildrenInLayout:layout
                                                            range:range
                                                             open:openChar
                                                            close:closeChar];
            NSMutableArray *children = [NSMutableArray array];
            NSMutableDictionary *splitDict = [self splitDictWithType:nodeType];
            [self parseLayoutArray:layout range:childrenRange intoTree:children];
            [splitDict setObject:children forKey:kLayoutDictChildrenKey];
            [tree addObject:splitDict];
            break;
        }
    }
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
