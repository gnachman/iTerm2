// Fixture for tools/swift_migration/tests/test_coverage_report.py: one
// function per Swift construct, run so that some outcome never happens.
// Swift's coverage has no branch regions; the tests check what the tool
// derives from region counts and what it lists as not determinable. The
// tests find lines by the "M:" markers. The calls at the bottom say which
// paths run.

func ifElse(_ x: Int) -> Int {
    if x > 0 {  // M:s-ifelse
        return 1
    } else {
        return 2
    }
}

func ifNoElse(_ x: Int) -> Int {
    var r = 0
    if x > 0 {  // M:s-ifnoelse
        r = 1
    }
    return r
}

func ifBoth(_ x: Int) -> Int {
    var r = 0
    if x > 0 {  // M:s-ifboth
        r = 1
    }
    return r
}

func guardNeverFails(_ x: Int?) -> Int {
    guard let v = x else {  // M:s-guard
        return -1
    }
    return v
}

func switchAll(_ x: Int) -> Int {
    switch x {
    case 1: return 10
    case 2: return 20
    default: return 0
    }
}

func switchSome(_ x: Int) -> Int {
    switch x {
    case 1: return 10
    case 2: return 20  // M:s-case2
    default: return 0
    }
}

func switchWhere(_ x: Int) -> Int {
    switch x {
    case 1, 2: return 1  // M:s-multi
    case let y where y > 10: return 2  // M:s-where
    default: return 0
    }
}

func loopNever(_ n: Int) -> Int {
    var s = 0
    for i in 0..<n {
        s += i  // M:s-for-body
    }
    return s
}

func whileCounts(_ n: Int) -> Int {
    var i = 0
    while i < n {  // M:s-while
        i += 1
    }
    return i
}

func whileBreak(_ n: Int) -> Int {
    var i = 0
    while i < 100 {  // M:s-while-break
        if i == n { break }
        i += 1
    }
    return i
}

func repeatOnce(_ n: Int) -> Int {
    var i = 0
    repeat {  // M:s-repeat
        i += 1
    } while i < n
    return i
}

func andRightNever(_ a: Bool, _ b: Bool) -> Int {
    if a && b {  // M:s-and
        return 1
    }
    return 0
}

func closureNever(_ x: Int) -> Int {
    let c = { (y: Int) -> Int in y + 1 }  // M:s-closure
    _ = c
    return x
}

func deferred(_ x: Int) -> Int {
    var r = x
    defer { r += 1 }
    return r
}

struct FixtureError: Error {}

func thrower(_ x: Int) throws -> Int {
    if x < 0 { throw FixtureError() }
    return x
}

func catchNever(_ x: Int) -> Int {
    do {
        return try thrower(x)
    } catch {  // M:s-catch
        return -1
    }
}

func earlyReturn(_ x: Int) -> Int {
    if x == 0 { return 0 }  // M:s-early
    let y = x * 2
    return y
}

func optionals(_ s: String?, _ x: Int) -> Int {
    let a = s?.count ?? 0  // M:s-opt
    let b = (try? thrower(x)) ?? 0  // M:s-tryq
    return a + b
}

func multiClause(_ x: Int?) -> Int {
    if let v = x, v > 3 {  // M:s-multiclause
        return v
    }
    return 0
}

func straight(_ x: Int) -> Int {
    return x * 3 + 1
}

_ = ifElse(1)
_ = ifNoElse(1) + ifNoElse(2)
_ = ifBoth(1) + ifBoth(0)
_ = guardNeverFails(5)
_ = switchAll(1) + switchAll(2) + switchAll(3)
_ = switchSome(1) + switchSome(3)
_ = switchWhere(1) + switchWhere(20) + switchWhere(5)
_ = loopNever(0)
_ = whileCounts(3) + whileCounts(0)
_ = whileBreak(5)
_ = repeatOnce(3)
_ = andRightNever(false, true)
_ = closureNever(1)
_ = deferred(1)
_ = catchNever(1)
_ = earlyReturn(3)
_ = optionals("a", 1)
_ = multiClause(5) + multiClause(nil)
_ = straight(2)
