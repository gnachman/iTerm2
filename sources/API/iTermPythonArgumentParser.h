//
//  iTermPythonArgumentParser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermPythonArgumentParser : NSObject

@property (nonatomic, readonly) NSArray<NSString *> *args;

@property (nonatomic, readonly) NSString *script;
@property (nonatomic, readonly) NSString *module;
@property (nonatomic, readonly) NSString *statement;
@property (nonatomic, readonly) NSString *fullPythonPath;

@property (nonatomic, readonly) NSString *escapedScript;
@property (nonatomic, readonly) NSString *escapedModule;
@property (nonatomic, readonly) NSString *escapedStatement;
@property (nonatomic, readonly) NSString *escapedFullPythonPath;
@property (nonatomic, readonly) BOOL repl;

- (instancetype)initWithArgs:(NSArray<NSString *> *)args NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
