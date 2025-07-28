#!/bin/bash

echo "🔧 Hello Prompt v2 - 修复后的快捷键测试"
echo "========================================="
echo ""

# 检查系统
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ 此应用只能在macOS上运行"
    exit 1
fi

echo "📋 修复内容：" 
echo "   ✅ 移除了权限管理器的死循环调用"
echo "   ✅ 禁用了权限监控定时器"
echo "   ✅ 使用简化的快捷键初始化流程"
echo "   ✅ 直接检查辅助功能权限"
echo ""

echo "🎯 测试步骤："
echo "   1. 应用启动时会显示权限诊断信息"
echo "   2. 如果辅助功能权限未授权，会显示详细的解决步骤"
echo "   3. 按下 Ctrl+U 测试快捷键（应该有详细的事件日志）"
echo "   4. 松开 Ctrl+U 应该触发停止录音"
echo ""

echo "📝 查看关键日志："
echo "   - '🔐 直接权限检查' - 显示权限状态"
echo "   - '🎹 检测到U键事件' - 确认按键被接收"
echo "   - '🎯 Ctrl+U按下事件已识别' - 确认快捷键被识别"
echo "   - '🎙️ Ctrl+U快捷键触发' - 确认回调被调用"
echo ""

echo "🚀 启动修复后的应用..."
echo ""

# 启动应用并高亮重要日志
./.build/debug/HelloPromptV2 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"🔐 直接权限检查"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"权限诊断"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"🎹 检测到U键事件"* ]]; then
        echo "⌨️  $line"
    elif [[ "$line" == *"🎯 Ctrl+U"* ]]; then
        echo "🎯 $line"
    elif [[ "$line" == *"🎙️ Ctrl+U快捷键触发"* ]]; then
        echo "🎙️ $line"
    elif [[ "$line" == *"🛑 Ctrl+U快捷键释放"* ]]; then
        echo "🛑 $line"
    elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"错误"* ]]; then
        echo "❌ $line"
    elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"警告"* ]]; then
        echo "⚠️  $line"
    elif [[ "$line" == *"强制刷新核心权限"* ]]; then
        echo "⚠️  循环检测: $line"
    else
        echo "$line"
    fi
done 