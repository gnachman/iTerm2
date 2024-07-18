//
//  iTermTerminfoHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/24.
//

#define entry iterm2_terminfo_entry
#include <stdbool.h>
#include <stdio.h>
#include <term.h>
#include <term_entry.h>

int iTermTerminfoNumberOfStrings(struct termtype *termType) {
    return NUM_STRINGS(termType);
}

int iTermTerminfoNumberOfNumbers(struct termtype *termType) {
    return NUM_NUMBERS(termType);
}

int iTermTerminfoNumberOfBooleans(struct termtype *termType) {
    return NUM_BOOLEANS(termType);
}

char *iTermTerminfoStringName(struct termtype *termType, int i) {
    return ExtStrname(termType, i, strnames);
}

char *iTermTerminfoNumberName(struct termtype *termType, int i) {
    return ExtNumname(termType, i, numnames);
}

char *iTermTerminfoBooleanName(struct termtype *termType, int i) {
    return ExtBoolname(termType, i, boolnames);
}

