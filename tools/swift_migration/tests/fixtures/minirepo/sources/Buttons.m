#import "Buttons.h"

NSString *const kFixtureButtonKey = @"key";
static int sHidden;

NSString *FixtureLocalizedOK(void) {
    return @"OK";
}

static void Private(void) {
    sHidden++;
}

static void reset(void) {
}

int gButtonsA = 1, gButtonsB = 2;

void (*FixtureHandlerFor(int kind))(int) {
    return 0;
}

int FixtureOnlyExternInM(void) {
    return 1;
}

#define FIXTURE_DEFINE_GETTER(name) int name(void) { return 0; }
FIXTURE_DEFINE_GETTER(FixtureMacroGetter)
