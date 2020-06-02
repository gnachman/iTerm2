//
//  iTermScreenCharAttachmentTests.m
//  iTerm2XCTests
//
//  Created by George Nachman on 6/1/20.
//

#import <XCTest/XCTest.h>
#import "iTermScreenCharAttachment.h"

@interface iTermScreenCharAttachmentTests : XCTestCase

@end

@implementation iTermScreenCharAttachmentTests

- (void)setUp {
}

- (void)tearDown {
}

#pragma mark - iTermScreenCharAttachmentRunArray

- (iTermScreenCharAttachmentRun *)heapify:(iTermScreenCharAttachmentRun *)array
                                     size:(size_t)size {
    iTermScreenCharAttachmentRun *result = malloc(size);
    memmove(result, array, size);
    return result;
}

- (void)testScreenCharAttachmentRunArray_AppendRunArray {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];

    iTermScreenCharAttachmentRun r2[3] = {
        {
            .offset = 0,
            .length = 1,
            .attachment = { .underlineRed = 3 }
        },
        {
            .offset = 10,
            .length = 1,
            .attachment = { .underlineRed = 4 }
        },
        {
            .offset = 20,
            .length = 1,
            .attachment = { .underlineRed = 5 }
        }
    };

    iTermScreenCharAttachmentRunArray *a2 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r2 size:sizeof(r2)]
                                                  count:sizeof(r2) / sizeof(*r2)];

    [a1 append:a2 baseOffset:40];

    XCTAssertEqual(6, a1.count);
    NSInteger i = 0;
    XCTAssertEqual(a1.runs[i].offset, 2);
    XCTAssertEqual(a1.runs[i].length, 10);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(a1.runs[i].offset, 20);
    XCTAssertEqual(a1.runs[i].length, 5);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
    XCTAssertEqual(a1.runs[i].offset, 30);
    XCTAssertEqual(a1.runs[i].length, 1);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    XCTAssertEqual(a1.runs[i].offset, 40);
    XCTAssertEqual(a1.runs[i].length, 1);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 3);
    XCTAssertEqual(a1.runs[i].offset, 50);
    XCTAssertEqual(a1.runs[i].length, 1);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 4);
    XCTAssertEqual(a1.runs[i].offset, 60);
    XCTAssertEqual(a1.runs[i].length, 1);
    XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 5);
}

- (void)testScreenCharAttachmentRunArray_SlicePrefix {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:0 length:15];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 2);
    XCTAssertEqual(slice.runs[i].length, 10);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceInfix {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:15 length:12];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 20);
    XCTAssertEqual(slice.runs[i].length, 5);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 1);
    XCTAssertEqual(slice.baseOffset, 15);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceSuffix {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:26 length:100];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 30);
    XCTAssertEqual(slice.runs[i].length, 1);
//    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 2);
    XCTAssertEqual(slice.baseOffset, 26);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceEndingBeforeFirstRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:1 length:1];
    XCTAssertEqual(slice.count, 0);
    XCTAssertEqual(slice.baseOffset, 1);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceStartingAfterLastRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:35 length:1];
    XCTAssertEqual(slice.count, 0);
    XCTAssertEqual(slice.baseOffset, 35);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceWhole {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:1 length:35];
    XCTAssertEqual(slice.baseOffset, 1);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, slice.count);
        NSInteger i = 0;
        XCTAssertEqual(slice.runs[i].offset, 3);
        XCTAssertEqual(slice.runs[i].length, 10);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(slice.runs[i].offset, 20);
        XCTAssertEqual(slice.runs[i].length, 5);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(slice.runs[i].offset, 30);
        XCTAssertEqual(slice.runs[i].length, 1);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 2);
    }
    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceWholeUsingAsSlice {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 asSlice];
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, slice.count);
        NSInteger i = 0;
        XCTAssertEqual(slice.runs[i].offset, 3);
        XCTAssertEqual(slice.runs[i].length, 10);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(slice.runs[i].offset, 20);
        XCTAssertEqual(slice.runs[i].length, 5);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(slice.runs[i].offset, 30);
        XCTAssertEqual(slice.runs[i].length, 1);
        XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 2);
    }
    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceCutEndingJustBeforeRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:0 length:3];
    XCTAssertEqual(slice.count, 0);
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceCutEndingAfterFirstValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:0 length:4];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 3);
    XCTAssertEqual(slice.runs[i].length, 1);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(4, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 4);
        XCTAssertEqual(a1.runs[i].length, 9);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceCutEndingBeforeLastValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:0 length:12];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 3);
    XCTAssertEqual(slice.runs[i].length, 9);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(4, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 9);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 12);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceEndingJustAfterLastValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:0 length:12];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 2);
    XCTAssertEqual(slice.runs[i].length, 10);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 0);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

#pragma mark -

- (void)testScreenCharAttachmentRunArray_SliceCutStartingJustBeforeRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:3 length:11];
    XCTAssertEqual(slice.count, 1);
    XCTAssertEqual(a1.runs[0].offset, 3);
    XCTAssertEqual(a1.runs[0].length, 10);
    XCTAssertEqual(a1.runs[0].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 3);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceCutStartingAfterFirstValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:4 length:11];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 4);
    XCTAssertEqual(slice.runs[i].length, 9);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 4);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(4, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 4);
        XCTAssertEqual(a1.runs[i].length, 9);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceCutStartingBeforeLastValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 3,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:12 length:5];
    XCTAssertEqual(slice.count, 1);
    NSInteger i = 0;
    XCTAssertEqual(slice.runs[i].offset, 12);
    XCTAssertEqual(slice.runs[i].length, 1);
    XCTAssertEqual(slice.runs[i++].attachment.underlineRed, 0);
    XCTAssertEqual(slice.baseOffset, 12);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(4, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 9);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 12);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_SliceStartingJustAfterLastValueOfRun {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *a1 =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    iTermScreenCharAttachmentRunArraySlice *slice = [a1 sliceFrom:12 length:5];
    XCTAssertEqual(slice.count, 0);
    XCTAssertEqual(slice.baseOffset, 12);
    XCTAssertTrue(slice.realArray == a1);

    {
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

- (void)testScreenCharAttachmentRunArray_Serialization {
    iTermScreenCharAttachmentRun r1[3] = {
        {
            .offset = 2,
            .length = 10,
            .attachment = { .underlineRed = 0 }
        },
        {
            .offset = 20,
            .length = 5,
            .attachment = { .underlineRed = 1 }
        },
        {
            .offset = 30,
            .length = 1,
            .attachment = { .underlineRed = 2 }
        }
    };
    iTermScreenCharAttachmentRunArray *orig =
    [iTermScreenCharAttachmentRunArray runArrayWithRuns:[self heapify:r1 size:sizeof(r1)]
                                                  count:sizeof(r1) / sizeof(*r1)];
    NSData *data = orig.serialized;
    iTermScreenCharAttachmentRunArray *a1 =
    [[iTermScreenCharAttachmentRunArray alloc] initWithSerialized:data];

    {
        XCTAssertEqual(0, a1.baseOffset);
        XCTAssertEqual(3, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 2);
        XCTAssertEqual(a1.runs[i].length, 10);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);
        XCTAssertEqual(a1.runs[i].offset, 20);
        XCTAssertEqual(a1.runs[i].length, 5);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);
        XCTAssertEqual(a1.runs[i].offset, 30);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 2);
    }
}

#pragma mark - iTermScreenCharAttachmentsArray

- (void)testScreenCharAttachmentsArray_runArray {
    NSMutableIndexSet *validAttachments = [NSMutableIndexSet indexSet];
    [validAttachments addIndex:0];
    [validAttachments addIndex:1];
    [validAttachments addIndex:3];
    [validAttachments addIndex:5];
    [validAttachments addIndex:6];

    iTermScreenCharAttachment attachments[7] = {
        { .underlineRed = 0 },  // 0  run 0
        { .underlineRed = 1 },  // 1  run 1
        { .underlineRed = -1 },
        { .underlineRed = 1 },  // 3  run 2
        { .underlineRed = -1 },
        { .underlineRed = 5 },  // 5  run 3
        { .underlineRed = 5 },  // 6  run 3
    };

    iTermScreenCharAttachmentsArray *array =
    [[iTermScreenCharAttachmentsArray alloc] initWithValidAttachmentIndexes:validAttachments
                                                                attachments:attachments
                                                                      count:sizeof(attachments) / sizeof(*attachments)];

    XCTAssertEqualObjects(validAttachments, array.validAttachments);
    XCTAssertNotEqual(validAttachments, array.validAttachments);
    XCTAssertEqual(0, memcmp(attachments, array.attachments, sizeof(attachments)));
    XCTAssertEqual(7, array.count);

    id<iTermScreenCharAttachmentRunArray> a1 = array.runArray;
    {
        XCTAssertEqual(0, a1.baseOffset);
        XCTAssertEqual(4, a1.count);
        NSInteger i = 0;
        XCTAssertEqual(a1.runs[i].offset, 0);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 0);

        XCTAssertEqual(a1.runs[i].offset, 1);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);

        XCTAssertEqual(a1.runs[i].offset, 3);
        XCTAssertEqual(a1.runs[i].length, 1);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 1);

        XCTAssertEqual(a1.runs[i].offset, 5);
        XCTAssertEqual(a1.runs[i].length, 2);
        XCTAssertEqual(a1.runs[i++].attachment.underlineRed, 5);
    }
}

- (void)testScreenCharAttachmentsArray_copy {
    NSMutableIndexSet *validAttachments = [NSMutableIndexSet indexSet];
    [validAttachments addIndex:0];
    [validAttachments addIndex:1];
    [validAttachments addIndex:3];
    [validAttachments addIndex:5];
    [validAttachments addIndex:6];

    iTermScreenCharAttachment attachments[7] = {
        { .underlineRed = 0 },  // 0  run 0
        { .underlineRed = 1 },  // 1  run 1
        { .underlineRed = -1 },
        { .underlineRed = 1 },  // 3  run 2
        { .underlineRed = -1 },
        { .underlineRed = 5 },  // 5  run 3
        { .underlineRed = 5 },  // 6  run 3
    };

    iTermScreenCharAttachmentsArray *array =
    [[iTermScreenCharAttachmentsArray alloc] initWithValidAttachmentIndexes:validAttachments
                                                                attachments:attachments
                                                                      count:sizeof(attachments) / sizeof(*attachments)];
    XCTAssertTrue(array == [array copy]);
}

#pragma mark - iTermMutableScreenCharAttachmentsArray

- (void)testiTermMutableScreenCharAttachmentsArray_MutateAndCopy {
    iTermMutableScreenCharAttachmentsArray *m =
    [[iTermMutableScreenCharAttachmentsArray alloc] initWithCount:10];
    m.mutableAttachments[2].underlineRed = 2;
    [m.mutableValidAttachments addIndex:2];
    [m.mutableValidAttachments removeIndex:2];

    m.mutableAttachments[3].underlineRed = 3;
    [m.mutableValidAttachments addIndex:3];

    m.mutableAttachments[4].underlineRed = 4;
    [m.mutableValidAttachments addIndex:4];

    iTermScreenCharAttachmentsArray *array = [m copy];
    NSIndexSet *expectedIndexes = [m.validAttachments copy];
    [m.mutableValidAttachments removeAllIndexes];
    m.mutableAttachments[3].underlineRed = 0;
    m.mutableAttachments[4].underlineRed = 0;

    XCTAssertEqual(2, array.validAttachments.count);
    XCTAssertEqualObjects(expectedIndexes, array.validAttachments);
    XCTAssertEqual(3, array.attachments[3].underlineRed);
    XCTAssertEqual(4, array.attachments[4].underlineRed);
}


@end
