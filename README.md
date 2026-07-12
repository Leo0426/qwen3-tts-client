# Qwen3 TTS for macOS

macOS 原生的 Qwen3-TTS 本地推理客户端。完全离线运行——文本不离开你的 Mac，无需 API Key，无按量计费。

## 功能

- **流式合成**：边生成边播放，M 系列芯片上首包约 0.1 秒（实测 M3 Max，8bit 量化）
- **9 个官方预置音色** + 中文方言（北京话、四川话）+ 10 语种
- **声音克隆**：3 秒以上参考音频 + 文字稿即可复刻音色
- **风格指令**：如「用温柔的语气慢慢说」，每次合成级别的情感/语气控制
- **长文本**：按句子边界自动分段，整篇文章无缝连续播放
- **模型下载中心**：官方 / 镜像 / 自定义下载源，自定义存储路径，下载进度与磁盘管理
- **细粒度配置**：模型规格（0.6B 快 / 1.7B 音质好）、采样参数、流式分块策略、内存加载管理
- 历史记录持久化、WAV 导出

## 系统要求

- Apple Silicon（M1 及以上）
- macOS 14+
- 磁盘：每个模型约 1.8 ~ 3 GB；内存：加载一个模型约 2 GB

## 构建

需要完整 Xcode（含 Metal 工具链——mlx-swift 的限制，SwiftPM 命令行编不了 Metal shaders）：

```sh
# 打包 .app（构建 + 组装 + ad-hoc 签名，产物在 dist/）
scripts/package-app.sh

# 开发内循环（TTSCore/UI，不涉及 MLX）
swift test
QWEN3TTS_FAKE_ENGINE=1 swift run Qwen3TTSApp   # 假引擎跑 UI
```

更多构建细节见 [CLAUDE.md](CLAUDE.md)。

## 架构

```
Sources/
├── TTSCore/        # 零 MLX 依赖：InferenceEngine 契约、流式播放、分段、持久化
├── TTSEngineMLX/   # MLX 推理引擎 + 模型下载管理（唯一接触 MLX 的模块）
└── Qwen3TTSApp/    # SwiftUI 界面层
```

核心契约是 `InferenceEngine`：文本 + 音色 + 选项 → 异步音频块流。运行时细节全部隐藏在接口后面（选型依据见 [ADR-0001](docs/adr/0001-inference-runtime-mlx-swift.md)，实测数据见 [spike 记录](docs/generated/spike-inference-runtime.md)）。

## 致谢

- [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS)（Apache 2.0）— 通义千问开源 TTS 模型
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)（MIT）— Apple Silicon 原生推理运行时
- 量化权重来自 [mlx-community](https://huggingface.co/mlx-community)
