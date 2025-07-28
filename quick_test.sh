#!/bin/bash

echo "🚀 Hello Prompt v2 - 快速测试（修复循环问题）"
echo "============================================"
echo ""

echo "🔧 修复内容："
echo "   ✅ 禁用了所有可能导致循环的权限检查"
echo "   ✅ 使用简化的快捷键初始化流程"
echo "   ✅ 直接设置快捷键回调"
echo "   ✅ 绕过复杂的权限管理器"
echo ""

echo "🎯 测试重点："
echo "   1. 应用启动后不应该有循环日志"
echo "   2. 会显示直接的权限诊断信息"
echo "   3. Ctrl+U 快捷键应该有响应（如果有辅助功能权限）"
echo ""

echo "📝 关键日志标识："
echo "   🔍 '开始直接权限诊断' - 权限检查开始"
echo "   🎯 '直接设置快捷键回调' - 快捷键回调设置"
echo "   🎙️ '快捷键触发：开始录音' - 快捷键成功触发"
echo ""

# 构建并启动
echo "📦 构建应用..."
swift build 2>/dev/null

echo "🚀 启动应用..."
echo ""

./.build/debug/HelloPromptV2 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"直接权限诊断"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"直接设置快捷键回调"* ]]; then
        echo "🎯 $line"
    elif [[ "$line" == *"快捷键触发"* ]]; then
        echo "🎙️ $line"
    elif [[ "$line" == *"强制刷新核心权限"* ]]; then
        echo "⚠️  循环警告: $line"
    elif [[ "$line" == *"权限检查已暂时禁用"* ]]; then
        echo "✅ $line"
    elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"错误"* ]]; then
        echo "❌ $line"
    else
        echo "$line"
    fi
done 