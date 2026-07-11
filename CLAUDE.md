# qwen3-tts-client

macOS 原生 Qwen3-TTS 本地推理客户端。SwiftUI + SPM，macOS 14+，仅 Apple Silicon。

## 构建与测试

本机 `xcode-select` 指向 CommandLineTools，但 CLT **缺 XCTest/Swift Testing 和 Metal 编译器**（MLX 依赖 Metal kernel 编译）。所有构建/测试命令必须带完整 Xcode 工具链：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Qwen3TTSApp
```

Xcode 26 的 Metal 工具链是独立组件；如遇 `Failed to load the default metallib`，运行：
`xcodebuild -downloadComponent MetalToolchain`

**引入 MLX 依赖后**：SwiftPM 命令行无法编译 Metal shaders（mlx-swift README 明确说明），凡链接 MLX 的产物必须用 xcodebuild 构建：

```sh
xcodebuild build -scheme Qwen3TTSApp -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcbuild -clonedSourcePackagesDirPath .build \
  -skipPackagePluginValidation -skipMacroValidation
```

（`-skipPackagePluginValidation` 是必需的：mlx-swift 的 CudaBuild 插件否则会被 xcodebuild 拒绝；`-clonedSourcePackagesDirPath .build` 让 xcodebuild 复用 SPM CLI 的依赖 checkout，避免重复拉取大仓库。）

打包 .app（构建 + 组装 + ad-hoc 签名，产物在 dist/）：

```sh
scripts/package-app.sh            # 完整构建后打包
scripts/package-app.sh --skip-build  # 直接用现有 Release 产物
```

纯 TTSCore/UI 开发（FakeInferenceEngine，不链接 MLX）仍可用 `swift build` / `swift test`。

## 架构（详见 docs/generated/prd.md）

- `Sources/TTSCore` — 库：`InferenceEngine` 协议（文本+音色 → AsyncThrowingStream<AudioChunk>）是全 App 核心契约，运行时细节（MLX/Fake）必须藏在它后面；`StreamingAudioPlayer` 消费同一流。
- `Sources/Qwen3TTSApp` — SwiftUI 界面层。
- 推理运行时选型见 `docs/adr/`（spike 记录：docs/generated/spike-inference-runtime.md）。

## 约定

- UI 开发和测试一律用 `FakeInferenceEngine`，不依赖真实模型。
- 文档、注释、commit message 用中文。
