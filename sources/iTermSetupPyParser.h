//
//  iTermSetupPyParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import <Foundation/Foundation.h>

// This thing is a hack to avoid running excutable code while installing a script. The user has to
// have a chance to inspect what they installed before it has the chance to do any damage.
// It wants a install_requires=[...] all one one line containing a list of strings quoted with '
// or " and delimited by commas. Version numbers aren't supported, but that could be added later.
@interface iTermSetupPyParser : NSObject

@property (nonatomic, readonly) NSArray<NSString *> *dependencies;

// error in computing dependencies. Check this if dependencies is nil.
@property (nonatomic, readonly) NSError *dependenciesError;

@property (nonatomic, readonly) NSString *content;

- (instancetype)initWithPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end
