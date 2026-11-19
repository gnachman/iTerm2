struct E: Error {}
func mayThrow(_ x: Int) throws -> Int { if x > 2 { throw E() }; return x }
func opt(_ x: Int) -> Int? { x > 0 ? x : nil }

func elseIfLet(_ x: Int) -> Int {
    if x > -100 { // M:ei-let
        return 1
    } else if let y = opt(x) { // M:ei-let-nested
        return y
    }
    return 3
}

func elseIfVar(_ x: Int) -> Int {
    if x > -100 { // M:ei-var
        return 1
    } else if var y = opt(x) {
        y += 1
        return y
    }
    return 3
}

func elseIfCase(_ x: Int) -> Int {
    if x > -100 { return 1 } else if case .some(let v) = opt(x) { return v } // M:ei-case
    return 3
}

func elseIfLetElse(_ x: Int) -> Int {
    var r = 0
    if x > 10 { r = 1 } else if let y = opt(x) { r = y } else { r = 9 } // M:ei-let-else
    return r
}

func chainNoElse(_ x: Int) -> Int {
    if x > 100 { // M:ch-1
        return 1
    } else if let a = opt(x) { // M:ch-2
        return a
    } else if case let b? = opt(x + 50) { // M:ch-3
        return b
    }
    return 4
}

func chainBoolLast(_ x: Int) -> Int {
    if x > 100 { // M:cb-1
        return 1
    } else if let a = opt(x - 50) { // M:cb-2
        return a
    } else if case let b? = opt(x + 50) { // M:cb-3
        return b
    } else if x == -1000 { // M:cb-4
        return 5
    }
    return 4
}

func thenThrows(_ x: Int) throws -> Int {
    if x > 0 { // M:tt-1
        throw E()
    } else if let y = opt(-x) { // M:tt-2
        return y
    }
    return 0
}

func headTry(_ x: Int) throws -> Int {
    if try mayThrow(x) > 0 { // M:ht-1
        return 1
    } else if let y = opt(x) { // M:ht-2
        return y
    }
    return 0
}

func mixedClauses(_ x: Int) -> Int {
    if x > 0, let y = opt(x - 5) { // M:mc-1
        return y
    } else if let z = opt(-x), z > 3 { // M:mc-2
        return z
    }
    return 0
}

func patternFirst(_ x: Int) -> Int {
    if let a = opt(x) { // M:pf-1
        return a
    } else if let b = opt(-x) { // M:pf-2
        return b
    }
    return 0
}

func mixedBool(_ x: Int) -> Int {
    var r = 0
    if let a = opt(x) { // M:mb-1
        r = a
    } else if x < -100 { // M:mb-2
        r = 2
    } else if let c = opt(-x) { // M:mb-3
        r = c
    } else {
        r = 7
    }
    return r
}

func inClosure(_ n: Int) -> Int {
    let f = { (x: Int) -> Int in
        if x > 0 { // M:ic-1
            return 1
        } else if let y = opt(-x) { // M:ic-2
            return y
        }
        return 0
    }
    return f(n)
}

func inGuardElse(_ x: Int) -> Int {
    guard x > 0 else { // M:ig-guard
        if x == 0 { // M:ig-1
            return 0
        } else if let y = opt(-x) { // M:ig-2
            return y
        }
        return -1
    }
    return x
}

func noExitThen(_ x: Int) -> Int {
    var r = 0
    if x > 0 { // M:ne-1
        r = 1
    } else if let y = opt(-x) { // M:ne-2
        r = y
    }
    return r
}

func ifTry(_ x: Int) throws -> Int {
    if try mayThrow(x) > 0 { // M:if-try
        return 1
    }
    return 0
}

func guardTry(_ x: Int) throws -> Int {
    guard try mayThrow(x) > 0 else { // M:guard-try
        return 0
    }
    return 1
}

func guardAlwaysFails(_ x: Int) -> Int {
    guard x > 100 else { // M:guard-fails
        return 0
    }
    return 1
}

func guardLast(_ x: Int) -> Int {
    var r = 0
    if x > 0 {
        guard x > 100 else { r = 2; return r } // M:guard-last
    }
    return r
}

func whileTry(_ n: Int) throws -> Int {
    var i = 0
    while try mayThrow(i) < 100 { // M:while-try
        i += 1
    }
    return i
}

func repeatTry(_ n: Int) throws -> Int {
    var i = 0
    repeat {
        i += 1
    } while try mayThrow(i) < 100 // M:repeat-try
    return i
}

func emptyBodies(_ x: Int) -> Int {
    if x > 0 { } else if let y = opt(-x) { _ = y } // M:empty
    return x
}

func nestedTryNeverReached(_ x: Int) throws -> Int {
    if x > -100 { return 1 } else if try mayThrow(x) > 0 { return 2 } // M:ntn
    return 3
}

func whileTryAlwaysTrue(_ n: Int) throws -> Int {
    var i = 0
    while try mayThrow(i) < 100 { // M:wtat
        i += 1
        if i == 2 { break } // M:wtat-if
    }
    return i
}

func tryWithElse(_ x: Int) throws -> Int {
    var r = 0
    if try mayThrow(x) > 1 { r = 1 } else { r = 2 } // M:twe
    return r
}

func repeatThrowInIf(_ n: Int) throws -> Int {
    var i = 0
    repeat { // M:rp-throw
        i += 1
        if i == 2 { throw E() }
    } while i < n
    return i
}

func repeatTryLast(_ n: Int) throws -> Int {
    var i = 0
    repeat { // M:rp-trylast
        i += 1
        _ = try mayThrow(i)
    } while i < n
    return i
}

func repeatTryMid(_ n: Int) throws -> Int {
    var i = 0
    repeat { // M:rp-trymid
        i += 1
        _ = try mayThrow(i)
        i += 0
    } while i < n
    return i
}

func repeatDoTry(_ n: Int) throws -> Int {
    var i = 0
    repeat { // M:rp-do
        i += 1
        do { _ = try mayThrow(i) }
        i += 0
    } while i < n
    return i
}

func repeatThrowingClosure(_ n: Int) -> Int {
    var i = 0
    repeat { // M:rp-closure
        i += 1
        let c = { () throws -> Int in try mayThrow(i) }
        _ = c
    } while i < n
    return i
}

func repeatBreak(_ n: Int) -> Int {
    var i = 0
    repeat { // M:rp-break
        i += 1
        if i == 2 { break }
    } while i < n
    return i
}

_ = elseIfLet(5); _ = elseIfLet(6)
_ = elseIfVar(5)
_ = elseIfCase(5)
_ = elseIfLetElse(20); _ = elseIfLetElse(5); _ = elseIfLetElse(-1)
_ = chainNoElse(200); _ = chainNoElse(5); _ = chainNoElse(-20)
_ = chainBoolLast(200); _ = chainBoolLast(60); _ = chainBoolLast(-20); _ = chainBoolLast(-1000)
_ = try? thenThrows(1); _ = try? thenThrows(-5)
_ = try? headTry(5); _ = try? headTry(1)
_ = mixedClauses(10); _ = mixedClauses(2); _ = mixedClauses(-10)
_ = patternFirst(5); _ = patternFirst(-5)
_ = mixedBool(5); _ = mixedBool(-5); _ = mixedBool(0)
_ = inClosure(1); _ = inClosure(-4)
_ = inGuardElse(5); _ = inGuardElse(0); _ = inGuardElse(-3)
_ = noExitThen(1); _ = noExitThen(-2)
_ = try? ifTry(5); _ = try? ifTry(1)
_ = try? guardTry(5); _ = try? guardTry(0)
_ = guardAlwaysFails(1)
_ = guardLast(5)
_ = try? whileTry(0)
_ = try? repeatTry(0)
_ = emptyBodies(1); _ = emptyBodies(-1)
_ = try? nestedTryNeverReached(5)
_ = try? whileTryAlwaysTrue(0)
_ = try? tryWithElse(2); _ = try? tryWithElse(0); _ = try? tryWithElse(5)
_ = try? repeatThrowInIf(5); _ = try? repeatThrowInIf(1)
_ = try? repeatTryLast(5); _ = try? repeatTryLast(1)
_ = try? repeatTryMid(5); _ = try? repeatTryMid(1)
_ = try? repeatDoTry(5); _ = try? repeatDoTry(1)
_ = repeatThrowingClosure(3)
_ = repeatBreak(5)
