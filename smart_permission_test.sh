#!/bin/bash

echo "🧠 Hello Prompt v2 - 智能权限管理测试"
echo "========================================"
echo ""

echo "💡 智能权限管理特性："
echo "   ✅ 保留了用户友好的权限弹窗"
echo "   ✅ 智能避免权限配置过程中的循环检查"
echo "   ✅ 应用激活时自动跳过配置流程中的检查"
echo "   ✅ 减少了定期检查频率（60秒 → 降低干扰）"
echo "   ✅ 明确的权限配置流程状态管理"
echo ""

echo "🎯 测试流程："
echo "   1. 应用启动 → 正常权限诊断"
echo "   2. 点击'完成安装' → 显示权限弹窗（如需要）"
echo "   3. 点击'打开系统设置' → 自动标记配置流程开始"
echo "   4. 从系统设置返回 → 智能跳过循环检查"
echo "   5. 点击指导弹窗'我知道了' → 配置流程结束"
echo "   6. 测试 Ctrl+U 快捷键"
echo ""

echo "📝 关键日志监控："
echo "   🔧 '开始权限配置流程' - 配置开始"
echo "   🔧 '权限配置流程中，跳过自动检查' - 智能跳过"
echo "   ✅ '权限配置流程结束' - 配置完成"
echo "   🎙️ '快捷键触发：开始录音' - 快捷键成功"
echo ""

echo "🎉 用户体验改进："
echo "   • 保留了必要的权限引导弹窗"
echo "   • 消除了权限配置过程中的循环干扰"
echo "   • 清晰的配置流程状态提示"
echo "   • 建议重启确保权限完全生效"
echo ""

# 构建应用
echo "📦 构建应用..."
swift build --quiet 2>/dev/null || {
    echo "❌ 构建失败，请检查代码"
    exit 1
}

echo "🚀 启动智能权限管理版本..."
echo "按 Ctrl+C 退出"
echo ""

# 启动应用并监控智能权限管理日志
./.build/debug/HelloPromptV2 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"开始权限配置流程"* ]]; then
        echo "🔧 $line"
    elif [[ "$line" == *"权限配置流程中"* ]]; then
        echo "🔧 $line"
    elif [[ "$line" == *"权限配置流程结束"* ]]; then
        echo "✅ $line"
    elif [[ "$line" == *"应用状态监听器已设置（智能模式）"* ]]; then
        echo "🧠 $line"
    elif [[ "$line" == *"直接权限诊断"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"快捷键触发"* ]]; then
        echo "🎙️ $line"
    elif [[ "$line" == *"强制刷新核心权限"* ]]; then
        echo "⚠️  意外循环: $line"
    elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"错误"* ]]; then
        echo "❌ $line"
    elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"警告"* ]]; then
        echo "⚠️  $line"
    else
        echo "$line"
    fi
done 