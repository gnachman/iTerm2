// Fixture for coverage_report.py: code inside string interpolations, and
// the autoclosures of set-aside logging calls. Lines are found by the M:
// markers in comments; see test_coverage_report.py.

struct Failure: Error {}

func debugging() -> Bool {
    return CommandLine.arguments.count > 50
}

func thrower(_ x: Int) throws -> Int {
    if x > 5 { throw Failure() }
    return x
}

func DLog(_ messageBlock: @autoclosure () -> String) {
    if debugging() { print(messageBlock()) }
}

func notDLog(_ messageBlock: @autoclosure () -> String) {
    if debugging() { print(messageBlock()) }
}

func lazily(_ value: @autoclosure () -> Int) -> Int {
    if debugging() { return value() }
    return 0
}

func interpNilCoalescing(_ n: String?) -> String {
    return "hi \(n ?? "x")" // M:i-nc
}

func interpNestedParens(_ a: Int?) -> String {
    return "v \((a ?? 0) + 1)" // M:i-paren
}

func interpNestedString(_ m: Int?) -> String {
    return "a \(String("b \(m ?? 1)"))" // M:i-nested
}

func interpChain(_ s: String?) -> String {
    return "len \(s?.count ?? 0)" // M:i-chain
}

func interpAnd(_ a: Bool, _ b: Bool) -> String {
    return "v \(a && b)" // M:i-and
}

func interpMultiline(_ n: String?) -> String {
    return """
        first
        second \(n ??
          "y") third
        """
}

func interpRaw(_ n: String?) -> String {
    return #"raw \#(n ?? "z") and \(literal) text"# // M:i-raw
}

func interpRaw2(_ a: Bool, _ b: Bool) -> String {
    return ##"x \##(a || b) \#(not) "# still"## // M:i-raw2
}

func literalOnly(_ n: Int) -> String {
    let s = "text ?? and && here || x?.y try? z"
    let r = #"raw \(n ?? m) and \(a && b)"#
    let t = """
        multi ?? && \\(x ?? y) "quoted"
        """
    return s + r + t + "\(n)"
}

func interpTryQ(_ x: Int) -> String {
    return "t \((try? thrower(x)) ?? 0)" // M:i-tryq
}

func interpClosure(_ n: Int) -> String {
    return "c \({ () -> Int in guard n > 0 else { return 0 }; return n }())" // M:i-closure
}

func dlogInterp(_ a: Int?, _ b: Int) -> Int {
    DLog("value \(a ?? b)") // M:d-interp
    return b
}

func dlogClosure(_ xs: [Int]) -> Int {
    DLog("mapped \(xs.map { $0 * 2 })") // M:d-closure
    return xs.count
}

func dlogMultiline(_ a: Int?) -> Int {
    DLog(
        "multi \(a ?? 4)" // M:d-ml
    )
    return 1
}

func notSetAside(_ x: Int) -> Int {
    return lazily(x + 1) // M:d-not
}

func similarName(_ x: Int) -> Int {
    notDLog("q \(x)") // M:d-similar
    return x
}

func dlogThenClosure(_ x: Int) -> Int {
    DLog("x"); let f = { (y: Int) -> Int in y + 1 } // M:d-after
    _ = f
    return x
}

func dlogAndOther(_ x: Int) -> Int {
    DLog("start")
    return lazily(x + 1) // M:d-other
}

func rawQuote(_ q1: Int?) -> String {
    return #"has """"# + "\(q1 ?? 9)" // M:rq
}

func afterRawQuote(_ q2: Int?) -> Int {
    return q2 ?? 7 // M:arq
}

_ = interpNilCoalescing(nil); _ = interpNilCoalescing(nil)
_ = interpNestedParens(nil)
_ = interpNestedString(nil)
_ = interpChain(nil)
_ = interpAnd(false, true)
_ = interpMultiline(nil)
_ = interpRaw(nil)
_ = interpRaw2(true, false)
_ = literalOnly(1)
_ = interpTryQ(1)
_ = interpClosure(1)
_ = dlogInterp(nil, 2)
_ = dlogClosure([1])
_ = dlogMultiline(nil)
_ = notSetAside(1)
_ = similarName(1)
_ = dlogThenClosure(1)
_ = dlogAndOther(1)
_ = rawQuote(nil)
_ = afterRawQuote(nil)
