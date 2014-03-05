//
//  VT100Token.m
//  iTerm
//
//  Created by George Nachman on 3/3/14.
//
//

#import "VT100Token.h"
#import "DebugLogging.h"
#include <stdlib.h>

static iTermObjectPool *gPool;

@implementation VT100Token

+ (void)initialize {
    gPool = [[iTermObjectPool alloc] initWithClass:self collections:10 objectsPerCollection:100];
}

+ (instancetype)token {
    if (gDebugLogging) {
        static int i;
        if (i % 100000 == 0) {
            DLog(@"%@", gPool);
        }
        i++;
    }
    return (VT100Token *)[gPool pooledObject];
}

+ (instancetype)tokenForControlCharacter:(unsigned char)controlCharacter {
    VT100Token *token = (VT100Token *)[gPool pooledObject];
    token->type = controlCharacter;
    return token;
}

- (void)destroyPooledObject {
    if (csi) {
        free(csi);
        csi = NULL;
    }
    
    [_string release];
    _string = nil;
    
    [_kvpKey release];
    _kvpKey = nil;
    
    [_kvpValue release];
    _kvpValue = nil;
    
    [_data release];
    _data = nil;
    
    type = 0;
    code = 0;
    isControl = NO;
}

- (CSIParam *)csi {
    if (!csi) {
        csi = calloc(sizeof(*csi), 1);
    }
    return csi;
}

- (BOOL)startsTmuxMode {
    return type == DCS_TMUX;
}

- (BOOL)isAscii {
    return type == VT100_ASCIISTRING;
}

- (BOOL)isStringType {
    return (type == VT100_STRING || type == VT100_ASCIISTRING);
}

@end
