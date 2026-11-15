import Foundation
import CoreImage
let context = CIContext(options: [.useSoftwareRenderer: false])
let source = CIImage(color: CIColor(red: 0.3, green: 0.6, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24))
func pixel(_ image: CIImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 10, y: 10, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    return bytes
}
var failed = 0
func check(_ condition: Bool, _ name: String) { if !condition { print("FAIL: \(name)"); failed += 1 } }
let original = pixel(source)
check(pixel(Effects.apply(source, settings: LookSettings(look: .original, grain: 0))) == original, "original preserves pixels")
for look in FilmLook.allCases where look != .original {
    let result = Effects.apply(source, settings: LookSettings(look: look, strength: 1, grain: 0))
    check(result.extent == source.extent, "\(look) keeps finite original extent")
    check(pixel(result) != original, "\(look) visibly changes pixels")
    check(pixel(Effects.apply(source, settings: LookSettings(look: look, strength: 0, grain: 0))) == original, "zero strength preserves source")
}
let mono = pixel(Effects.apply(source, settings: LookSettings(look: .noir, strength: 1, grain: 0)))
check(abs(Int(mono[0]) - Int(mono[1])) <= 1 && abs(Int(mono[1]) - Int(mono[2])) <= 1, "noir removes colour")
if failed > 0 { exit(1) }
print("All image pipeline checks passed")
