//
//  BulkCopyProfilePreferencesWindowController.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"

// These match the stable xib identifiers on the profiles tab view items (not
// their localized labels), so bulk copy works in every UI language.
extern NSString *const iTermBulkCopyIdentifierColors;
extern NSString *const iTermBulkCopyIdentifierText;
extern NSString *const iTermBulkCopyIdentifierWeb;
extern NSString *const iTermBulkCopyIdentifierWindow;
extern NSString *const iTermBulkCopyIdentifierTerminal;
extern NSString *const iTermBulkCopyIdentifierSession;
extern NSString *const iTermBulkCopyIdentifierKeys;
extern NSString *const iTermBulkCopyIdentifierAdvanced;


@interface BulkCopyProfilePreferencesWindowController : NSWindowController

// GUID to copy from. Set this before presenting the modal sheet.
@property(nonatomic, copy) NSString *sourceGuid;
@property(nonatomic, copy) NSArray *keysForColors;
@property(nonatomic, copy) NSArray *keysForText;
@property(nonatomic, copy) NSArray *keysForWeb;
@property(nonatomic, copy) NSArray *keysForWindow;
@property(nonatomic, copy) NSArray *keysForTerminal;
@property(nonatomic, copy) NSArray *keysForSession;
@property(nonatomic, copy) NSArray *keysForKeyboard;
@property(nonatomic, copy) NSArray *keysForAdvanced;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithWindow:(NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)windowNibName NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)windowNibName owner:(id)owner NS_UNAVAILABLE;
- (instancetype)initWithWindowNibPath:(NSString *)windowNibPath owner:(id)owner NS_UNAVAILABLE;

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                       profileTypes:(ProfileType)profileTypes;

// Maps a profile-preferences tab view item's stable xib identifier to the
// corresponding iTermBulkCopyIdentifier* constant, or nil if the tab has no
// bulk-copy category (e.g. the General tab). This is intentionally keyed on
// the language-independent xib identifier rather than the tab's localized
// label, so it works in every UI language.
+ (nullable NSString *)bulkCopyIdentifierForTabViewItemIdentifier:(nullable NSString *)tabViewItemIdentifier;

@end
