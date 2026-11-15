import Foundation
import CoreImage

enum FilmLook: String, CaseIterable, Codable, Identifiable {
    case original = "Original", daylight = "Daylight", golden = "Golden", faded = "Faded", noir = "Noir", tape = "Tape"
    var id: String { rawValue }
}
struct LookSettings: Codable, Equatable {
    var look: FilmLook = .daylight
    var strength: Double = 0.8
    var grain: Double = 0.12
    var warmth: Double = 0
    var dateStamp = false
}
enum Effects {
    static func apply(_ image: CIImage, settings: LookSettings) -> CIImage {
        let extent = image.extent
        var styled = image
        switch settings.look {
        case .original: break
        case .daylight:
            styled = styled.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.90, "inputContrast": 1.08])
            styled = styled.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6100, y: 5)])
        case .golden:
            styled = styled.applyingFilter("CIPhotoEffectTransfer")
        case .faded:
            styled = styled.applyingFilter("CIPhotoEffectFade")
        case .noir:
            styled = styled.applyingFilter("CIPhotoEffectNoir")
        case .tape:
            styled = styled.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.65, "inputContrast": 1.16, "inputBrightness": 0.025])
            styled = styled.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(0.3, extent.width / 1600)])
        }
        let strength = min(max(settings.strength.isFinite ? settings.strength : 0, 0), 1)
        if settings.look != .original {
            styled = styled.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": image, "inputTime": 1 - strength])
        }
        let warmth = min(max(settings.warmth.isFinite ? settings.warmth : 0, -1), 1)
        if warmth != 0 {
            styled = styled.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - warmth * 2000, y: 0)])
        }
        let grain = min(max(settings.grain.isFinite ? settings.grain : 0, 0), 1)
        if grain > 0, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let mono = noise.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0])
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: grain * 0.22)])
                .cropped(to: extent)
            styled = mono.applyingFilter("CISoftLightBlendMode", parameters: ["inputBackgroundImage": styled])
        }
        return styled.cropped(to: extent)
    }
}
