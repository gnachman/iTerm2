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

NS_INLINE BOOL iTermFilterModeIsRegularExpression(iTermFindMode mode) {
    switch (mode) {
        case iTermFindModeSmartCaseSensitivity:
        case iTermFindModeCaseSensitiveSubstring:
        case iTermFindModeCaseInsensitiveSubstring:
            return NO;
        case iTermFindModeCaseSensitiveRegex:
        case iTermFindModeCaseInsensitiveRegex:
            return YES;
    }
    return NO;
}

@protocol iTermFindViewController<NSObject>

@property (nonatomic, readonly) BOOL searchBarIsFirstResponder;
@property (nonatomic, weak) iTermFindDriver *driver;
@property (nonatomic, copy) NSString *findString;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, readonly) BOOL filterIsVisible;
@property (nonatomic, readonly) BOOL searchIsVisible;
@property (nonatomic, readonly) BOOL shouldSearchAutomatically;
@property (nonatomic) BOOL hasLineRange;

- (void)close;
- (void)open;
- (void)makeVisible;
- (void)setOffsetFromTopRightOfSuperview:(NSSize)offset;
- (void)setProgress:(double)progress;
- (void)deselectFindBarTextField;
- (void)countDidChange;
- (void)toggleFilter;
- (void)setFilterHidden:(BOOL)filterHidden;
- (void)setFilterProgress:(double)progress;

@end

@protocol iTermFilterViewController<NSObject>
- (void)setFilterProgress:(double)progress;
@end

