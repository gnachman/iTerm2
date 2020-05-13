//
//  iTermTmuxSessionObject.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTmuxSessionObject : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int number;

- (iTermTmuxSessionObject *)copyWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
