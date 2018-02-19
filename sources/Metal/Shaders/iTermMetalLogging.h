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
                      constant int *values,
                      int count);

    void LogStringFloat(bool enabled,
                        device iTermMetalDebugBuffer *buffer,
                        constant char *message,
                        constant float *values,
                        int count);
}

