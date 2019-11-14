//
//  NSIndexSet+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/19.
//

#import <AppKit/AppKit.h>


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSIndexSet (iTerm)

@property (nonatomic, readonly) NSArray<NSNumber *> *it_array;

@end

NS_ASSUME_NONNULL_END
