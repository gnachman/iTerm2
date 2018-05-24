//
//  ArrangementsDataSource.h
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ArrangementPreviewView.h"

@interface WindowArrangements : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

+ (WindowArrangements *)sharedInstance;

+ (int)count;

+ (void)setArrangement:(NSArray *)arrangement withName:(NSString *)name;

+ (BOOL)hasWindowArrangement:(NSString *)name;

+ (NSArray *)arrangementWithName:(NSString *)name;

+ (NSString *)defaultArrangementName;
- (NSArray *)defaultArrangement;

+ (void)makeDefaultArrangement:(NSString *)name;

+ (NSArray *)allNames;

+ (void)refreshRestoreArrangementsMenu:(NSMenuItem *)menuItem
                          withSelector:(SEL)selector
                       defaultShortcut:(NSString *)defaultShortcut
                            identifier:(NSString *)identifier;

+ (NSString *)nameForNewArrangement;

- (IBAction)setDefault:(id)sender;
- (IBAction)deleteSelectedArrangement:(id)sender;

@end
