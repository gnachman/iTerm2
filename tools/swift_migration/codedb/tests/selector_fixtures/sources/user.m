// Fixture: a second unit that reads methods.h. Line numbers are part of the expectations.
#import "methods.h"
int UseGadget(Gadget *g) {
    return [g count] + g.size;
}
