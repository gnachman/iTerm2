//
//  TransferrableFileMenuItemViewController.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Cocoa/Cocoa.h>
#import "TransferrableFile.h"

@interface TransferrableFileMenuItemViewController : NSViewController

@property(nonatomic, retain) TransferrableFile *transferrableFile;
@property(nonatomic, retain) NSMenuItem *stopSubItem;
@property(nonatomic, retain) NSMenuItem *showInFinderSubItem;
@property(nonatomic, retain) NSMenuItem *removeFromListSubItem;
@property(nonatomic, retain) NSMenuItem *openSubItem;

- (instancetype)initWithTransferrableFile:(TransferrableFile *)transferrableFile;
- (void)update;
- (void)itemSelected:(id)sender;
- (NSTimeInterval)timeSinceLastStatusChange;

- (void)stop:(id)sender;
- (void)showInFinder:(id)sender;
- (void)removeFromList:(id)sender;
- (void)open:(id)sender;
- (void)getInfo:(id)sender;

@end
