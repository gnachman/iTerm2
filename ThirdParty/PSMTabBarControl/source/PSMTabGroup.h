//
//  PSMTabGroup.h
//  PSMTabBarControl
//
//  Interface the tab bar needs to render tab-group chips. The control
//  defines it; the owner (the window controller) supplies a data source
//  and the tab-group model conforms. This keeps the group model and its
//  ownership outside the vendored tab bar: the control never references
//  the concrete model types, only these protocols.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// A single tab group's display attributes, as the tab bar needs them to
// draw its chip. Membership (which tabs belong to the group) is not here;
// that is pushed per-tab via -setTabGroupIdentifier:forTabViewItem:.
@protocol PSMTabGroup <NSObject>
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSColor *color;
@end

// Supplies group definitions to the tab bar by identifier. The window
// controller owns the backing store and sets itself (or its registry) as
// the control's tabGroupDataSource; the control holds it weakly and only
// reads through it while laying out/drawing chips.
@protocol PSMTabGroupDataSource <NSObject>
- (nullable id<PSMTabGroup>)tabGroupWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
