//
//  iTermFakeUserDefaults.h
//  iTerm2
//
//  Created by George Nachman on 2/25/17.
//
//

#import <Foundation/Foundation.h>

@interface iTermFakeUserDefaults : NSUserDefaults

- (void)setFakeObject:(id)object forKey:(id)key;

@end
