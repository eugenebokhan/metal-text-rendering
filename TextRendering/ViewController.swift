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
    private var atlasTexture: MTLTexture!
    private var textRender: TextRender!
    private var textMesh: TextMesh!
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

        MTLCaptureManager.shared().startCapture(commandQueue: self.context.commandQueue)
        self.draw(texture: self.destinationTexture)
        MTLCaptureManager.shared().stopCapture()

        print("Hello")
    }

    // MARK: - Setup

    private func setup() throws {
        self.context = try .init()
        self.metalView = try .init(context: self.context)

        self.destinationTexture = try self.context.texture(width: self.destinationTextureSize.x,
                                                           height: self.destinationTextureSize.y,
                                                           pixelFormat: .bgra8Unorm)

        let defaultFont = "HoeflerText-Regular"
        let atlas = FontAtlas(with: UIFont(name: defaultFont,
                                           size: 32)!,
                              textureSize: FontAtlas.fontAtlasSize,
                              metalContext: self.context)
        self.atlasTexture = atlas.fontTexture

        self.textRender = try .init(context: self.context)
        self.textMesh = try .init(string: """
                                          It was the best of times, it was the worst of times,
                                          it was the age of wisdom, it was the age of foolishness...\n\n
                                          Все счастливые семьи похожи друг на друга,
                                          каждая несчастливая семья несчастлива по-своему.
                                          """,
                                  rect: .init(x: 0,
                                              y: 0,
                                              width: self.destinationTextureSize.x,
                                              height: self.destinationTextureSize.y),
                                  fontAtlas: atlas,
                                  fontSize: 20,
                                  device: self.context.device)

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
                let drawableSize = SIMD2<Int>(.init(self.metalView.drawableSize.width),
                                              .init(self.metalView.drawableSize.height))

                self.metalView.draw(texture: texture,
                                    additionalRenderCommands: { renderEncoder in
                                        self.textRender!.render(textMesh: self.textMesh,
                                                                fontTexture: self.atlasTexture,
                                                                drawableSize: drawableSize,
                                                                using: renderEncoder)
                },
                                    in: commandBuffer)
            }
        } catch { return }
    }

}

