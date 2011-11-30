//
//  TmuxStateParser.h
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *kStateDictInAlternateScreen;
extern NSString *kStateDictBaseCursorX;
extern NSString *kStateDictBaseCursorY;
extern NSString *kStateDictCursorX;
extern NSString *kStateDictCursorY;
extern NSString *kStateDictScrollRegionUpper;
extern NSString *kStateDictScrollRegionLower;
extern NSString *kStateDictTabstops;
extern NSString *kStateDictHasSelection;
extern NSString *kStateDictHasRectangularSelection;
extern NSString *kStateDictSelectionStartX;
extern NSString *kStateDictSelectionStartY;
extern NSString *kStateDictSelectionEndX;
extern NSString *kStateDictSelectionEndY;
extern NSString *kStateDictDECSCCursorX;
extern NSString *kStateDictDECSCCursorY;

@interface TmuxStateParser : NSObject

+ (TmuxStateParser *)sharedInstance;
- (NSMutableDictionary *)parsedStateFromString:(NSString *)layout;

@end
