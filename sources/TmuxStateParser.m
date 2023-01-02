//
//  TmuxStateParser.m
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxStateParser.h"

NSString *kStateDictSavedGrid = @"alternate_on";
// These are the cursor coords in the primary screen, valid only when in the alt screen.
// CSI ? 1049 h saves to this, CSI ? 1049 h restores from it. CSI ? 1048 h/l is not supported by
// tmux.
NSString *kStateDictAltSavedCX = @"alternate_saved_x";
NSString *kStateDictAltSavedCY = @"alternate_saved_y";

// This is the current screen's cursor position.
NSString *kStateDictCursorX = @"cursor_x";
NSString *kStateDictCursorY = @"cursor_y";
NSString *kStateDictScrollRegionUpper = @"scroll_region_upper";
NSString *kStateDictScrollRegionLower = @"scroll_region_lower";
NSString *kStateDictPaneId = @"pane_id";
NSString *kStateDictTabstops = @"pane_tabs";

// Cursor visible? (DECTCEM)
NSString *kStateDictCursorMode = @"cursor_flag";

// Insert mode?
NSString *kStateDictInsertMode = @"insert_flag";

// Application cursor mode (DECCKM)
NSString *kStateDictKCursorMode = @"keypad_cursor_flag";

// Corresponds to VT100Terminal's setKeypadMode:
NSString *kStateDictKKeypadMode = @"keypad_flag";
NSString *kStateDictWrapMode = @"wrap_flag";
NSString *kStateDictMouseStandardMode = @"mouse_standard_flag";
NSString *kStateDictMouseButtonMode = @"mouse_button_flag";
NSString *kStateDictMouseAnyMode = @"mouse_any_flag";
NSString *kStateDictMouseUTF8Mode = @"mouse_utf8_flag";
NSString *kStateDictMouseSGRMode = @"mouse_sgr_flag";  // tmux 3.1+

@interface NSString (TmuxStateParser)
- (NSArray *)intlistValue;
- (NSNumber *)numberValue;
- (NSNumber *)paneIdNumberValue;
@end

@implementation NSString (TmuxStateParser)

- (NSNumber *)paneIdNumberValue
{
    if ([self hasPrefix:@"%"] && [self length] > 1) {
        return [NSNumber numberWithInt:[[self substringFromIndex:1] intValue]];
    } else {
        NSLog(@"WARNING: Bogus pane id %@", self);
        return [NSNumber numberWithInt:-1];
    }
}

- (NSNumber *)numberValue
{
    return [NSNumber numberWithInt:[self intValue]];
}

- (NSArray *)intlistValue
{
    NSArray *components = [self componentsSeparatedByString:@","];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *s in components) {
        [result addObject:[NSNumber numberWithInt:[s intValue]]];
    }
    return result;
}

@end

@implementation TmuxStateParser

+ (NSString *)format {
    NSMutableString *format = [NSMutableString string];
    NSArray *theModes = @[
                         kStateDictPaneId, kStateDictSavedGrid, kStateDictAltSavedCX,
                         kStateDictAltSavedCY,
                         kStateDictCursorX, kStateDictCursorY, kStateDictScrollRegionUpper,
                         kStateDictScrollRegionLower, kStateDictTabstops, kStateDictCursorMode,
                         kStateDictInsertMode,
                         kStateDictKCursorMode, kStateDictKKeypadMode, kStateDictWrapMode,
                         kStateDictMouseStandardMode, kStateDictMouseButtonMode,
                         kStateDictMouseAnyMode, kStateDictMouseUTF8Mode, kStateDictMouseSGRMode ];
    for (NSString *value in theModes) {
        [format appendFormat:@"%@=#{%@}", value, value];
        if (value != [theModes lastObject]) {
            [format appendString:@"\t"];
        }
    }
    return format;
}

+ (TmuxStateParser *)sharedInstance
{
    static TmuxStateParser *instance;
    if (!instance) {
        instance = [[TmuxStateParser alloc] init];
    }
    return instance;
}

+ (NSMutableDictionary *)dictionaryForState:(NSString *)state
                           workAroundTabBug:(BOOL)workAroundTabBug {
    // State is a collection of key-value pairs. Each KVP is delimited by
    // newlines. The key is to the left of the first =, the value is to the
    // right.
    NSString *intType = @"numberValue";
    NSString *uintType = @"numberValue";
    NSString *intlistType = @"intlistValue";
    NSString *paneIdNumberType = @"paneIdNumberValue";



    NSDictionary *fieldTypes = [NSDictionary dictionaryWithObjectsAndKeys:
                                intType, kStateDictSavedGrid,
                                intType, kStateDictCursorX,
                                intType, kStateDictCursorY,
                                intType, kStateDictAltSavedCX,
                                intType, kStateDictAltSavedCY,
                                uintType, kStateDictCursorMode,
                                uintType, kStateDictInsertMode,
                                uintType, kStateDictKCursorMode,
                                uintType, kStateDictKKeypadMode,
                                uintType, kStateDictMouseStandardMode,
                                uintType, kStateDictMouseButtonMode,
                                uintType, kStateDictMouseAnyMode,
                                uintType, kStateDictMouseUTF8Mode,
                                uintType, kStateDictMouseSGRMode,
                                uintType, kStateDictWrapMode,
                                uintType, kStateDictScrollRegionUpper,
                                uintType, kStateDictScrollRegionLower,
                                paneIdNumberType, kStateDictPaneId,
                                intlistType, kStateDictTabstops,
                                nil];

    NSArray *fields = [state componentsSeparatedByString:@"\t"];
    if (fields.count == 1 && workAroundTabBug) {
        fields = [state componentsSeparatedByString:@"\\t"];
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *kvp in fields) {
        NSRange eq = [kvp rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *key = [kvp substringToIndex:eq.location];
            NSString *value = [kvp substringFromIndex:eq.location + 1];
            NSString *converter = [fieldTypes objectForKey:key];
            if (converter) {
                SEL sel = NSSelectorFromString(converter);
                id convertedValue = [value performSelector:sel];
                [result setObject:convertedValue forKey:key];
            } else {
                [result setObject:value forKey:key];
            }
        } else if ([kvp length] > 0) {
            NSLog(@"Bogus result in control command: \"%@\"", kvp);
        }
    }
    return result;
}

- (NSMutableDictionary *)parsedStateFromString:(NSString *)stateLines
                                     forPaneId:(int)paneId
                              workAroundTabBug:(BOOL)workAroundTabBug {
    NSArray *states = [stateLines componentsSeparatedByString:@"\n"];
    for (NSString *state in states) {
        NSMutableDictionary *dict = [[self class] dictionaryForState:state workAroundTabBug:workAroundTabBug];
        NSNumber *paneIdNumber = [dict objectForKey:kStateDictPaneId];
        if (paneIdNumber && [paneIdNumber intValue] == paneId) {
            return dict;
        }
    }
    return [NSMutableDictionary dictionary];
}

@end
