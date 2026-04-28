//
//  iTermRightGutterPanelRegistry.h
//  iTerm2
//
//  Process-wide registry of right-gutter panel types. Panels register a
//  factory at app launch; SessionView's controller asks the registry which
//  panels to instantiate for a given profile and sums their widths into the
//  right-extra layout budget.
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"
#import "iTermRightGutterPanel.h"

NS_ASSUME_NONNULL_BEGIN

typedef id<iTermRightGutterPanel> _Nonnull (^iTermRightGutterPanelFactory)(void);

// Block returning the configured width for a panel type given a profile.
// Must be cheap; called on the layout-budget hot path. Return 0 to omit the
// panel from the budget without instantiating it.
typedef CGFloat (^iTermRightGutterPanelWidthProvider)(Profile *profile);

@interface iTermRightGutterPanelRegistry : NSObject

+ (instancetype)sharedInstance;

// Registration order is preserved and determines panel layout order
// (innermost-to-outermost in the gutter). A duplicate identifier replaces
// the previous registration.
- (void)registerPanelType:(NSString *)identifier
                  factory:(iTermRightGutterPanelFactory)factory
            widthProvider:(iTermRightGutterPanelWidthProvider)widthProvider;

// Identifiers, in registration order, that should be instantiated for the
// given profile. A panel is "enabled" if its widthProvider returns > 0.
- (NSArray<NSString *> *)enabledPanelIdentifiersForProfile:(Profile *)profile;

// Sum of widths over enabled panels for the given profile. Cheap; safe to
// call from +[PTYSession desiredRightExtraForProfile:].
- (CGFloat)totalWidthForProfile:(Profile *)profile;

// Lazily instantiate a panel by identifier. Returns nil if the identifier
// is not registered.
- (nullable id<iTermRightGutterPanel>)createPanelWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
