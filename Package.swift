// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "qwen3-tts-client",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TTSCore", targets: ["TTSCore"]),
        .library(name: "TTSEngineMLX", targets: ["TTSEngineMLX"]),
        .executable(name: "Qwen3TTSApp", targets: ["Qwen3TTSApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.3"),
        // mlx-audio-swift 的既有依赖，这里直接引用其 HubClient 做模型下载与进度回调
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.8.1"),
    ],
    targets: [
        // 无 MLX 依赖：UI 开发与测试的快速内循环（swift build / swift test 可用）
        .target(name: "TTSCore"),
        // MLX 真实推理引擎：链接 MLX 的产物必须用 xcodebuild 构建（见 CLAUDE.md）
        .target(
            name: "TTSEngineMLX",
            dependencies: [
                "TTSCore",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ]
        ),
        .executableTarget(name: "Qwen3TTSApp", dependencies: ["TTSCore", "TTSEngineMLX"]),
        .testTarget(name: "TTSCoreTests", dependencies: ["TTSCore"]),
        // AppModel 状态机测试：全程假引擎，不触发 MLX 推理（链接 MLX 但不加载 metallib）
        .testTarget(name: "AppModelTests", dependencies: ["Qwen3TTSApp"]),
    ],
    swiftLanguageModes: [.v5]
)
