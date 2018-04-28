//
//  iTermPythonRuntimeDownloader.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/28/18.
//

#import <Foundation/Foundation.h>

@interface iTermPythonRuntimeDownloader : NSObject

// Returns the path of the standard python binary.
@property (nonatomic, readonly) NSString *pathToStandardPyenvPython;

// Returns the path of the standard pyenv folder.
@property (nonatomic, readonly) NSString *pathToStandardPyenv;

+ (instancetype)sharedInstance;

- (void)downloadOptionalComponentsIfNeededWithCompletion:(void (^)(void))completion;

// Returns the path of the python binary given a root directory having a pyenv.
- (NSString *)pyenvAt:(NSString *)root;

@end
