//
//  NSMenu+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 6/25/25.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMenu(iTermAdditions)
- (BOOL)it_selectMenuItemWithTitle:(NSString * _Nullable)title identifier:(NSString * _Nullable)identifier;

// Returns the immediate child item whose identifier matches, or nil. Unlike
// -itemWithTitle:, this is stable across localization because identifiers are
// not localized.
- (NSMenuItem * _Nullable)it_itemWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
