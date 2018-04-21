//
//  iTermAPIConnectionIdentifierController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/20/18.
//

#import <Foundation/Foundation.h>

@interface iTermAPIConnectionIdentifierController : NSObject

+ (instancetype)sharedInstance;
- (id)identifierForKey:(NSString *)key;

@end
