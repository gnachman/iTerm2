//
//  iTermWindowShortcutLabelTitlebarAccessoryViewController.h
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermWindowShortcutLabelTitlebarAccessoryViewController : NSTitlebarAccessoryViewController

@property(nonatomic, assign) int ordinal;
@property(nonatomic, assign) BOOL isMain;

+ (NSString *)stringForOrdinal:(int)ordinal deempahsized:(out BOOL *)deemphasized;

@end
