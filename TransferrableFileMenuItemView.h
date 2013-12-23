//
//  TransferrableFileMenuItemView.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Cocoa/Cocoa.h>

@interface TransferrableFileMenuItemView : NSView

@property(nonatomic, copy) NSString *filename;
@property(nonatomic, assign) double size;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic, retain) NSProgressIndicator *progressIndicator;

@end
