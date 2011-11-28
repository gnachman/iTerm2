//
//  TmuxLayoutParser.h
//  iTerm
//
//  Created by George Nachman on 11/28/11.
//

#import <Cocoa/Cocoa.h>

// Trees consist of arrays of dictionaries. The dictionaries have these keys defined:
extern NSString *kLayoutDictChildrenKey;  // Sub-tree. Returns an array.
extern NSString *kLayoutDictWidthKey;     // Width of node. String. Use -intValue.
extern NSString *kLayoutDictHeightKey;    // Height. String. Use -intValue.
extern NSString *kLayoutDictXOffsetKey;   // X position. String. Use -intValue.
extern NSString *kLayoutDictYOffsetKey;   // Y position. String. Use -intValue.
extern NSString *kLayoutDictNodeType;     // Node type from enum LayoutNodeType. NSNumber.

// These values are filled in by the client:
extern NSString *kLayoutDictPixelWidthKey;
extern NSString *kLayoutDictPixelHeightKey;
extern NSString *kLayoutDictWindowPaneKey;

typedef enum {
    kLeafLayoutNode,
    kHSplitLayoutNode,
    kVSplitLayoutNode
} LayoutNodeType;

@interface TmuxLayoutParser : NSObject

+ (TmuxLayoutParser *)sharedInstance;
- (NSMutableDictionary *)parsedLayoutFromString:(NSString *)layout;

@end
