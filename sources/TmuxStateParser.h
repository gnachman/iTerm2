//
//  TmuxStateParser.h
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *kStateDictSavedGrid;
extern NSString *kStateDictAltSavedCX;
extern NSString *kStateDictAltSavedCY;
extern NSString *kStateDictCursorX;
extern NSString *kStateDictCursorY;
extern NSString *kStateDictScrollRegionUpper;
extern NSString *kStateDictScrollRegionLower;
extern NSString *kStateDictTabstops;
extern NSString *kStateDictCursorMode;
extern NSString *kStateDictInsertMode;
extern NSString *kStateDictKCursorMode;
extern NSString *kStateDictKKeypadMode;
extern NSString *kStateDictWrapMode;
extern NSString *kStateDictMouseStandardMode;
extern NSString *kStateDictMouseButtonMode;
extern NSString *kStateDictMouseAnyMode;
extern NSString *kStateDictMouseUTF8Mode;

@interface TmuxStateParser : NSObject

+ (NSString *)format;
+ (TmuxStateParser *)sharedInstance;
- (NSMutableDictionary *)parsedStateFromString:(NSString *)layout
                                     forPaneId:(int)paneId;

@end
