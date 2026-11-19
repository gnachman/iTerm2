import Foundation

func conversions(d: Double, n: Int, i: Int32, g: CGFloat, u: UInt64, s: String) {
    _ = Int(d)
    _ = Int32(n)
    _ = UInt8(i)
    _ = Int(i)
    _ = Int(g)
    _ = Int64(u)
    let x: Int16 = .init(n)
    _ = Int(truncatingIfNeeded: u)
    _ = Int8(clamping: n)
    _ = UInt32(bitPattern: i)
    _ = Int(exactly: d)
    _ = Int(s)
    _ = Int(5)
    _ = Double(i)
    _ = Float(d)
    _ = numericCast(i) as Int
    _ = Int(3.0)
    _ = x
}
