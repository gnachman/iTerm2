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

@class PSMTabRichLine;

// A single tab group's display attributes, as the tab bar needs them to
// draw its chip. Membership (which tabs belong to the group) is not here;
// that is pushed per-tab via -setTabGroupIdentifier:forTabViewItem:.
@protocol PSMTabGroup <NSObject>
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSColor *color;
@optional
// The chip's tooltip, when it isn't the name.
@property (nonatomic, readonly, nullable) NSString *toolTip;
// A heading over tabs that go together rather than a group the user made.
// The bar draws it as a quiet line of text, with no color or outline, and
// draws its tabs as ungrouped.
@property (nonatomic, readonly) BOOL isSectionHeading;
// For a section heading, dimmer text before the name, such as the parent
// directory of the directory the name gives.
@property (nonatomic, readonly, nullable) NSString *detail;
@end

// Supplies group definitions to the tab bar by identifier. The window
// controller owns the backing store and sets itself (or its registry) as
// the control's tabGroupDataSource; the control holds it weakly and only
// reads through it while laying out/drawing chips.
@protocol PSMTabGroupDataSource <NSObject>
- (nullable id<PSMTabGroup>)tabGroupWithIdentifier:(NSString *)identifier;

@optional
// The icon a collapsed group's chip shows on behalf of its hidden members
// (for example the status dot or bell of the member that most needs the
// user), or nil when none does. The control calls this while drawing a
// collapsed chip; it reserves room for the icon whether or not there is one,
// so the chip's width never changes when attention comes and goes.
- (nullable NSImage *)tabGroupAttentionImageWithIdentifier:(NSString *)identifier;

// Whether collapsed groups' chips show rich content lines. When YES, a
// collapsed chip on a vertical bar is as tall as a tab.
- (BOOL)tabGroupsShowRichContent;

// Rich content lines a collapsed group's chip shows on behalf of its hidden
// members, below the group's name, or nil to show only the name. The number
// of lines must not depend on what the members show, since it sets the
// chip's height on a vertical bar.
- (nullable NSArray<PSMTabRichLine *> *)tabGroupRichLinesWithIdentifier:(NSString *)identifier;

// Lines with no text, one for each line a collapsed chip shows, sized as
// tabGroupRichLinesWithIdentifier: sizes them, or nil when chips show no
// lines. The control sizes collapsed chips with these so layout doesn't
// have to combine every group's content. Called often, so keep it cheap.
- (nullable NSArray<PSMTabRichLine *> *)tabGroupRichLinesForSizing;
@end

NS_ASSUME_NONNULL_END
