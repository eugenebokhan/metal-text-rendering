import Foundation
import UIKit
import Alloy

final class FontAtlas {

    // MARK: - Properties

    var parentFont: UIFont!
    var fontPointSize: CGFloat!
    var spread: CGFloat!
    var textureSize: Int!
    var glyphDescriptors: [GlyphDescriptor] = []
    var fontImage: CGImage!
    var fontTexture: MTLTexture!
    var fontBuffer: MTLBuffer!
    var metalContext: MTLContext

    // MARK: - Init

    /// Create a signed-distance field based font atlas with the specified dimensions.
    /// The supplied font will be resized to fit all available glyphs in the texture.
    /// - Parameters:
    ///   - font: font.
    ///   - textureSize: texture size.
    init(with font: UIFont,
         textureSize: Int,
         metalContext: MTLContext) {
        self.metalContext = metalContext

        self.parentFont = font
        self.fontPointSize = font.pointSize
        self.spread = self.estimatedLineWidth(for: font) * 0.5
        self.textureSize = textureSize
        self.createTextureData()
    }

    func estimatedGlyphSize(for font: UIFont) -> CGSize {
        let string: NSString = "{ǺOJMQYZa@jmqyw"
        let stringSize = string.size(withAttributes: [NSAttributedString.Key.font : font])
        let averageGlyphWidth: CGFloat = .init(ceilf(.init(stringSize.width) / .init(string.length)))
        let maxGlyphHeight: CGFloat = .init(ceilf(.init(stringSize.height)))

        return .init(width: averageGlyphWidth,
                     height: maxGlyphHeight)
    }

    func estimatedLineWidth(for font: UIFont) -> CGFloat {
        let string: NSString = "!"
        let stringSize = string.size(withAttributes: [NSAttributedString.Key.font : font])
        return .init(ceilf(.init(stringSize.width)))
    }

    func isLikelyToFitInAtlas(font: UIFont,
                              of size: CGFloat,
                              rect: CGRect) -> Bool {
        let textureArea = rect.size.width * rect.size.height
        let trialFont = UIFont(name: font.fontName, size: size)!
        let trialCTFont = CTFontCreateWithName(font.fontName as CFString,
                                               size,
                                               nil)
        let fontGlyphCount = CTFontGetGlyphCount(trialCTFont)
        let glyphMargin = self.estimatedLineWidth(for: trialFont)
        let averageGlyphSize = self.estimatedGlyphSize(for: trialFont)
        let estimatedGlyphTotalArea = (averageGlyphSize.width + glyphMargin)
                                    * (averageGlyphSize.height + glyphMargin)
                                    * .init(fontGlyphCount)
        return estimatedGlyphTotalArea < .init(textureArea)
    }

    func pointSizeThatFits(for font: UIFont,
                           in atlasRect: CGRect) -> CGFloat {
        var fittedSize = font.pointSize
        while self.isLikelyToFitInAtlas(font: font,
                                        of: fittedSize,
                                        rect: atlasRect) {
                                            fittedSize += 1
        }

        while !self.isLikelyToFitInAtlas(font: font,
                                        of: fittedSize,
                                        rect: atlasRect) {
                                            fittedSize -= 1
        }
        return fittedSize
    }

    func createFontAtlas(for font: UIFont,
                         width: size_t,
                         height: size_t) -> [UInt8] {
        var data = [UInt8](repeating: .zero, count: width * height)

        let context = CGContext(data: &data,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGBitmapInfo.alphaInfoMask.rawValue & CGImageAlphaInfo.none.rawValue)!

        // Turn off antialiasing so we only get fully-on or fully-off pixels.
        // This implicitly disables subpixel antialiasing and hinting.
        context.setAllowsAntialiasing(false)

        // Flip context coordinate space so y increases downward
        context.translateBy(x: .zero,
                             y: .init(height))
        context.scaleBy(x: 1,
                        y: -1)

        let rect = CGRect(x: 0,
                          y: 0,
                          width: width,
                          height: height)

        // Fill the context with an opaque black color
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        self.fontPointSize = self.pointSizeThatFits(for: font,
                                                    in: rect)

        let ctFont = CTFontCreateWithName(font.fontName as CFString,
                                          self.fontPointSize,
                                          nil)
        self.parentFont = UIFont(name: font.fontName,
                                 size: self.fontPointSize)!

        let fontGlyphCount = CTFontGetGlyphCount(ctFont)

        let glyphMargin = self.estimatedLineWidth(for: self.parentFont)

        // Set fill color so that glyphs are solid white
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)

        let fontAscent = CTFontGetAscent(ctFont)
        let fontDescent = CTFontGetDescent(ctFont)

        var origin = CGPoint(x: 0, y: fontAscent)

        var maxYCoordForLine: CGFloat = -1

        let glyphs = (0 ..< fontGlyphCount).map { CGGlyph($0) }

        for var glyph in glyphs {
            var boundingRect = CGRect()

            CTFontGetBoundingRectsForGlyphs(ctFont,
                                            .horizontal,
                                            &glyph,
                                            &boundingRect,
                                            1)

            if (origin.x + boundingRect.maxX + glyphMargin) > .init(width) {
                origin.x = 0
                origin.y = maxYCoordForLine + glyphMargin + fontDescent
                maxYCoordForLine = -1
            }

            if (origin.y + boundingRect.maxY) > maxYCoordForLine {
                maxYCoordForLine = origin.y + boundingRect.maxY
            }

            let glyphOriginX = origin.x - boundingRect.origin.x + (glyphMargin * 0.5)
            let glyphOriginY = origin.y + (glyphMargin * 0.5)
            var glyphTransform = CGAffineTransform(a: 1,
                                                   b: 0,
                                                   c: 0,
                                                   d: -1,
                                                   tx: glyphOriginX,
                                                   ty: glyphOriginY)

            var glyphPathBoundingRect: CGRect = .zero

            if let path = CTFontCreatePathForGlyph(ctFont,
                                                   glyph,
                                                   &glyphTransform) {

                context.addPath(path)
                context.fillPath()

                glyphPathBoundingRect = path.boundingBoxOfPath
            }

            let texCoordLeft = glyphPathBoundingRect.origin.x / .init(width)
            let texCoordRight = (glyphPathBoundingRect.origin.x + glyphPathBoundingRect.size.width) / .init(width)
            let texCoordTop = (glyphPathBoundingRect.origin.y) / .init(height)
            let texCoordBottom = (glyphPathBoundingRect.origin.y + glyphPathBoundingRect.size.height) / .init(height)

            let descriptor = GlyphDescriptor()
            descriptor.glyphIndex = glyph
            descriptor.topLeftTexCoord = .init(x: texCoordLeft, y: texCoordTop)
            descriptor.bottomRightTexCoord = .init(x: texCoordRight, y: texCoordBottom)
            self.glyphDescriptors.append(descriptor)

            origin.x += boundingRect.width + glyphMargin
        }

        self.fontImage = context.makeImage()!
        self.fontTexture = try! self.metalContext.texture(from: self.fontImage)

        return data
    }

    func createTextureData() {
        let fontData =  self.createFontAtlas(for: self.parentFont,
                                             width: Self.fontAtlasSize,
                                             height: Self.fontAtlasSize)

        let scaleFactor = 2

        let textureWidth = Int(Self.fontAtlasSize) / scaleFactor
        let textureHeight = Int(Self.fontAtlasSize) / scaleFactor

        let pixelRowAlignment = self.metalContext.device.minimumTextureBufferAlignment(for: .r32Float)
        let bytesPerRow = alignUp(size: textureWidth, align: pixelRowAlignment)

        let sdf = self.createSignedDistanceFieldForGrayscaleImage(imageData: fontData,
                                                                  width: Self.fontAtlasSize,
                                                                  height: Self.fontAtlasSize)
        var resampledSDF = self.createResampledData(in: sdf,
                                                    width: textureWidth,
                                                    height: textureHeight,
                                                    scaleFactor: scaleFactor)

        let texture = try! self.metalContext.texture(width: textureWidth,
                                                     height: textureHeight,
                                                     pixelFormat: .r32Float,
                                                     usage: [.shaderRead, .shaderWrite])



        texture.replace(region: texture.region,
                        mipmapLevel: 0,
                        withBytes: &resampledSDF,
                        bytesPerRow: bytesPerRow * 4)

        self.fontTexture = texture

        print("HI!")
    }

    static let fontAtlasSize: size_t = 8

}
