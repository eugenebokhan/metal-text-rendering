//
//import Foundation

//
//let maxDist = hypot(Float(width), Float(height))
//let distUnit: Float = 1
//let distDiag: Float = sqrtf(2)
//
//let distanceMapTexture = try! self.metalContext.texture(width: Self.fontAtlasSize,
//                                                        height: Self.fontAtlasSize,
//                                                        pixelFormat: .rgba32Float,
//                                                        usage: [.shaderRead, .shaderWrite])
//let boundaryPointMapTexture = try! self.metalContext.texture(width: Self.fontAtlasSize,
//                                                             height: Self.fontAtlasSize,
//                                                             pixelFormat: .rgba8Uint,
//                                                             usage: [.shaderRead, .shaderWrite])
//
//
//MTLCaptureManager.shared().startCapture(commandQueue: self.metalContext.commandQueue)
//try! self.metalContext.scheduleAndWait { commandBuffer in
//    self.sdfInitializationPass.encode(distanceMapTexture: distanceMapTexture,
//                                      boundaryPointMapTexture: boundaryPointMapTexture,
//                                      maxDist: maxDist,
//                                      in: commandBuffer)
//
//    self.sdfInteriorExteriorPass.encode(atlasTexture: self.fontTexture,
//                                        distanceMapTexture: distanceMapTexture,
//                                        boundaryPointMapTexture: boundaryPointMapTexture,
//                                        maxDist: maxDist,
//                                        in: commandBuffer)
//
//    self.sdfForwardDeadReckoningPass.encode(atlasTexture: self.fontTexture,
//                                            distanceMapTexture: distanceMapTexture,
//                                            boundaryPointMapTexture: boundaryPointMapTexture,
//                                            maxDist: maxDist,
//                                            distDiag: distDiag,
//                                            distUnit: distUnit,
//                                            in: commandBuffer)
//
//    self.sdfBackwardDeadReckoningPass.encode(atlasTexture: self.fontTexture,
//                                             distanceMapTexture: distanceMapTexture,
//                                             boundaryPointMapTexture: boundaryPointMapTexture,
//                                             maxDist: maxDist,
//                                             distDiag: distDiag,
//                                             distUnit: distUnit,
//                                             in: commandBuffer)
//
//    self.sdfInteriorExteriorPass.encode(atlasTexture: self.fontTexture,
//                                        distanceMapTexture: distanceMapTexture,
//                                        boundaryPointMapTexture: boundaryPointMapTexture,
//                                        maxDist: maxDist,
//                                        in: commandBuffer)
//
//
//}
//
//
//MTLCaptureManager.shared().stopCapture()
