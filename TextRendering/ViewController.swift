import UIKit
import SnapKit
import Alloy
import MetalView

class ViewController: UIViewController {

    // MARK: - Properties

    // UI
    private var metalView: MetalView!
    // Core
    private var context: MTLContext!
    private var atlasProvider: MTLFontAtlasProvider!
    private var textRender: TextRender!
    private var destinationTexture: MTLTexture!

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        do { try self.setup() }
        catch { fatalError() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.setupTextRender()
        self.draw(texture: self.destinationTexture)
    }

    // MARK: - Setup

    private func setup() throws {
        self.context = try .init()
        self.metalView = try .init(context: self.context)
        self.metalView.contentScaleFactor = UIScreen.main.scale

        let screenBounds = UIScreen.main.nativeBounds
        self.destinationTexture = try self.context
                                          .texture(width: .init(screenBounds.width),
                                                   height: .init(screenBounds.height),
                                                   pixelFormat: .bgra8Unorm)

        self.atlasProvider = try MTLFontAtlasProvider(context: self.context)
        let fontAtlas = try self.atlasProvider
                                .fontAtlas(descriptor: MTLFontAtlasProvider.defaultAtlasDescriptor)
        self.textRender = try .init(context: self.context,
                                    fontAtlas: fontAtlas)
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

    private func setupTextRender() {
        self.textRender.renderTargetSize = self.destinationTexture.size
        self.textRender.geometryDescriptors = [
            .init(text: "It’s time to kick ass and chew bubble gum...and I’m all outta gum.",
                  normalizedRect: .init(origin: .init(x: 0.25, y: 0.25),
                                        size: .init(width: 0.5,
                                                    height: 0.5)),
                  color: UIColor.red.cgColor)
        ]
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

