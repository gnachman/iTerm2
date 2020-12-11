//
//  iTermImageView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/22/20.
//

#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"
#import "iTermSharedImageStore.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermImageView : NSView

@property (nonatomic, strong) iTermImageWrapper *image;
@property (nonatomic) iTermBackgroundImageMode contentMode;
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic) CGFloat blend;
@property (nonatomic) CGFloat transparency;

- (void)setAlphaValue:(CGFloat)alphaValue NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
