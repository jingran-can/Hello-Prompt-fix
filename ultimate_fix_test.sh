#!/bin/bash

echo "🛡️  Hello Prompt v2 - 终极防循环修复测试"
echo "==========================================="
echo ""

echo "💥 终极修复方案："
echo "   🚫 应用启动时全局禁用所有权限检查"
echo "   🚫 在所有权限检查方法开头添加全局禁用检查"
echo "   🚫 彻底阻断所有可能的循环触发点"
echo "   ✅ 保留用户友好的权限弹窗（在需要时）"
echo "   ✅ 保留快捷键功能"
echo ""

echo "🎯 测试场景："
echo "   1. 应用启动 → 无任何权限检查循环"
echo "   2. 点击'完成安装' → 显示权限弹窗但无循环"
echo "   3. 点击'打开系统设置' → 绝对无循环"
echo "   4. 从系统设置返回 → 绝对无循环"
echo "   5. 任何操作都不会触发循环"
echo ""

echo "📝 关键日志监控："
echo "   🚫 '全局禁用所有权限检查' - 防护启动"
echo "   🚫 '权限检查已全局禁用，跳过检查' - 循环阻断"
echo "   🔍 '开始直接权限诊断' - 权限状态查看"
echo "   🎙️ '快捷键触发：开始录音' - 快捷键功能"
echo ""

echo "⚠️  警告信号："
echo "   如果看到'强制刷新核心权限'或'checkAllPermissions'字样"
echo "   说明还有漏网之鱼需要修复"
echo ""

echo "🏆 成功标准："
echo "   • 整个流程中看不到任何循环日志"
echo "   • 可以正常操作所有界面功能"
echo "   • Ctrl+U快捷键正常工作（如有权限）"
echo ""

# 构建应用
echo "📦 构建终极修复版本..."
swift build --quiet 2>/dev/null || {
    echo "❌ 构建失败，请检查代码"
    exit 1
}

echo "🚀 启动终极防循环版本..."
echo "如果此版本仍有循环，那就真的需要从头重构了！"
echo "按 Ctrl+C 退出"
echo ""

# 启动应用并监控所有可能的循环信号
./.build/debug/HelloPromptV2 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *"全局禁用所有权限检查"* ]]; then
        echo "🚫 $line"
    elif [[ "$line" == *"权限检查已全局禁用"* ]]; then
        echo "🚫 $line"
    elif [[ "$line" == *"直接权限诊断"* ]]; then
        echo "🔍 $line"
    elif [[ "$line" == *"快捷键触发"* ]]; then
        echo "🎙️ $line"
    elif [[ "$line" == *"强制刷新核心权限"* ]]; then
        echo "🔥 循环警告: $line"
    elif [[ "$line" == *"checkAllPermissions"* ]]; then
        echo "🔥 循环警告: $line"
    elif [[ "$line" == *"forceRefresh"* ]]; then
        echo "🔥 循环警告: $line"
    elif [[ "$line" == *"immediatePermissionCheck"* ]]; then
        echo "🔥 循环警告: $line"
    elif [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"错误"* ]]; then
        echo "❌ $line"
    elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"警告"* ]]; then
        echo "⚠️  $line"
    else
        echo "$line"
    fi
done 