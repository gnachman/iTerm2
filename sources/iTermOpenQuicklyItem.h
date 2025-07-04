#import <Foundation/Foundation.h>

@class iTermLogoGenerator;
@class iTermOpenQuicklyTableCellView;
@class iTermVariableScope;
@protocol iTermGenericNamedMarkReading;
@class PTYSession;
@class NSMenuItem;

// Represents and item in the Open Quickly table.
@interface iTermOpenQuicklyItem : NSObject

// Globally unique identifier for represented object.
@property(nonatomic, copy) NSString *identifier;

// Title for table view (in large text)
@property(nonatomic, copy) NSAttributedString *title;

// Detail text for table view (in small text below title)
@property(nonatomic, retain) NSAttributedString *detail;

// How well this item matches the query. Just a non-negative number. Higher
// scores are better matches.
@property(nonatomic, assign) double score;

// The view. We have to hold on to this to change the text color for
// non-highlighted items. This is hacky :(
@property(nonatomic, retain) iTermOpenQuicklyTableCellView *view;

// Icon to display with item. Should be overridden by subclasses.
@property(nonatomic, readonly) NSImage *icon;

@end


@interface iTermOpenQuicklySessionItem : iTermOpenQuicklyItem

// Holds the session's colors and can create a logo with them as needed.
@property(nonatomic, retain) iTermLogoGenerator *logoGenerator;

@end

@interface iTermOpenQuicklyWindowItem : iTermOpenQuicklyItem
@end

@interface iTermOpenQuicklyProfileItem : iTermOpenQuicklyItem
@end

@interface iTermOpenQuicklyChangeProfileItem : iTermOpenQuicklyItem
@end

@interface iTermOpenQuicklyArrangementItem : iTermOpenQuicklyItem
@property (nonatomic) BOOL inTabs;
@end

@interface iTermOpenQuicklyHelpItem : iTermOpenQuicklyItem
@end

@interface iTermOpenQuicklyScriptItem : iTermOpenQuicklyItem
@end

@interface iTermOpenQuicklyColorPresetItem : iTermOpenQuicklyItem
// Holds the session's colors and can create a logo with them as needed.
@property(nonatomic, retain) iTermLogoGenerator *logoGenerator;
@property(nonatomic, copy) NSString *presetName;
@end

@class iTermAction;
@interface iTermOpenQuicklyActionItem : iTermOpenQuicklyItem
@property(nonatomic, strong) iTermAction *action;
@end

@class iTermSnippet;
@interface iTermOpenQuicklySnippetItem : iTermOpenQuicklyItem
@property(nonatomic, strong) iTermSnippet *snippet;
@end

NS_AVAILABLE_MAC(11_0)
@interface iTermOpenQuicklyInvocationItem : iTermOpenQuicklyItem
@property(nonatomic, strong) iTermVariableScope *scope;
@end

@interface iTermOpenQuicklyNamedMarkItem: iTermOpenQuicklyItem
@property(nonatomic, strong) id<iTermGenericNamedMarkReading> namedMark;
@property(nonatomic, weak) PTYSession *session;
@end

@interface iTermOpenQuicklyMenuItem: iTermOpenQuicklyItem
@property(nonatomic, strong) NSMenuItem *menuItem;
@property(nonatomic, readonly) BOOL valid;
@end

@interface iTermOpenQuicklyBookmarkItem: iTermOpenQuicklyItem
@property(nonatomic, copy) NSString *bookmarkName;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, copy) NSString *userID;
@end

@interface iTermOpenQuicklyURLItem: iTermOpenQuicklyItem
@property(nonatomic, strong) NSURL *url;
@end

