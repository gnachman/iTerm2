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

@end
