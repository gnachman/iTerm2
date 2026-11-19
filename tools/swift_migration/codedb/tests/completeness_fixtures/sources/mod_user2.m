// Fixture: a second unit that imports the same module.
@import LocalMod;
void ModUser2(ModChild *c) {
    [c poke];
}
