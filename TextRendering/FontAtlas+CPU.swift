import Foundation
import Alloy

extension FontAtlas {

    /// Compute signed-distance field for an 8-bpp grayscale image (values greater than 127 are considered "on")
       /// For details of this algorithm, see "The 'dead reckoning' signed distance transform" [Grevera 2004]
       private func createSignedDistanceFieldForGrayscaleImage(imageData: UnsafeMutablePointer<UInt8>,
                                                               width: Int,
                                                               height: Int) -> [Float] {
           let maxDist = hypot(Float(width), Float(height))
           // Initialization phase
           // distance to nearest boundary point map - set all distances to "infinity"
           var distanceMap = [Float](repeating: maxDist, count: width * height)
           // nearest boundary point map - zero out nearest boundary point map
           var boundaryPointMap = [SIMD2<Int32>](repeating: .zero, count: width * height)
           let distUnit :Float = 1
           let distDiag :Float = sqrtf(2)
           // Immediate interior/exterior phase: mark all points along the boundary as such
           for y in 1..<(height-1) {
               for x in 1..<(width-1) {
                   let inside = imageData[y * width + x] > 0x7f
                   if (imageData[y * width + x - 1] > 0x7f) != inside
                       || (imageData[y * width + x + 1] > 0x7f) != inside
                       || (imageData[(y - 1) * width + x] > 0x7f) != inside
                       || (imageData[(y + 1) * width + x] > 0x7f) != inside {
                       distanceMap[y * width + x] = 0
                       boundaryPointMap[y * width + x].x = Int32(x)
                       boundaryPointMap[y * width + x].y = Int32(y)
                   }
               }
           }
           // Forward dead-reckoning pass
           for y in 1..<(height-2) {
               for x in 1..<(width-2) {
                   let d = distanceMap[y * width + x]
                   let n = boundaryPointMap[y * width + x]
                   let h = hypot(Float(x) - Float(n.x), Float(y) - Float(n.y))
                   if distanceMap[(y - 1) * width + x - 1] + distDiag < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y - 1) * width + (x - 1)]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[(y - 1) * width + x] + distUnit < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y - 1) * width + x]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[(y - 1) * width + x + 1] + distDiag < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y - 1) * width + (x + 1)]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[y * width + x - 1] + distUnit < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[y * width + (x - 1)]
                       distanceMap[y * width + x] = h
                   }
               }
           }
           // Backward dead-reckoning pass
           for y in (1...(height-2)).reversed() {
               for x in (1...(width-2)).reversed() {
                   let d = distanceMap[y * width + x]
                   let n = boundaryPointMap[y * width + x]
                   let h = hypot(Float(x) - Float(n.x), Float(y) - Float(n.y))
                   if distanceMap[y * width + x + 1] + distUnit < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[y * width + x + 1]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[(y + 1) * width + x - 1] + distDiag < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y + 1) * width + x - 1]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[(y + 1) * width + x] + distUnit < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y + 1) * width + x]
                       distanceMap[y * width + x] = h
                   }
                   if distanceMap[(y + 1) * width + x + 1] + distDiag < d {
                       boundaryPointMap[y * width + x] = boundaryPointMap[(y + 1) * width + x + 1]
                       distanceMap[y * width + x] = h
                   }
               }
           }
           // Interior distance negation pass; distances outside the figure are considered negative
           for y in 0..<height {
               for x in 0..<width {
                   if imageData[y * width + x] <= 0x7f {
                       distanceMap[y * width + x] = -distanceMap[y * width + x]
                   }
               }
           }
           return distanceMap
       }


       func createResampledData(in inData: [Float],
                                width: size_t,
                                height: size_t,
                                scaleFactor: size_t) -> [Float] {
           assert(width % scaleFactor == 0 && height % scaleFactor == 0,
           "Scale factor does not evenly divide width and height of source distance field")

           let scaledWidth = width / scaleFactor
           let scaledHeight = height / scaleFactor

           var outData = [Float](repeating: 0, count: scaledWidth * scaledHeight)

           var y: size_t = 0
           var x: size_t = 0
           while y < height {
               while x < height {

                   var accum: Float = 0
                   for ky in 0 ..< scaleFactor {
                       for kx in 0 ..< scaleFactor {
                           accum += inData[(y + ky) * width + (x + kx)]
                       }
                   }
                   accum = accum / .init((scaleFactor * scaleFactor))

                   outData[(y / scaleFactor) * scaledWidth + (x / scaleFactor)] = accum

                   x += scaleFactor
               }
               y += scaleFactor
           }

           return outData
       }

       func createQuantizedDistanceField(_ inData: [Float],
                                         width: size_t,
                                         height: size_t,
                                         normalizationFactor: Float) {
           let pixelRowAlignment = self.metalContext.device.minimumTextureBufferAlignment(for: .r8Unorm)
           let bytesPerRow = alignUp(size: width, align: pixelRowAlignment)

           let pagesize = Int(getpagesize())
           let allocationSize = alignUp(size: bytesPerRow * height, align: pagesize)
           var outData: UnsafeMutableRawPointer! = nil
           let result = posix_memalign(&outData, pagesize, allocationSize)
           if result != noErr {
               fatalError("Error during memory allocation")
           }


           for y in 0 ..< height {
               for x in 0 ..< width {
                   let dist = inData[y * width + x]
                   let clampDist = fmax(-normalizationFactor, fmin(dist, normalizationFactor))
                   let scaledDist = clampDist / normalizationFactor
                   let value = ((scaledDist + 1) / 2) * Float(UINT8_MAX)
                   print(value)
                   outData.assumingMemoryBound(to: UInt8.self)[y * width + x] = UInt8(value)
               }
           }

           let buffer = self.metalContext
                            .device
                            .makeBuffer(bytesNoCopy: outData,
                                        length: allocationSize,
                                        options: .storageModeShared,
                                        deallocator: { pointer, length in  })!

           let textureDescriptor = MTLTextureDescriptor()
           textureDescriptor.pixelFormat = .r8Unorm
           textureDescriptor.width = width
           textureDescriptor.height = height
           textureDescriptor.storageMode = buffer.storageMode
           // we are only going to read from this texture on GPU side
           textureDescriptor.usage = [.shaderRead, .shaderWrite]

           self.fontTexture = buffer.makeTexture(descriptor: textureDescriptor,
                                                 offset: 0,
                                                 bytesPerRow: bytesPerRow)
       }

}
