#!/bin/bash

echo "🎯 测试音频格式修复..."

# 编译并运行应用
echo "📦 编译应用..."
cd v2
swift build --configuration release

if [ $? -eq 0 ]; then
    echo "✅ 编译成功"
    
    echo "🎵 启动应用进行音频测试..."
    echo "请注意观察日志中："
    echo "1. 是否还有 'ExtAudioFileWrite' 错误"
    echo "2. 录音格式是否正确显示为 '16位PCM'"
    echo "3. 音频缓冲区处理是否正常"
    echo ""
    echo "按 Ctrl+C 停止测试"
    
    # 过滤关键的音频相关日志
    .build/release/HelloPromptV2 2>&1 | grep -E "(录音格式|AudioBufferProcessing|ExtAudioFileWrite|音频缓冲区|writeAudioBuffer|录音文件|AudioService.*初始化)"
else
    echo "❌ 编译失败"
    exit 1
fi 