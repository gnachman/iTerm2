//
//  TmuxStateParser.m
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxStateParser.h"

NSString *kStateDictInAlternateScreen = @"in_alternate_screen";  // Deprecated: same as kStateDictSavedGrid below.
NSString *kStateDictSavedGrid = @"alternate_on";
NSString *kStateDictBaseCursorX = @"base_cursor_x";  // Deprecated: use saved_cx
NSString *kStateDictBaseCursorY = @"base_cursor_y";  // Deprecated: use saved_cy
NSString *kStateDictSavedCX = @"alternate_saved_x";
NSString *kStateDictSavedCY = @"alternate_saved_y";
NSString *kStateDictCursorX = @"cursor_x";
NSString *kStateDictCursorY = @"cursor_y";
NSString *kStateDictScrollRegionUpper = @"scroll_region_upper";
NSString *kStateDictScrollRegionLower = @"scroll_region_lower";
NSString *kStateDictPaneId = @"pane_id";
NSString *kStateDictTabstops = @"pane_tabs";
NSString *kStateDictDECSCCursorX = @"saved_cursor_x";
NSString *kStateDictDECSCCursorY = @"saved_cursor_y";
NSString *kStateDictCursorMode = @"cursor_flag";
NSString *kStateDictInsertMode = @"insert_flag";
NSString *kStateDictKCursorMode = @"keypad_cursor_flag";
NSString *kStateDictKKeypadMode = @"keypad_flag";
NSString *kStateDictWrapMode = @"wrap_flag";
NSString *kStateDictMouseStandardMode = @"mouse_standard_flag";
NSString *kStateDictMouseButtonMode = @"mouse_button_flag";
NSString *kStateDictMouseAnyMode = @"mouse_any_flag";
NSString *kStateDictMouseUTF8Mode = @"mouse_utf8_flag";

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
    NSArray *theModes = [NSArray arrayWithObjects:
                         kStateDictPaneId, kStateDictSavedGrid, kStateDictSavedCX, kStateDictSavedCY,
                         kStateDictCursorX, kStateDictCursorY, kStateDictScrollRegionUpper,
                         kStateDictScrollRegionLower, kStateDictTabstops, kStateDictDECSCCursorX,
                         kStateDictDECSCCursorY, kStateDictCursorMode, kStateDictInsertMode,
                         kStateDictKCursorMode, kStateDictKKeypadMode, kStateDictWrapMode,
                         kStateDictMouseStandardMode, kStateDictMouseButtonMode,
                         kStateDictMouseAnyMode, kStateDictMouseUTF8Mode, nil];
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
{
    // State is a collection of key-value pairs. Each KVP is delimited by
    // newlines. The key is to the left of the first =, the value is to the
    // right.
    NSString *intType = @"numberValue";
    NSString *uintType = @"numberValue";
    NSString *intlistType = @"intlistValue";
    NSString *paneIdNumberType = @"paneIdNumberValue";

    NSDictionary *fieldTypes = [NSDictionary dictionaryWithObjectsAndKeys:
                                intType, kStateDictInAlternateScreen,
                                intType, kStateDictSavedGrid,
                                uintType, kStateDictBaseCursorX,
                                uintType, kStateDictBaseCursorY,
                                uintType, kStateDictSavedCX,
                                uintType, kStateDictSavedCY,
                                uintType, kStateDictCursorX,
                                uintType, kStateDictCursorY,
                                uintType, kStateDictScrollRegionUpper,
                                uintType, kStateDictScrollRegionLower,
                                paneIdNumberType, kStateDictPaneId,
                                intlistType, kStateDictTabstops,
                                intType, kStateDictDECSCCursorX,
                                intType, kStateDictDECSCCursorY,
                                nil];

    NSArray *fields = [state componentsSeparatedByString:@"\t"];
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
{
    NSArray *states = [stateLines componentsSeparatedByString:@"\n"];
    for (NSString *state in states) {
        NSMutableDictionary *dict = [[self class] dictionaryForState:state];
        NSNumber *paneIdNumber = [dict objectForKey:kStateDictPaneId];
        if (paneIdNumber && [paneIdNumber intValue] == paneId) {
            return dict;
        }
    }
    return [NSMutableDictionary dictionary];
}

@end
