//
//  iTermMetalLogging.metal
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

#include <metal_stdlib>
#include "iTermShaderTypes.h"

using namespace metal;

namespace {
    void NullTerminate(device iTermMetalDebugBuffer *buffer) {
        if (buffer->offset < buffer->capacity) {
            buffer->storage[buffer->offset] = 0;
        }
    }

    void ReverseChars(device iTermMetalDebugBuffer *buffer,
                      int location,
                      int length) {
        for (int i = 0; i < length / 2; i++) {
            char temp = buffer->storage[location + i];
            const size_t j = location + length - i - 1;
            buffer->storage[location + i] = buffer->storage[j];
            buffer->storage[j] = temp;
        }
    }

    void AppendChar(device iTermMetalDebugBuffer *buffer,
                    char c,
                    int reserve) {
        if (buffer->offset + reserve < buffer->capacity) {
            buffer->storage[buffer->offset++] = c;
        }
    }

    void AppendString(device iTermMetalDebugBuffer *buffer,
                      constant char *message,
                      int reserve) {
        int i = 0;
        while (message[i] && buffer->offset + reserve < buffer->capacity) {
            AppendChar(buffer, message[i++], reserve);
        }
    }

    void AppendNonNegativeIntReversed(device iTermMetalDebugBuffer *buffer,
                                      int value,
                                      int reserve) {
        if (value == 0) {
            AppendChar(buffer, '0', reserve);
        } else {
            char c = (value % 10) + '0';
            AppendChar(buffer, c, reserve);
            if (value > 9) {
                AppendNonNegativeIntReversed(buffer, value / 10, reserve);
            }
        }
    }

    void AppendInt(device iTermMetalDebugBuffer *buffer,
                   int value,
                   int reserve) {
        if (value < 0) {
            AppendChar(buffer, '-', reserve);
            AppendInt(buffer, -value, reserve);
        } else {
            int start = buffer->offset;
            AppendNonNegativeIntReversed(buffer, value, reserve);
            ReverseChars(buffer, start, buffer->offset - start);
        }
    }

    void AppendWholePartOfNonNegativeFloatReversed(device iTermMetalDebugBuffer *buffer,
                                                   float value,
                                                   int reserve) {
        if (value == 0) {
            AppendChar(buffer, '0', reserve);
        } else {
            char c = static_cast<char>(fmod(value, 10)) + '0';
            AppendChar(buffer, c, reserve);
            if (value > 9) {
                AppendWholePartOfNonNegativeFloatReversed(buffer, trunc(value / 10), reserve);
            }
        }
    }

    // Precondition: value in [0, 1)
    void AppendFractionalPartOfNonNegativeFloat(device iTermMetalDebugBuffer *buffer,
                                                float value,
                                                int reserve,
                                                int precision) {
        if (precision == 0) {
            return;
        }
        if (value == 0) {
            AppendChar(buffer, '0', reserve);
        } else {
            char c;
            if (precision > 1) {
                c = static_cast<char>(trunc(value * 10)) + '0';
            } else {
                // Round last digit
                c = static_cast<char>(round(value * 10)) + '0';
            }
            AppendChar(buffer, c, reserve);
            AppendFractionalPartOfNonNegativeFloat(buffer, value * 10 - trunc(value * 10), reserve, precision - 1);
        }
    }

    void AppendFloat(device iTermMetalDebugBuffer *buffer,
                     float value,
                     int reserve) {
        if (value < 0) {
            AppendChar(buffer, '-', reserve);
            AppendFloat(buffer, -value, reserve);
        } else {
            int start = buffer->offset;
            float whole;
            // NOTE: There is an annoying difference between metal and c++ here. c++ takes a pointer while metal takes a mutable reference.
            float fractional = modf(value, whole);
            AppendWholePartOfNonNegativeFloatReversed(buffer, whole, reserve);
            ReverseChars(buffer, start, buffer->offset - start);
            AppendChar(buffer, '.', reserve);
            AppendFractionalPartOfNonNegativeFloat(buffer, fractional, reserve, 3);
        }
    }
}

namespace MetalLogging {
    void LogString(bool enabled,
                   device iTermMetalDebugBuffer *buffer,
                   constant char *message) {
        if (!enabled) {
            return;
        }
        AppendString(buffer, message, 2);
        AppendChar(buffer, '\n', 1);
        NullTerminate(buffer);
    }

    void LogStringInt(bool enabled,
                      device iTermMetalDebugBuffer *buffer,
                      constant char *message,
                      constant int *values,
                      int count) {
        if (!enabled) {
            return;
        }
        AppendString(buffer, message, 2);
        for (int i = 0; i < count; i++) {
            AppendChar(buffer, ' ', 2);
            AppendInt(buffer, values[i], 2);
        }
        AppendChar(buffer, '\n', 1);
        NullTerminate(buffer);
    }

    void LogStringFloat(bool enabled,
                        device iTermMetalDebugBuffer *buffer,
                        constant char *message,
                        constant float *values,
                        int count) {
        if (!enabled) {
            return;
        }
        AppendString(buffer, message, 2);
        for (int i = 0; i < count; i++) {
            AppendChar(buffer, ' ', 2);
            AppendFloat(buffer, values[i], 2);
        }
        AppendChar(buffer, '\n', 1);
        NullTerminate(buffer);
    }
}
