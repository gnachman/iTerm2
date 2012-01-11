//
//  SplitPanel.h
//  iTerm
//
//  Created by George Nachman on 8/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class ProfileListView;
@class PseudoTerminal;

@interface SplitPanel : NSWindowController {
    PseudoTerminal *parent_;
    IBOutlet NSTextField *label_;
    IBOutlet NSButton *splitButton_;
    BOOL isVertical_;
    IBOutlet ProfileListView *bookmarks_;
    NSString *guid_;
}

@property (nonatomic, retain) PseudoTerminal *parent;
@property (nonatomic, assign) BOOL isVertical;
@property (nonatomic, readonly) NSTextField *label;
@property (nonatomic, copy) NSString *guid;

+ (NSString *)showPanelWithParent:(PseudoTerminal *)parent isVertical:(BOOL)vertical;
- (IBAction)cancel:(id)sender;
- (IBAction)split:(id)sender;

@end
