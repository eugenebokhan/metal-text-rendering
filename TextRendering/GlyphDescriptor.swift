import Foundation
import CoreGraphics
import CoreText

final class GlyphDescriptor {

    // MARK: Type Definitions

    enum CodingKey: String {
        case glyphIndex
        case leftTexCoord
        case rightTexCoord
        case topTexCoord
        case bottomTexCoord
        case fontName
        case fontSize
        case spread
        case textureData
        case textureWidth
        case textureHeight
        case glyphDescriptors
    }

    // MARK: - Properties

    var glyphIndex: CGGlyph!
    var topLeftTexCoord: CGPoint!
    var bottomRightTexCoord: CGPoint!

}

extension GlyphDescriptor: Codable { }
