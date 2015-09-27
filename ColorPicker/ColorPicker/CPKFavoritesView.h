#import <Cocoa/Cocoa.h>

@class CPKFavorite;

/** Shows a table of saved "favorite" colors. */
@interface CPKFavoritesView : NSScrollView

/**
 * Called when the selected favorite color changes.
 *
 * @param color The new color, or nil if no color is selected.
 */
@property(nonatomic, copy) void (^selectionDidChangeBlock)(NSColor *color);

/** Add a new favorite color. */
- (void)addFavorite:(CPKFavorite *)favorite;

/** Remove the current selection, if any. */
- (void)removeSelectedFavorites;

/** If an entry with the specified color exists, select it. */
- (void)selectColor:(NSColor *)color;

@end
