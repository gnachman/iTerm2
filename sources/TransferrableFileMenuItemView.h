//
//  TransferrableFileMenuItemView.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermProgressIndicator.h"

@interface TransferrableFileMenuItemView : NSView

@property(nonatomic, copy) NSString *filename;
@property(nonatomic, copy) NSString *subheading;
@property(nonatomic, assign) long long size;
@property(nonatomic, assign) long long bytesTransferred;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic, retain) iTermProgressIndicator *progressIndicator;
@property(nonatomic, assign) BOOL lastDrawnHighlighted;

@end
