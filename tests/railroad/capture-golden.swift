import Foundation
@_silgen_name("railroad_dsl_to_svg") func r_svg(_ i: UnsafePointer<CChar>, _ c: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("railroad_dsl_css_for_theme") func r_css(_ t: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("railroad_dsl_is_valid") func r_valid(_ i: UnsafePointer<CChar>) -> Bool
let a = CommandLine.arguments
if a[1] == "css" { print(String(cString: r_css(a[2])!), terminator: ""); exit(0) }
var dsl = a[1] == "regex" ? ICURegexToRailroadConverter().convert(a[2]) : try! String(contentsOfFile: a[2], encoding: .utf8)
if a.count > 3 { try! dsl.write(toFile: a[3], atomically: true, encoding: .utf8) }
if !r_valid(dsl) { print("INVALID"); exit(2) }
let css = r_css("light")!
print(String(cString: r_svg(dsl, css)!), terminator: "")
