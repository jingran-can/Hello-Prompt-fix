#!/bin/bash

echo "🎯 测试音频格式修复 v2..."

# 编译应用
echo "📦 重新编译应用..."
cd v2
swift build --configuration release

if [ $? -eq 0 ]; then
    echo "✅ 编译成功"
    
    echo ""
    echo "🎵 测试要点："
    echo "1. 应该看到硬件格式和目标格式的日志"
    echo "2. 不应该再有 ExtAudioFileWrite 错误"
    echo "3. 音频缓冲区写入应该成功"
    echo "4. 格式转换日志应该显示成功"
    echo ""
    echo "按 Ctrl+C 停止测试"
    echo "启动后请点击 '测试快捷键录音' 按钮"
    echo ""
    
    # 启动应用并过滤音频相关日志
    .build/release/HelloPromptV2 2>&1 | grep -E "(硬件格式|目标格式|文件格式|音频缓冲区写入|格式转换|ExtAudioFileWrite|AudioBufferProcessing|录音文件)"
else
    echo "❌ 编译失败"
    exit 1
fi 