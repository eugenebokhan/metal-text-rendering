import UIKit
import SnapKit
import MetalRenderingTools
import TextureView

class ViewController: UIViewController {

    // MARK: - Properties

    // UI
    private var textureView: TextureView!
    // Core
    private var context: MTLContext!
    private var atlasProvider: MTLFontAtlasProvider!
    private var textRender: TextRender!

    // MARK: - Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        try! self.setup()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.setupTextRender()
        self.draw()
    }

    // MARK: - Setup

    private func setup() throws {
        let screenBounds = UIScreen.main.nativeBounds
        self.context = try .init()
        self.textureView = try .init(
            device: self.context.device,
            pixelFormat: .bgra8Unorm
        )
        self.textureView.contentScaleFactor = UIScreen.main.scale
        self.textureView.texture = try self.context.texture(
            width: .init(screenBounds.width),
            height: .init(screenBounds.height),
            pixelFormat: .bgra8Unorm
        )

        self.atlasProvider = try MTLFontAtlasProvider(context: self.context)
        let fontAtlas = try self.atlasProvider.fontAtlas(
            descriptor: MTLFontAtlasProvider.defaultAtlasDescriptor
        )
        self.textRender = try .init(
            context: self.context,
            fontAtlas: fontAtlas
        )
        self.setupUI()
    }

    private func setupUI() {
        self.textureView.layer.cornerRadius = 10
        self.textureView.layer.masksToBounds = true

        self.view.addSubview(self.textureView)

        self.textureView.snp.makeConstraints { constraintMaker in
            constraintMaker.top.equalToSuperview().inset(40)
            constraintMaker.bottom.equalToSuperview().inset(40)
            constraintMaker.trailing.leading.equalToSuperview()
        }
    }

    private func setupTextRender() {
        guard let texture = self.textureView.texture
        else { return }
        self.textRender.renderTargetSize = texture.size
        self.textRender.geometryDescriptors = [
            .init(text: "It’s time to kick ass and chew bubble gum...and I’m all outta gum.",
                  normalizedRect: .init(
                    origin: .init(
                        x: 0.25,
                        y: 0.25
                    ),
                    size: .init(
                        width: 0.5,
                        height: 0.5
                    )
                  ),
                  color: UIColor.red.cgColor)
        ]
    }

    // MARK: - Draw

    private func draw() {
        try? self.context.schedule { commandBuffer in
            self.textureView.draw(
                additionalRenderCommands: self.textRender.render(using:),
                in: commandBuffer
            )
        }
    }

}

