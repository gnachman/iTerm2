//
//  iTermWindowShortcutLabelTitlebarAccessoryViewController.h
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, iTermTitlebarStyle) {
    iTermTitlebarStyleRegular,
    iTermTitlebarStyleCompact,
    iTermTitlebarStyleMinimal,
    iTermTitlebarStyleNone
};

@interface iTermWindowShortcutLabelTitlebarAccessoryViewController : NSTitlebarAccessoryViewController

@property(nonatomic, assign) int ordinal;
@property(nonatomic, assign) BOOL isMain;
@property(nonatomic, assign) iTermTitlebarStyle titlebarStyle;

+ (NSString *)modifiersString;
+ (NSString *)stringForOrdinal:(int)ordinal deemphasized:(out BOOL *)deemphasized;
+ (iTermTitlebarStyle)titlebarStyleForWindowType:(int)windowType;

@end
