//
//  iTermStoplightHotbox.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermStoplightHotboxDelegate<NSObject>
- (BOOL)stoplightHotboxMouseEnter;
- (void)stoplightHotboxMouseExit;
- (NSColor *)stoplightHotboxColor;
- (NSColor *)stoplightHotboxOutlineColor;
- (BOOL)stoplightHotboxCanDrag;
@end

@interface iTermStoplightHotbox : NSView
@property (nonatomic, weak) id<iTermStoplightHotboxDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
