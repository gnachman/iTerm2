//
//  CVector.h
//  iTerm
//
//  Created by George Nachman on 3/5/14.
//
//

#import <Foundation/Foundation.h>

// A vector of pointers that is fast and simple.
typedef struct {
    int capacity;
    void **elements;
    int count;
} CVector;

NS_INLINE void CVectorCreate(CVector *vector, int capacity) {
    vector->capacity = capacity;
    vector->elements = (void **)malloc(vector->capacity * sizeof(void *));
    vector->count = 0;
}

NS_INLINE void CVectorDestroy(const CVector *vector) {
    free(vector->elements);
}

NS_INLINE void *CVectorGet(const CVector *vector, int index) {
    return vector->elements[index];
}

NS_INLINE int CVectorCount(const CVector *vector) {
    return vector->count;
}

NS_INLINE id CVectorGetObject(const CVector *vector, int index) {
    return (id) vector->elements[index];
}

NS_INLINE void CVectorSet(const CVector *vector, int index, void *value) {
    vector->elements[index] = value;
}

NS_INLINE void CVectorAppend(CVector *vector, void *value) {
    if (vector->count + 1 == vector->capacity) {
        vector->capacity *= 2;
        vector->elements = realloc(vector->elements, sizeof(void *) * vector->capacity);
    }
    vector->elements[vector->count++] = value;
}

NS_INLINE id CVectorLastObject(const CVector *vector) {
    if (vector->count == 0) {
        return nil;
    }
    return CVectorGet(vector, vector->count - 1);
}

