// Fixture: a repository header read only through a module, with function
// bodies the extractor does not walk (test_codedb_completeness.py,
// ModuleBodyTest).
__attribute__((objc_root_class))
@interface BMThing
- (int)poke;
@end
static inline int BodyModPoke(BMThing *t) { return [t poke]; }
int BodyModDeclared(BMThing *t);
