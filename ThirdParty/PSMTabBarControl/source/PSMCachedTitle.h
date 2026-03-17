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

/// Protocol for looking up fonts for Private Use Area code points.
/// This allows different PUA ranges to use different fonts (e.g., nerd font bundles).
@protocol PSMPUAFontProvider <NSObject>
- (NSFont *)fontForPUACodePoint:(UTF32Char)codePoint;
@end


@interface PSMCachedTitleInputs: NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic) NSLineBreakMode truncationStyle;
@property (nonatomic, strong) NSColor *color;
@property (nullable, nonatomic, strong) NSImage *graphic;
@property (nonatomic) PSMTabBarOrientation orientation;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) BOOL parseHTML;
@property (nullable, nonatomic, weak) id<PSMPUAFontProvider> puaFontProvider;

- (instancetype)initWithTitle:(NSString *)title
              truncationStyle:(NSLineBreakMode)truncationStyle
                        color:(NSColor *)color
                      graphic:(nullable NSImage *)graphic
                  orientation:(PSMTabBarOrientation)orientation
                     fontSize:(CGFloat)fontSize
                    parseHTML:(BOOL)parseHTML
              puaFontProvider:(nullable id<PSMPUAFontProvider>)puaFontProvider NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Applies fonts from a PUA font provider to Private Use Area characters in an attributed string.
/// @param attributedString The attributed string to modify
/// @param provider The font provider to query for PUA fonts
/// @param fontSize The point size to use for the PUA fonts
/// @return A new attributed string with PUA fonts applied, or the original if no changes needed
NSAttributedString *PSMApplyPUAFonts(NSAttributedString *attributedString,
                                     id<PSMPUAFontProvider> provider,
                                     CGFloat fontSize);

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
