//
//  iTermEditKeyActionWindowController.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermEditKeyActionWindowController : NSWindowController

@property(nonatomic, copy) NSString *currentKeyCombination;
@property(nonatomic, copy) NSString *parameterValue;
@property(nonatomic, assign) int action;
@property(nonatomic, readonly) BOOL ok;

// Used by client to remember if this was opened to add a new mapping or edit an existing one.
@property(nonatomic, assign) BOOL isNewMapping;

@end
