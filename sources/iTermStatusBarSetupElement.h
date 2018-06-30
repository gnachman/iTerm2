//
//  iTermStatusBarSetupElement.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermStatusBarElementPasteboardType;

@interface iTermStatusBarSetupElement : NSObject<NSCopying, NSPasteboardWriting, NSPasteboardReading, NSCoding>

@property (nonatomic, readonly) id exemplar;
@property (nonatomic, readonly) NSString *shortDescription;
@property (nonatomic, readonly) NSString *detailedDescription;
@property (nonatomic, readonly) Class componentClass;

- (instancetype)initWithComponentClass:(Class)componentClass NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
