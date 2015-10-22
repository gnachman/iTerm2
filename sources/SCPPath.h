//
//  SCPPath.h
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import <Foundation/Foundation.h>

@interface SCPPath : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *username;

- (NSString *)stringValue;
- (NSURL *)URL;

@end
