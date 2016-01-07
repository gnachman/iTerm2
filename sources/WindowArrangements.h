//
//  ArrangementsDataSource.h
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ArrangementPreviewView.h"

@interface WindowArrangements : NSViewController <NSTableViewDataSource, NSTableViewDelegate> {
    IBOutlet NSTableColumn *defaultColumn_;
    IBOutlet NSTableColumn *titleColumn_;
    IBOutlet NSTableView *tableView_;
    IBOutlet ArrangementPreviewView *previewView_;
    IBOutlet NSButton *deleteButton_;
    IBOutlet NSButton *defaultButton_;
}

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
                       defaultShortcut:(NSString *)defaultShortcut;

- (IBAction)setDefault:(id)sender;
- (IBAction)deleteSelectedArrangement:(id)sender;

@end
