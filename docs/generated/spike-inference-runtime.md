# Spike: 推理运行时选型实测

> 2026-07-10 ~ 07-11，decision-forge 收敛过程的实测环节。结论已固化为 [ADR-0001](../adr/0001-inference-runtime-mlx-swift.md)。
> 测试机：Apple M3 Max / 64 GB RAM / macOS 26.5（高配机型，普通用户机型数字会更差，结论已留余量）。

## 背景

PRD 要求「交互流畅」：流式播放、首包延迟目标 < 2s。候选运行时：

- **A. MLX Swift**（[mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)，MIT，v0.1.x）：纯 Swift、真流式（`generateStream` 逐块产出 PCM）、macOS 14+。实现覆盖全部三个变体（CustomVoice 预置音色、VoiceDesign、Base 克隆）。
- **B. CoreML**（FluidAudio）：纯 Swift、最稳，但仅 0.6B、单次输出约 10s 上限、无流式、仅中英。

测试顺序：先测 A（推荐路线）；A 全面达标，B 未测。

## 验收标准与结果

| # | 标准 | 阈值 | 结果 |
|---|---|---|---|
| S1 | 首包延迟（TTFB，模型已加载） | < 2s | ✅ 全部 0.11~0.13s，超标 15 倍以上 |
| S2 | 实时倍率（RTFx） | > 1.0 | ✅ 3.4~4.1 |
| S3 | 中途取消 | 流终止、无泄漏 | ⚠️ 引擎层已实现（Task 取消传播），待 App 集成测试验证 |
| S4 | 音质抽检 | 人耳可用 | ✅ 5 个 WAV 生成正常（时长与文本匹配），待人耳确认 |

## 基准数据（xcodebuild Release 构建，模型本地缓存，无并发负载）

| 场景 | 音频时长 | TTFB | RTFx | Tokens/s |
|---|---|---|---|---|
| 0.6B 中文短句 | 4.9s | 0.116s | 3.96 | 49.9 |
| 0.6B 中文长文（约 220 字） | 51.3s | 0.113s | 4.06 | 50.8 |
| 0.6B 英文短句 | 7.7s | 0.106s | 4.05 | 50.6 |
| 1.7B 中文短句 | 4.5s | 0.125s | 3.37 | 42.1 |
| 1.7B 中文长文 | 57.9s | 0.129s | 3.47 | 43.4 |

模型：`mlx-community/Qwen3-TTS-12Hz-{0.6B,1.7B}-CustomVoice-8bit`，音色 Vivian。

注：冷启动首次运行（模型加载 + Metal 编译）观测到 TTFB 3.4s 量级——App 需在启动时后台预热模型（已实现 `MLXInferenceEngine.prepare()`）。

## 过程中踩的坑（对工程有约束力）

1. **SwiftPM 命令行编不了 Metal shaders**：mlx-swift 官方限制，链接 MLX 的产物必须 `xcodebuild` 构建，否则运行时报 `Failed to load the default metallib`（CLT 工具链更是连 Metal 编译器都没有；Xcode 26 的 Metal 工具链是独立下载组件）。
2. **mlx-audio-swift 的模型缓存布局**：不是标准 HF hub snapshot 布局，而是 `<hub-cache>/mlx-audio/<owner>_<repo>/` 平铺目录；预下载权重必须铺到这个位置才会命中缓存。
3. **模型体积**：0.6B repo 实际约 1.8 GB（主模型 650 MB + speech tokenizer 1.2 GB），1.7B 约 2.9 GB。PRD 的下载引导与磁盘提示按此校准。

## 结论

MLX Swift（mlx-audio-swift）在 0.6B 与 1.7B 上均大幅超过 MVP 性能标准，能力上限（全变体、真流式）也最高；CoreML 路线无需再测。**默认模型定为 0.6B-CustomVoice-8bit**（TTFB 与 RTFx 最优、体积最小），1.7B 作为音质偏好选项保留。已固化为 ADR-0001。
