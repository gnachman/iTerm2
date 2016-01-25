//
//  OCMockito - MKTTestLocation.h
//  Copyright 2012 Jonathan M. Reid. See LICENSE.txt
//
//  Created by: Jon Reid, http://qualitycoding.org/
//  Source: https://github.com/jonreid/OCMockito
//

#import <Foundation/Foundation.h>


typedef struct
{
    __unsafe_unretained id testCase;
    const char *fileName;
    int lineNumber;
} MKTTestLocation;


static inline MKTTestLocation MKTTestLocationMake(id test, const char *file, int line)
{
    MKTTestLocation location;
    location.testCase = test;
    location.fileName = file;
    location.lineNumber = line;
    return location;
}

void MKTFailTest(id testCase, const char *fileName, int lineNumber, NSString *description);
void MKTFailTestLocation(MKTTestLocation testLocation, NSString *description);
