// Fixture: imports a repository header with an inline function body through
// a module (test_codedb_completeness.py, ModuleBodyTest).
@import BodyMod;
int BodyUser(BMThing *t) {
    return BodyModDeclared(t);
}
