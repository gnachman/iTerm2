//
//  BulkCopyProfilePreferencesWindowController.h
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import <Cocoa/Cocoa.h>

@interface BulkCopyProfilePreferencesWindowController : NSWindowController

// GUID to copy from. Set this before presenting the modal sheet.
@property(nonatomic, copy) NSString *sourceGuid;
@property(nonatomic, copy) NSArray *keysForColors;
@property(nonatomic, copy) NSArray *keysForText;
@property(nonatomic, copy) NSArray *keysForWindow;
@property(nonatomic, copy) NSArray *keysForTerminal;
@property(nonatomic, copy) NSArray *keysForSession;
@property(nonatomic, copy) NSArray *keysForKeyboard;
@property(nonatomic, copy) NSArray *keysForAdvanced;

@end
