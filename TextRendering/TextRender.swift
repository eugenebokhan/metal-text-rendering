import Alloy
import SwiftMath

final class TextRender {

    public class TextMeshDescriptor: Equatable {
        let text: String
        let normalizedRect: CGRect
        let fontSize: CGFloat

        public init(text: String,
                    rect: CGRect,
                    fontSize: CGFloat) {
            self.text = text
            self.normalizedRect = rect
            self.fontSize = fontSize
        }

        public static func == (lhs: TextRender.TextMeshDescriptor,
                               rhs: TextRender.TextMeshDescriptor) -> Bool {
            return lhs.text == rhs.text
                && lhs.normalizedRect == rhs.normalizedRect
                && lhs.fontSize == rhs.fontSize
        }
    }

    // MARK: - Propertires

    public let pipelineState: MTLRenderPipelineState
    public let sampler: MTLSamplerState
    public var color: SIMD4<Float> = .init(repeating: 1)
    private let fontAtlas: MTLFontAtlas

    /// Render taregt texture size.
    public var renderTargetSize: MTLSize = .zero {
        didSet {
            if self.renderTargetSize != oldValue {
                let ortho = Matrix4x4f.ortho(left: 0,
                                             right: .init(self.renderTargetSize
                                                              .width),
                                             bottom: .init(self.renderTargetSize
                                                               .height),
                                             top: 0,
                                             near: 0,
                                             far: 1)
                self.projectionMatrix = .init(ortho)
            }
        }
    }

    public var textMeshDescriptor: TextMeshDescriptor? = nil {
        didSet {
            if let descriptor = self.textMeshDescriptor,
                descriptor != oldValue {
                self.setNeedsUpdateTextMesh()
            }
        }
    }
    
    private var textMesh: MTLTextMesh? = nil
    private var projectionMatrix = matrix_identity_float4x4
    private var needsUpdateTextMesh: Bool = true

    // MARK: - Life Cycle

    public convenience init(context: MTLContext,
                            fontAtlas: MTLFontAtlas,
                            scalarType: MTLPixelFormat.ScalarType = .half) throws {
        try self.init(library: context.library(for: Self.self),
                      fontAtlas: fontAtlas,
                      scalarType: scalarType)
    }

    public init(library: MTLLibrary,
                fontAtlas: MTLFontAtlas,
                scalarType: MTLPixelFormat.ScalarType = .half) throws {
        self.fontAtlas = fontAtlas
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
    }

    private func setNeedsUpdateTextMesh() {
         self.needsUpdateTextMesh = true
     }

    // MARK: - Draw

    public func render(renderPassDescriptor: MTLRenderPassDescriptor,
                       commandBuffer: MTLCommandBuffer) throws {
        self.renderTargetSize = renderPassDescriptor.colorAttachments[0].texture?.size ?? .zero
        commandBuffer.render(descriptor: renderPassDescriptor,
                             self.render(using:))
    }

    public func render(using renderEncoder: MTLRenderCommandEncoder) {
        guard let textMeshDescriptor = self.textMeshDescriptor
        else { return }

        if self.needsUpdateTextMesh {
            let normalizedRect = textMeshDescriptor.normalizedRect
            let renderLayerWidth = CGFloat(self.renderTargetSize.width)
            let renderLayerHeight = CGFloat(self.renderTargetSize.height)
            let rect = CGRect(x: normalizedRect.origin.x * renderLayerWidth,
                              y: normalizedRect.origin.y * renderLayerHeight,
                              width: normalizedRect.size.width * renderLayerWidth,
                              height: normalizedRect.size.height * renderLayerHeight)
            self.textMesh = try? .init(string: textMeshDescriptor.text,
                                       rect: rect,
                                       fontAtlas: self.fontAtlas,
                                       fontSize: textMeshDescriptor.fontSize,
                                       device: self.pipelineState.device)
        }

        guard let textMesh = self.textMesh
        else { return }
        
        renderEncoder.pushDebugGroup("Draw Text Geometry")
        defer { renderEncoder.popDebugGroup() }

        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(self.pipelineState)
        renderEncoder.setVertexBuffer(textMesh.vertexBuffer,
                                      offset: 0,
                                      index: 0)
        renderEncoder.setVertexBytes(&self.projectionMatrix,
                                     length: MemoryLayout<matrix_float4x4>.stride,
                                     index: 1)

        renderEncoder.setFragmentTexture(self.fontAtlas
                                             .fontAtlasTexture,
                                         index: 0)
        renderEncoder.setFragmentBytes(&self.color,
                                       length: MemoryLayout<SIMD4<Float>>.stride,
                                       index: 0)
        renderEncoder.setFragmentSamplerState(self.sampler,
                                              index: 0)

        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: textMesh.indexBuffer.length / MemoryLayout<UInt16>.stride,
                                            indexType: .uint16,
                                            indexBuffer: textMesh.indexBuffer,
                                            indexBufferOffset: 0)
    }

    private static func vertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextMeshVertex>.stride
        return vertexDescriptor
    }

    public static let vertexFunctionName = "vertex_shade"
    public static let fragmentFunctionName = "fragment_shade"
}
