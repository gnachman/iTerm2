//
//  VT100DCSParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"
#import "iTermParser.h"
#import "CVector.h"

NS_ASSUME_NONNULL_BEGIN

@protocol VT100DCSParserHook<NSObject>

@property(nonatomic, readonly) NSString *hookDescription;

typedef NS_ENUM(NSUInteger, VT100DCSParserHookResult) {
    // Can't continue until new input arrives.
    VT100DCSParserHookResultBlocked,

    // May have done a partial read. Check again. (formerly NO)
    VT100DCSParserHookResultCanReadAgain,

    // Totally broken. Unhook the parser.  (formerly YES)
    VT100DCSParserHookResultUnhook
};

// Return YES if it should unhook.
- (VT100DCSParserHookResult)handleInput:(iTermParserContext *)context
           support8BitControlCharacters:(BOOL)support8BitControlCharacters
                                  token:(VT100Token *)result;

@end

NS_INLINE BOOL isDCS(unsigned char *code, int len, BOOL support8BitControlCharacters) {
    if (support8BitControlCharacters && len >= 1 && code[0] == VT100CC_C1_DCS) {
        return YES;
    }
    return (len >= 2 && code[0] == VT100CC_ESC && code[1] == 'P');
}

typedef NS_ENUM(NSInteger, VT100DCSState) {
    // Initial state
    kVT100DCSStateEntry,

    // Intermediate bytes, usually zero or one punctuation marks.
    kVT100DCSStateIntermediate,

    // Semicolon-delimited numeric parameters
    kVT100DCSStateParam,

    // Waiting for terminator but failure is guaranteed.
    kVT100DCSStateIgnore,

    // Finished.
    kVT100DCSStateGround,

    // ESC after ground state.
    kVT100DCSStateEscape,

    // After ESC while in DCS.
    kVT100DCSStateDCSEscape,

    // Reading final byte or bytes.
    kVT100DCSStatePassthrough
};

@interface VT100DCSParser : NSObject

// Indicates if a hook is present. All input should be sent to the DCS Parser
// while hooked.
@property(nonatomic, readonly) BOOL isHooked;

// For debug logging; nil if no hook.
@property(nonatomic, readonly) NSString *hookDescription;

// Uniquely identifies this object so the main thread can avoid unhooking the wrong session.
@property(nonatomic, readonly, nullable) NSString *uniqueID;

- (void)decodeFromContext:(iTermParserContext *)context
                    token:(VT100Token *)result
                 encoding:(NSStringEncoding)encoding
               savedState:(NSMutableDictionary *)savedState;

// Reset to ground state, unhooking if needed.
- (void)reset;

- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelTmuxRecoveryMode;

- (void)startConductorRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelConductorRecoveryMode;

@end

// This is exposed for testing.
@interface VT100DCSParser (Testing)

@property(nonatomic, readonly) VT100DCSState state;
@property(nonatomic, readonly) NSArray *parameters;
@property(nonatomic, readonly) NSString *privateMarkers;
@property(nonatomic, readonly) NSString *intermediateString;
@property(nonatomic, readonly) NSString *data;

@end

NS_ASSUME_NONNULL_END

