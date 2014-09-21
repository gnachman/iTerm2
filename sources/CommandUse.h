//
//  CommandUse.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Foundation/Foundation.h>

@class VT100ScreenMark;

@interface CommandUse : NSObject <NSCopying>

@property(nonatomic, assign) NSTimeInterval time;
@property(nonatomic, retain) VT100ScreenMark *mark;
@property(nonatomic, retain) NSString *directory;

+ (instancetype)commandUseFromSerializedValue:(NSArray *)serializedValue;
- (NSArray *)serializedValue;

@end
