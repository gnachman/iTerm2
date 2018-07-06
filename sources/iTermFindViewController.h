//
//  iTermFindViewController.h
//  iTerm2
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

@class iTermFindDriver;

// Never change these values as they are saved to user defaults.
typedef NS_ENUM(NSUInteger, iTermFindMode) {
    iTermFindModeSmartCaseSensitivity = 0,
    iTermFindModeCaseSensitiveSubstring = 1,
    iTermFindModeCaseInsensitiveSubstring = 2,
    iTermFindModeCaseSensitiveRegex = 3,
    iTermFindModeCaseInsensitiveRegex = 4,
};

@protocol iTermFindViewController<NSObject>

@property (nonatomic, readonly) BOOL searchBarIsFirstResponder;
@property (nonatomic, weak) iTermFindDriver *driver;
@property (nonatomic, copy) NSString *findString;

- (void)close;
- (void)open;
- (void)makeVisible;
- (void)setFrameOrigin:(NSPoint)p;
- (void)setProgress:(double)progress;
- (void)deselectFindBarTextField;

@end
