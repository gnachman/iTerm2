//
//  iTermDoublyLinkedList.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/5/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermDoublyLinkedList<T>;

@interface iTermDoublyLinkedListEntry<T>: NSObject
@property (nullable, nonatomic, weak) iTermDoublyLinkedList<T> *dll;
@property (nullable, nonatomic, strong) iTermDoublyLinkedListEntry<T> *dllNext;
@property (nullable, nonatomic, strong) iTermDoublyLinkedListEntry<T> *dllPrevious;
@property (nonatomic, strong, readonly) T object;
- (instancetype)initWithObject:(T)object NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermDoublyLinkedList<T>: NSObject
@property (nullable, nonatomic, readonly) iTermDoublyLinkedListEntry<T> *first;
@property (nullable, nonatomic, readonly) iTermDoublyLinkedListEntry<T> *last;
@property (nonatomic, readonly) NSInteger count;

- (void)prepend:(iTermDoublyLinkedListEntry<T> *)object;
- (void)remove:(iTermDoublyLinkedListEntry<T> *)object;
@end

NS_ASSUME_NONNULL_END
