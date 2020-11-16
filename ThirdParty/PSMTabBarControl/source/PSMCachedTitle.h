//
//  PSMCachedTitle.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/2/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int, PSMTabBarOrientation) {
    PSMTabBarHorizontalOrientation,
    PSMTabBarVerticalOrientation
};


@interface PSMCachedTitleInputs: NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic) NSLineBreakMode truncationStyle;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, strong) NSImage *graphic;
@property (nonatomic) PSMTabBarOrientation orientation;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) BOOL parseHTML;

- (instancetype)initWithTitle:(NSString *)title
              truncationStyle:(NSLineBreakMode)truncationStyle
                        color:(NSColor *)color
                      graphic:(NSImage *)graphic
                  orientation:(PSMTabBarOrientation)orientation
                     fontSize:(CGFloat)fontSize
                    parseHTML:(BOOL)parseHTML NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface PSMCachedTitle: NSObject
@property (nonatomic, readonly) PSMCachedTitleInputs *inputs;
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic, readonly) NSSize size;

- (instancetype)initWith:(PSMCachedTitleInputs *)inputs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSRect)boundingRectWithSize:(NSSize)size;
- (NSAttributedString *)attributedStringForcingLeftAlignment:(BOOL)forceLeft
                                           truncatedForWidth:(CGFloat)truncatingWidth;

@end

NS_ASSUME_NONNULL_END
