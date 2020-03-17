import UIKit
import SnapKit
import Alloy
import MetalView
import MetalPerformanceShaders
import SettingsViewController

class ViewController: UIViewController {

    // MARK: - Properties

    // UI
    private var metalView: MetalView!
    // Core
    private var context: MTLContext!
    private var atlasProvider: MTLFontAtlasProvider!
    private var textRender: TextRender!
    private var destinationTexture: MTLTexture!
    private let screenBounds = UIScreen.main.nativeBounds
    private var destinationTextureSize: SIMD2<Int> {
        .init(.init(self.screenBounds.width),
              .init(self.screenBounds.height))
    }

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        do { try self.setup() }
        catch { fatalError() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let drawableSize = MTLSize(width: self.destinationTextureSize.x,
                                   height: self.destinationTextureSize.y,
                                   depth: 0)
        self.textRender.renderTargetSize = drawableSize
        self.textRender.textMeshDescriptor = .init(text: "Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good Damn, I'm good ",
                                                   rect: .init(origin: .init(x: 0.25, y: 0.25),
                                                               size: .init(width: 0.5,
                                                                           height: 0.5)),
                                                   fontSize: 70)
        self.draw(texture: self.destinationTexture)
    }

    // MARK: - Setup

    private func setup() throws {
        self.context = try .init()
        self.metalView = try .init(context: self.context)
        self.metalView.contentScaleFactor = UIScreen.main.scale

        self.destinationTexture = try self.context
                                          .texture(width: self.destinationTextureSize.x,
                                                   height: self.destinationTextureSize.y,
                                                   pixelFormat: .bgra8Unorm)

        self.atlasProvider = try MTLFontAtlasProvider(context: self.context)
        let fontAtlas = try self.atlasProvider
                                .fontAtlas(descriptor: .init(fontName: "HelveticaNeue",
                                                             textureSize: 2048))
        self.textRender = try .init(context: self.context,
                                    fontAtlas: fontAtlas)

        let fontAtlasCodable = try fontAtlas.codable()
        let jsonEncoder = JSONEncoder()
        let fontAtlasData = try jsonEncoder.encode(fontAtlasCodable)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]

        let fileURL = documentsDirectory.appendingPathComponent("HelveticaNeue.mtlfontatlas")
        try fontAtlasData.write(to: fileURL)

        self.setupUI()
    }

    private func setupUI() {
        self.metalView.layer.cornerRadius = 10
        self.metalView.layer.masksToBounds = true

        self.view.addSubview(self.metalView)

        self.metalView.snp.makeConstraints { constraintMaker in
            constraintMaker.top.equalToSuperview().inset(40)
            constraintMaker.bottom.equalToSuperview().inset(40)
            constraintMaker.trailing.leading.equalToSuperview()
        }
    }

    // MARK: - Draw

    private func draw(texture: MTLTexture) {
        do {
            try self.context.schedule { commandBuffer in
                self.metalView.draw(texture: texture,
                                    additionalRenderCommands: (self.textRender.render(using:)),
                                    in: commandBuffer)
            }
        } catch { return }
    }

}

