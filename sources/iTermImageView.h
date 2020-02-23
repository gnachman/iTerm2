//
//  iTermImageView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/22/20.
//

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermImageView : NSView

@property (nonatomic, strong) NSImage *image;
@property (nonatomic) iTermBackgroundImageMode contentMode;
@property (nonatomic, strong) NSColor *backgroundColor;

@end

NS_ASSUME_NONNULL_END
