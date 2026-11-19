// The names of the nodes and fields of the Swift compiler's JSON AST dump
// (`swift-frontend -dump-ast -dump-ast-format json`) that the reader depends
// on, in one place. The compiler's help says the format is not stable across
// versions, so the reader is written against one version (kWrittenAgainst,
// major.minor) and codedb.py refuses a dump from another unless
// --accept-compiler-version is given. Every name the reader compares with is
// here; swift_refs.cpp uses no other string from the dump.
#pragma once

namespace dump {

// The compiler version (major.minor) these names were read from.
static const char *const kWrittenAgainst = "6.4";

// Fields.
static const char *const kKind = "_kind";
static const char *const kUsr = "usr";
static const char *const kDeclUsr = "decl_usr";
static const char *const kBaseNameField = "base_name";  // in decl_ref: the name used
static const char *const kName = "name";
static const char *const kFilename = "filename";
static const char *const kRange = "range";
static const char *const kStart = "start";
static const char *const kEnd = "end";
static const char *const kType = "type";
static const char *const kAccess = "access";
static const char *const kImplicit = "implicit";
static const char *const kObjCFlag = "@objc";
static const char *const kStatic = "static";
static const char *const kGet = "get";
static const char *const kSet = "set";
static const char *const kApiName = "apiName";
static const char *const kSelectorKind = "kind";  // of objc_selector_expr: method, getter, setter
static const char *const kIsNameImplicit = "is_name_implicit";
static const char *const kMajor = "major";
static const char *const kMinor = "minor";
static const char *const kFull = "full";
static const char *const kExtendedType = "extended_type";    // of extension_decl
static const char *const kSuperclassType = "superclass_type";  // of a class's inheritance node
static const char *const kKeyPathObjC = "objc";               // of keypath_expr: #keyPath
static const char *const kProtocolField = "protocol";          // of normal_conformance: the protocol's USR

// Keys under which a child sits.
static const char *const kKeyDecl = "decl";                // decl_ref of a reference node
static const char *const kKeyName = "name";                // decl_name of a declaration
static const char *const kKeyParams = "params";
static const char *const kKeyAttrs = "attrs";
static const char *const kKeyDest = "dest";                // of assign_expr
static const char *const kKeySrc = "src";                  // of assign_expr
static const char *const kKeyExistentialValue = "existential_value";  // of open_existential_expr
static const char *const kKeyBase = "base";
static const char *const kKeySubExpr = "sub_expr";
static const char *const kKeyFn = "fn";
static const char *const kKeyArgs = "args";
static const char *const kKeyExpr = "expr";
static const char *const kKeyComponents = "components";  // of keypath_expr
static const char *const kKeyRewritten = "rewritten";    // macro expansion
static const char *const kKeyCompilerVersion = "compiler_version";
static const char *const kKeyForeignError = "foreign_error_convention";
static const char *const kKeyForeignAsync = "foreign_async_convention";
static const char *const kKeyAccessors = "accessors";
static const char *const kKeyInherits = "inherits";
static const char *const kKeyConformances = "conformances";  // of an inheritance node
static const char *const kKeyMembers = "members";            // of a type or extension declaration
// Subtrees that hold copies made before type checking (duplicates of what
// follows, or unresolved): skipped.
static const char *const kSkipKeys[] = {"original_init", "parsed_path", "parsed_root"};

// Node kinds.
static const char *const kSourceFile = "source_file";
static const char *const kDeclRef = "decl_ref";
static const char *const kDeclName = "decl_name";
static const char *const kBaseName = "base_name";
static const char *const kParameter = "parameter";
static const char *const kParameterList = "parameter_list";
static const char *const kDeclRefExpr = "declref_expr";
static const char *const kMemberRefExpr = "member_ref_expr";
static const char *const kDynamicMemberRefExpr = "dynamic_member_ref_expr";
static const char *const kOtherConstructorRefExpr = "other_constructor_ref_expr";
static const char *const kSubscriptExpr = "subscript_expr";
static const char *const kDynamicSubscriptExpr = "dynamic_subscript_expr";
static const char *const kObjCSelectorExpr = "objc_selector_expr";
static const char *const kKeyPathExpr = "keypath_expr";
static const char *const kKeyPathMember = "member";  // a key path component
static const char *const kDotSyntaxCallExpr = "dot_syntax_call_expr";
static const char *const kConstructorRefCallExpr = "constructor_ref_call_expr";
static const char *const kArgument = "argument";
static const char *const kArgumentList = "argument_list";
static const char *const kClosureExpr = "closure_expr";
static const char *const kLoadExpr = "load_expr";
static const char *const kAssignExpr = "assign_expr";
static const char *const kInOutExpr = "inout_expr";
static const char *const kTupleExpr = "tuple_expr";
static const char *const kOpenExistentialExpr = "open_existential_expr";
static const char *const kInheritance = "inheritance";
static const char *const kNormalConformance = "normal_conformance";
static const char *const kObjCAttr = "objc_attr";
static const char *const kOverrideAttr = "override_attr";
// Expressions through which an lvalue passes on its way to a load, an
// assignment or an inout argument: what they hold under base or sub_expr
// (any element, for a tuple_expr) is accessed as their parent decides.
// Those in kLvalueChain access a part of it (writing w.frame.origin reads
// and writes w.frame; writing w.title! reads w.title first); those in
// kLvalueIdentity are the same lvalue (writing (w.count) writes w.count).
static const char *const kLvalueChain[] = {
    "member_ref_expr", "subscript_expr", "bind_optional_expr", "force_value_expr", "tuple_element_expr",
    "dynamic_member_ref_expr", "dynamic_subscript_expr", "keypath_application_expr",
};
static const char *const kLvalueIdentity[] = {
    "paren_expr", "dot_self_expr", "tuple_expr", "open_existential_expr",
    // An lvalue conversion: the compiler wraps an assignment's target in it
    // when the property's type differs by @Sendable or @preconcurrency
    // (process.terminationHandler = { ... }).
    "abi_safe_conversion_expr",
    // Identity expressions, whose value is what they hold, lvalue or not.
    "await_expr", "unsafe_expr", "borrow_expr",
    // The value of an optional chain or of a try is what they hold.
    "optional_evaluation_expr", "try_expr", "force_try_expr", "optional_try_expr",
};
// Nodes that take only rvalues: a property reference directly under one
// (or reaching it through an lvalue chain) is read. Any other parent leaves
// the access unknown (see accessIn in swift_refs.cpp). Each was checked with
// `swiftc -dump-ast` on a settable property in its place: the compiler puts
// a load_expr between them, so what they hold is a value. (The value of
// open_existential_expr's existential_value is read too; accessIn says so.
// Its sub_expr is the expression's value: kLvalueIdentity.)
static const char *const kRvalueContexts[] = {
    // Calls and their arguments (an argument passed inout is in an
    // inout_expr, which decides first), and the body of an autoclosure
    // (XCTAssert(w.on)).
    "argument", "call_expr", "binary_expr", "rebind_self_in_constructor_expr", "autoclosure_expr",
    // Conversions and casts of a value (abi_safe_conversion_expr, the one
    // lvalue conversion, is in kLvalueIdentity).
    "erasure_expr", "inject_into_optional", "function_conversion_expr", "derived_to_base_expr",
    "covariant_return_conversion_expr", "any_hashable_erasure_expr", "bridge_from_objc_expr",
    "bridge_to_objc_expr", "coerce_expr", "conditional_checked_cast_expr", "forced_checked_cast_expr",
    "pointer_to_pointer",
    // Collections built from values, and the choice of one (c ? a : b
    // cannot be assigned to in Swift).
    "array_expr", "dictionary_expr", "ternary_expr", "collection_upcast_expr",
    // Statements and patterns that use a value: the sequence of a for-in,
    // conditions, a switch's subject, a variable's initial value, a
    // parameter's default value, the initializer of if let x = ..., the
    // where clause of a case, the value of an if or switch expression.
    "brace_stmt", "return_stmt", "yield_stmt", "pattern_entry", "for_each_stmt", "if_stmt", "guard_stmt",
    "while_stmt", "switch_stmt", "parameter", "pattern", "case_label_item", "then_stmt",
};
// Node kinds the reader reacts to (each is named on its own above or below).
static const char *const kHandledKinds[] = {
    "source_file", "compiler_version", "decl_ref", "decl_name", "base_name", "parameter", "parameter_list",
    "declref_expr", "member_ref_expr", "dynamic_member_ref_expr", "other_constructor_ref_expr", "subscript_expr",
    "dynamic_subscript_expr", "objc_selector_expr", "keypath_expr", "member", "dot_syntax_call_expr",
    "constructor_ref_call_expr", "argument", "argument_list", "closure_expr", "load_expr", "assign_expr",
    "inout_expr", "objc_attr", "override_attr", "func_decl", "accessor_decl", "constructor_decl",
    "destructor_decl", "var_decl", "subscript_decl", "inheritance", "foreign_error_convention",
    "foreign_async_convention", "normal_conformance",
};
// Node kinds the reader deliberately passes over: it takes nothing from the
// node itself (its children are still read, so a reference under one is
// recorded). None of them was seen holding a property reference directly;
// if one does, that access is recorded as unknown, not as a wrong access.
// Every kind the dumps of this tree (Swift 6.4) contain is in one of the
// tables of this file; update and the queries warn of any other.
static const char *const kIgnoredKinds[] = {
    // Conformances, generic signatures, substitutions and type references:
    // type information.
    "abstract_conformance", "builtin_conformance", "conformance", "conformance_context", "inherited_conformance",
    "specialized_conformance", "self_conformance", "pack_conformance", "requirement",
    "requirement_repr", "requirement_signature", "generic_signature", "substitution", "substitution_map",
    "opaque_to_existential_mapping", "type_composite", "type_qualified_ident", "type_unqualified_ident",
    "type_tuple",
    // Attributes other than @objc and override: none changes a selector
    // (@nonobjc makes a declaration invisible to Objective-C, which its USR
    // and @objc flag already say).
    "access_control_attr", "async_attr", "available_attr", "convenience_attr", "custom_attr",
    "discardable_result_attr", "dynamic_attr", "final_attr", "has_initial_value_attr", "has_storage_attr",
    "ib_action_attr", "ib_designable_attr", "ib_inspectable_attr", "ib_outlet_attr", "implements_attr",
    "indirect_attr", "inlinable_attr", "inline_attr", "lazy_attr", "main_type_attr", "mutating_attr",
    "non_ephemeral_attr", "non_mutating_attr", "non_objc_attr", "nonisolated_attr", "ns_copying_attr",
    "objc_members_attr", "optional_attr", "preconcurrency_attr", "property_wrapper_attr",
    "reference_ownership_attr", "required_attr", "result_builder_attr", "rethrows_attr", "semantics_attr",
    "sendable_attr", "setter_access_attr", "storage_restrictions_attr", "transparent_attr",
    // Availability conditions (#available(...)).
    "#available", "availability_spec",
    // Literals, and the parts of a string interpolation (the calls that
    // append each segment are under them).
    "boolean_literal_expr", "integer_literal_expr", "float_literal_expr", "string_literal_expr",
    "nil_literal_expr", "magic_identifier_literal_expr", "interpolated_string_literal_expr", "tap_expr",
    // Declarations with no Objective-C selector, and declarations and
    // patterns that only hold the nodes that matter.
    "import_decl", "pattern_binding_decl", "pattern_binding", "enum_case_decl", "enum_element_decl",
    "infix_operator_decl", "typealias", "associated_type_decl", "pattern_named", "pattern_typed", "pattern_any",
    "pattern_bool", "pattern_enum_element", "pattern_expr", "pattern_is", "pattern_opaque",
    "pattern_optional_some", "pattern_paren", "pattern_tuple", "tuple_element",
    // Statements whose expressions sit under a node that classifies them, or
    // that hold none.
    "defer_stmt", "break_stmt", "continue_stmt", "fallthrough_stmt", "fail_stmt", "throw_stmt", "do_stmt",
    "do_catch_stmt", "repeat_while_stmt", "case_stmt", "single_value_stmt_expr", "unreachable",
    // Conversions and expressions over types, metatypes, pointers and
    // collections that were not seen holding a property reference directly.
    "metatype_conversion_expr", "metatype_expr", "class_metatype_to_object", "existential_metatype_to_object",
    "protocol_metatype_to_object", "archetype_to_super_expr", "underlying_to_opaque_expr",
    "foreign_object_conversion", "array_to_pointer", "inout_to_pointer", "string_to_pointer", "is_subtype_expr",
    "enum_is_case_expr", "destructure_tuple_expr", "vararg_expansion_expr", "default_argument_expr",
    "lazy_initializer_expr", "property_wrapper_value_placeholder_expr", "current_context_isolation_expr",
    "prefix_unary_expr", "postfix_unary_expr", "capture_list",
    // References to no declaration of their own, or to a type.
    "captured_value", "function_ref_info", "opaque_value_expr", "super_ref_expr", "type_expr",
    "discard_assignment_expr", "dot_syntax_base_ignored", "unevaluated_instance", "thrown_error_destination",
    // Unresolved forms the compiler leaves next to the checked ones, and in
    // the bodies it synthesizes and leaves unchecked in the dump (a derived
    // ==): they name no declaration.
    "unresolved_dot_expr", "unresolved_decl_ref_expr", "unresolved_member_expr",
};
// Declarations.
static const char *const kFuncDecl = "func_decl";
static const char *const kAccessorDecl = "accessor_decl";
static const char *const kConstructorDecl = "constructor_decl";
static const char *const kDestructorDecl = "destructor_decl";
static const char *const kVarDecl = "var_decl";
static const char *const kSubscriptDecl = "subscript_decl";
static const char *const kClassDecl = "class_decl";
static const char *const kExtensionDecl = "extension_decl";
static const char *const kProtocolDecl = "protocol";
static const char *const kTypeDecls[] = {"class_decl", "struct_decl", "enum_decl", "extension_decl", "protocol"};

// The values of objc_selector_expr's kind.
static const char *const kSelectorMethod = "method";

}  // namespace dump
