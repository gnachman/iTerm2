import Foundation

func runtimeNames(_ i: Ivar) {
    _ = ivar_getName(i)
    _ = ivar_getTypeEncoding(i)
    MyClass_ivar_set_foo(nil, 1)
}
