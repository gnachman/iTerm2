//
//  TmuxLayoutParser.h
//  iTerm
//
//  Created by George Nachman on 11/28/11.
//

#import <Cocoa/Cocoa.h>

// Trees consist of arrays of dictionaries. The dictionaries have these keys defined:
// All nodes:
extern NSString *kLayoutDictNodeType;     // Node type from enum LayoutNodeType. NSNumber.

// Intermediate nodes only:
extern NSString *kLayoutDictChildrenKey;  // Sub-tree. Returns an array.

// Leaf nodes only:
extern NSString *kLayoutDictWidthKey;     // Width of node. String. Use -intValue.
extern NSString *kLayoutDictHeightKey;    // Height. String. Use -intValue.
extern NSString *kLayoutDictXOffsetKey;   // X position. String. Use -intValue.
extern NSString *kLayoutDictYOffsetKey;   // Y position. String. Use -intValue.
extern NSString *kLayoutDictWindowPaneKey;  // window pane number (leaf nodes only)

// These values are filled in by other classes:
extern NSString *kLayoutDictPixelWidthKey;
extern NSString *kLayoutDictPixelHeightKey;
extern NSString *kLayoutDictMaximumPixelWidthKey;  // Largest size with same number of cells
extern NSString *kLayoutDictMaximumPixelHeightKey;  // Largest size with same number of cells
extern NSString *kLayoutDictHistoryKey;       // Array of screen_char_t-filled NSData
extern NSString *kLayoutDictAltHistoryKey;    // Alternate screen history
extern NSString *kLayoutDictStateKey;         // see TmuxStateParser
extern NSString *kLayoutDictHotkeyKey;        // Session hotkey dictionary
extern NSString *kLayoutDictTabColorKey;      // Tab color
extern NSString *kLayoutDictFocusReportingKey;  // Focus reporting

// Children of leaf:
extern NSString *kLayoutDictTabOpenedManually;  // Was this tab opened by a user-initiated action?
extern NSString *kLayoutDictAllInitialWindowsAdded;  // Have we finished initial window loading?
extern NSString *kLayoutDictTabIndex;           // Which index the tab should have in the native window

typedef NS_ENUM(NSInteger, LayoutNodeType) {
    kLeafLayoutNode,
    kHSplitLayoutNode,
    kVSplitLayoutNode
};

@interface TmuxLayoutParser : NSObject

+ (instancetype)sharedInstance;
- (NSMutableDictionary *)parsedLayoutFromString:(NSString *)layout;
- (NSMutableDictionary *)windowPane:(int)windowPane
                        inParseTree:(NSMutableDictionary *)parseTree;
- (NSArray *)windowPanesInParseTree:(NSDictionary *)parseTree;

// For each leaf node, perform selector taking the NSMutableDictionary for the
// current node as the first arg and obj as the second arg. If it returns
// nil, the DFS continues; otherwise the DFS stops and that value is returned
// here.
- (id)depthFirstSearchParseTree:(NSMutableDictionary *)parseTree
                callingSelector:(SEL)selector
                       onTarget:(id)target
                     withObject:(id)obj;

@end
