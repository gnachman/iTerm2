//
//  iTermStatusBarSetupElement.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarLayout.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarSetupElement;

@protocol iTermStatusBarSetupElementDelegate<NSObject>

- (void)itermStatusBarSetupElementDidChange:(iTermStatusBarSetupElement *)element;

@end

extern NSString *const iTermStatusBarElementPasteboardType;

// Model for an item in the status bar collection view.
@interface iTermStatusBarSetupElement : NSObject<NSCopying, NSPasteboardWriting, NSPasteboardReading, NSCoding>

@property (nonatomic, readonly) NSString *shortDescription;
@property (nonatomic, readonly) NSString *detailedDescription;
@property (nonatomic, readonly) id<iTermStatusBarComponent> component;
@property (nonatomic, weak) id<iTermStatusBarSetupElementDelegate> delegate;

- (instancetype)initWithComponentFactory:(id<iTermStatusBarComponentFactory>)factory
                         layoutAlgorithm:(iTermStatusBarLayoutAlgorithmSetting)layoutAlgorithm
                                   knobs:(NSDictionary *)knobs;
- (instancetype)initWithComponent:(id<iTermStatusBarComponent>)component NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSAttributedString *)exemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor
                                        defaultFont:(NSFont *)font;

@end

NS_ASSUME_NONNULL_END
