# inference-runtime-mlx-swift

Status: accepted

本地推理运行时采用 MLX Swift（mlx-audio-swift），因为实测（M3 Max，8bit 量化）TTFB 0.11~0.13s、RTFx 3.4~4.1，
大幅超过 MVP 标准（首包 < 2s、RTFx > 1），且它是唯一同时满足「纯 Swift 分发 + 真流式 + 覆盖全部三个模型变体」的路线；
CoreML（FluidAudio）单次输出约 10s 上限且无流式，直接伤害「交互流畅」目标，Python sidecar 被 MLX Swift 原生实现取代后已无存在理由。

## Considered Options

MLX Swift (mlx-audio-swift, MIT, v0.1.x):
  优点: 真流式（TTFB ~0.1s）、全变体（CustomVoice/VoiceDesign/Base 克隆）、纯 Swift、macOS 14+
  缺点: v0.1.x 早期库；靠 InferenceEngine 接口隔离 + 可随时换实现兜底

CoreML (FluidAudio):
  优点: 最稳、分发最干净
  缺点: 仅 0.6B、单次约 10s 上限、无流式、仅中英——不满足流式播放核心需求

Python sidecar (mlx-audio):
  优点: 生态最成熟
  缺点: 嵌入 Python 运行时的分发复杂度；被同能力的 Swift 原生路线支配

## Consequences

- 凡链接 MLX 的产物必须用 xcodebuild 构建（SwiftPM CLI 编不了 Metal shaders）；TTSCore 保持零 MLX 依赖以保留 swift build/test 快速内循环。
- 默认模型 0.6B-CustomVoice-8bit（约 1.8 GB 磁盘），1.7B（约 2.9 GB）作音质选项；模型缓存必须铺在 `<hub-cache>/mlx-audio/<owner>_<repo>/` 平铺布局。
- 冷启动模型加载约 3s：App 启动时后台预热（MLXInferenceEngine.prepare()）。
- 实测数据与踩坑记录见 docs/generated/spike-inference-runtime.md。
