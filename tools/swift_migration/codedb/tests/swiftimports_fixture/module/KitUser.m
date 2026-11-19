// Reads Kit.h as text (this unit is compiled without modules), so that the
// database records KitThing's declarations.
#import <Kit/Kit.h>

void UseKit(KitThing *thing) {
    [thing kitMethod];
}
