import Foundation
import Alloy

final public class SDFInitializationPass {

    // MARK: - Properties

    public let pipelineState: MTLComputePipelineState
    private let deviceSupportsNonuniformThreadgroups: Bool

    // MARK: - Life Cycle

    public convenience init(context: MTLContext) throws {
        try self.init(library: context.library(for: Self.self))
    }

    public init(library: MTLLibrary) throws {
        self.deviceSupportsNonuniformThreadgroups = library.device
                                                           .supports(feature: .nonUniformThreadgroups)
        let constantValues = MTLFunctionConstantValues()
        constantValues.set(self.deviceSupportsNonuniformThreadgroups,
                           at: 0)
        self.pipelineState = try library.computePipelineState(function: Self.functionName,
                                                              constants: constantValues)
    }

    // MARK: - Encode

    public func encode(distanceMapTexture: MTLTexture,
                       boundaryPointMapTexture: MTLTexture,
                       maxDist: Float,
                       in commandBuffer: MTLCommandBuffer) {
        commandBuffer.compute { encoder in
            encoder.label = "SDFInitializationPass"
            self.encode(distanceMapTexture: distanceMapTexture,
                        boundaryPointMapTexture: boundaryPointMapTexture,
                        maxDist: maxDist,
                        using: encoder)
        }
    }

    public func encode(distanceMapTexture: MTLTexture,
                       boundaryPointMapTexture: MTLTexture,
                       maxDist: Float,
                       using encoder: MTLComputeCommandEncoder) {
        encoder.set(textures: [distanceMapTexture,
                               boundaryPointMapTexture])
        encoder.set(maxDist,
                    at: 0)
        if self.deviceSupportsNonuniformThreadgroups {
            encoder.dispatch2d(state: self.pipelineState,
                               exactly: distanceMapTexture.size)
        } else {
            encoder.dispatch2d(state: self.pipelineState,
                               covering: distanceMapTexture.size)
        }
    }

    public static let functionName = "sdfInitializationPhase"
}


