//
//  iTermUserDefaults.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kSelectionRespectsSoftBoundariesKey;

@interface iTermUserDefaults : NSObject

@property (class, nonatomic, copy) NSArray<NSString *> *searchHistory;
@property (class, nonatomic) BOOL secureKeyboardEntry;

typedef NS_ENUM(NSUInteger, iTermAppleWindowTabbingMode) {
    iTermAppleWindowTabbingModeAlways,
    iTermAppleWindowTabbingModeFullscreen,
    iTermAppleWindowTabbingModeManual
};

@property (class, nonatomic, readonly) iTermAppleWindowTabbingMode appleWindowTabbingMode;
@property (class, nonatomic) BOOL haveBeenWarnedAboutTabDockSetting;

@end

NS_ASSUME_NONNULL_END
