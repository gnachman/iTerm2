//
//  PopupModel.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Foundation/Foundation.h>

@class PopupEntry;

@interface PopupModel : NSObject <NSFastEnumeration>

@property (nonatomic, readonly) NSUInteger count;

- (instancetype)initWithMaxEntries:(int)maxEntries;
- (void)removeAllObjects;
- (void)addObject:(id)object;
- (void)addHit:(PopupEntry*)object;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfObject:(id)o;
- (void)sortByScore;
- (int)indexOfObjectWithMainValue:(NSString*)value;

@end
