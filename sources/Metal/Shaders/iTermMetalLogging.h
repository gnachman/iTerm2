//
//  iTermMetalLogging.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

#import "iTermShaderTypes.h"

namespace MetalLogging {
    void LogString(bool enabled,
                   device iTermMetalDebugBuffer *buffer,
                   constant char *message);

    void LogStringInt(bool enabled,
                      device iTermMetalDebugBuffer *buffer,
                      constant char *message,
                      int value);

    void LogStringFloat(bool enabled,
                        device iTermMetalDebugBuffer *buffer,
                        constant char *message,
                        float value);
    void LogStringFloat4(bool enabled,
                        device iTermMetalDebugBuffer *buffer,
                        constant char *message,
                        float4 value);
}

