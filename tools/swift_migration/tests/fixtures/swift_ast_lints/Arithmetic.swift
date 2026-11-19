import Foundation

typealias FixInt = Int32

func it_add<T: FixedWidthInteger>(_ a: T, _ b: T) -> T { return a &+ b }

func arithmetic(a: Int32, b: Int32, n: NSInteger, c: FixInt, u: UInt8, d: Double, g: CGFloat, s: String) {
    _ = a + b
    _ = n - 1
    _ = c * c
    _ = -a
    _ = a << 2
    _ = u + u
    var q = a
    q += 1
    q -= b
    q *= 2
    q <<= 1
    _ = d + 1
    _ = g * 2
    _ = s + "x"
    _ = [1] + [2]
    _ = a &+ b
    _ = 1 + 2
    _ = it_add(a, b)
    _ = a + b // bounded-by-type: the fixture says so
    // bounded-by-type: the line below
    _ = a - b
    // bounded-by-type: two lines above does not count

    _ = a * b
    _ = a / b
    _ = a < b
    _ = -d
    _ = q
    _ = a + FixToken()
}

struct FixToken {}

// An operator of this module, not of the standard library: not integer arithmetic, though its operand is Int32.
func + (lhs: Int32, rhs: FixToken) -> Int32 { return lhs }
