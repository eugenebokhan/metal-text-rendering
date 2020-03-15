import Alloy
import SwiftMath

final class TextRender {

    // MARK: - Propertires

    public let pipelineState: MTLRenderPipelineState
    public let sampler: MTLSamplerState
    public let uniformBuffer: MTLBuffer

    // MARK: - Life Cycle

    public convenience init(context: MTLContext,
                            scalarType: MTLPixelFormat.ScalarType = .half) throws {
        try self.init(library: context.library(for: Self.self),
                      scalarType: scalarType)
    }

    public init(library: MTLLibrary,
                scalarType: MTLPixelFormat.ScalarType = .half) throws {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToZero
        samplerDescriptor.tAddressMode = .clampToZero
        guard let sampler = library.device.makeSamplerState(descriptor: samplerDescriptor)
        else { throw MetalError.MTLDeviceError.samplerStateCreationFailed }
        self.sampler = sampler

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].setup(blending: .alpha)

        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        pipelineDescriptor.vertexFunction = library.makeFunction(name: Self.vertexFunctionName)
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: Self.fragmentFunctionName)
        pipelineDescriptor.vertexDescriptor = Self.vertexDescriptor()

        self.pipelineState = try library.device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        self.uniformBuffer = try library.device.buffer(with: Uniforms(),
                                                       options: .storageModeShared)
    }

    func updateUniforms(with drawableSize: SIMD2<Int>) {
        var uniforms = Uniforms()
        uniforms.modelMatrix = .init(Matrix4x4f.identity)

        let ortho = Matrix4x4f.ortho(left: 0,
                                     right: .init(drawableSize.x),
                                     bottom: .init(drawableSize.y),
                                     top: 0,
                                     near: 0,
                                     far: 1)
        uniforms.viewProjectionMatrix = .init(ortho)

        uniforms.foregroundColor = .init(1, 0, 0, 1)

        memcpy(self.uniformBuffer.contents(),
               &uniforms,
               MemoryLayout<Uniforms>.stride)
    }

    // MARK: - Draw

    public func render(textMesh: TextMesh,
                       fontTexture: MTLTexture,
                       drawableSize: SIMD2<Int>,
                       renderPassDescriptor: MTLRenderPassDescriptor,
                       commandBuffer: MTLCommandBuffer) throws {
        commandBuffer.render(descriptor: renderPassDescriptor,
                             { renderEncoder in
                                self.render(textMesh: textMesh,
                                            fontTexture: fontTexture,
                                            drawableSize: drawableSize,
                                            using: renderEncoder)
        })
    }

    public func render(textMesh: TextMesh,
                       fontTexture: MTLTexture,
                       drawableSize: SIMD2<Int>,
                       using renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Draw Text Geometry")
        defer { renderEncoder.popDebugGroup() }

        self.updateUniforms(with: drawableSize)

        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(self.pipelineState)

        renderEncoder.setVertexBuffer(textMesh.vertexBuffer,
                                      offset: 0,
                                      index: 0)
        renderEncoder.setVertexBuffer(self.uniformBuffer,
                                      offset: 0,
                                      index: 1)

        renderEncoder.setFragmentBuffer(self.uniformBuffer,
                                        offset: 0,
                                        index: 0)
        renderEncoder.setFragmentTexture(fontTexture,
                                         index: 0)
        renderEncoder.setFragmentSamplerState(self.sampler,
                                              index: 0)

        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: textMesh.indexBuffer.length / MemoryLayout<UInt16>.stride,
                                            indexType: .uint16,
                                            indexBuffer: textMesh.indexBuffer,
                                            indexBufferOffset: 0)
    }

    public static func vertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        // Position
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Texture coordinates
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride

        return vertexDescriptor
    }

    public static let vertexFunctionName = "vertex_shade"
    public static let fragmentFunctionName = "fragment_shade"
}
