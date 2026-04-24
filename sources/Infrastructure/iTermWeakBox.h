//
//  iTermWeakBox.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/7/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermWeakBox<T>: NSObject

@property (nullable, nonatomic, readonly, weak) T object;

+ (instancetype)boxFor:(T)object;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface NSMutableArray<ObjectType>(WeakBox)
/// `object` is T, not a weak box, but array contains iTermWeakBox<T> *.
- (void)removeWeakBoxedObject:(id)object;
- (void)pruneEmptyWeakBoxes;
@end

NS_ASSUME_NONNULL_END
