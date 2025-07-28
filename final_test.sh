#!/bin/bash

echo "🚀 Hello Prompt v2 - 最终修复测试"
echo "=================================="
echo ""

echo "🎯 完整修复内容："
echo "   ✅ 禁用了所有权限检查循环方法"
echo "   ✅ 禁用了应用激活状态监听"
echo "   ✅ 禁用了定期权限检查"
echo "   ✅ 使用简化的快捷键初始化"
echo "   ✅ 改进了'打开系统设置'的用户体验"
echo ""

echo "🔍 测试场景："
echo "   1. 应用启动 - 无循环，显示权限诊断"
echo "   2. 点击'完成安装' - 无循环"
echo "   3. 点击'打开辅助功能' - 无循环，显示友好引导"
echo "   4. 从系统设置返回 - 无循环（应用激活事件被禁用）"
echo "   5. 测试 Ctrl+U 快捷键"
echo ""

echo "📝 关键日志监控："
echo "   🔍 '开始直接权限诊断' - 启动诊断"
echo "   🎯 '直接设置快捷键回调' - 快捷键设置"
echo "   ✅ '权限检查已暂时禁用' - 循环避免"
echo "   ✅ '应用状态监听已暂时禁用' - 激活监听禁用"
echo "   🎙️ '快捷键触发：开始录音' - 快捷键成功"
echo ""

echo "⚠️  如果仍有问题："
echo "   • 使用 Cmd+Shift+D 手动诊断权限"
echo "   • 检查系统设置 > 隐私与安全性 > 辅助功能"
echo "   • 重启应用测试"
echo ""

# 构建应用
echo "📦 构建应用..."
swift build --quiet 2>/dev/null || {
    echo "❌ 构建失败，请检查代码"
    exit 1
}

echo "🚀 启动修复后的应用..."
echo "按 Ctrl+C 退出"
echo ""

# 启动应用并监控关键日志
./.build/debug/HelloPromptV2 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"直接权限诊断"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"直接设置快捷键回调"* ]]; then
        echo "🎯 $line"
    elif [[ "$line" == *"快捷键触发"* ]]; then
        echo "🎙️ $line"
    elif [[ "$line" == *"权限检查已暂时禁用"* ]]; then
        echo "✅ $line"
    elif [[ "$line" == *"应用状态监听已暂时禁用"* ]]; then
        echo "✅ $line"
    elif [[ "$line" == *"定期权限检查已暂时禁用"* ]]; then
        echo "✅ $line"
    elif [[ "$line" == *"强制刷新核心权限"* ]]; then
        echo "⚠️  循环警告: $line"
    elif [[ "$line" == *"checkAllPermissions"* ]]; then
        echo "⚠️  权限检查调用: $line"
    elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"错误"* ]]; then
        echo "❌ $line"
    elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"警告"* ]]; then
        echo "⚠️  $line"
    else
        echo "$line"
    fi
done 