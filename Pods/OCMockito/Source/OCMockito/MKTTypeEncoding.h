//
//  OCMockito - MKTTypeEncoding.h
//  Copyright 2012 Jonathan M. Reid. All rights reserved.
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//


static inline BOOL MKTTypeEncodingIsObjectOrClass(const char *type)
{
    return strcmp(type, @encode(id)) == 0 || strcmp(type, @encode(Class)) == 0;
}
