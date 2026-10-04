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

@property (nonatomic, readonly, nullable) NSString *script;
@property (nonatomic, readonly, nullable) NSString *module;
@property (nonatomic, readonly, nullable) NSString *statement;
@property (nonatomic, readonly) NSString *fullPythonPath;

@property (nonatomic, readonly, nullable) NSString *escapedScript;
@property (nonatomic, readonly, nullable) NSString *escapedModule;
@property (nonatomic, readonly, nullable) NSString *escapedStatement;
@property (nonatomic, readonly) NSString *escapedFullPythonPath;
@property (nonatomic, readonly) BOOL repl;

- (instancetype)initWithArgs:(NSArray<NSString *> *)args NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
