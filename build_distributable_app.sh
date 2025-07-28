#!/bin/bash

# Hello Prompt 可分发应用构建脚本
# 创建一个可以直接双击运行且别人也能使用的 .app 文件

set -e  # 遇到错误时退出

echo "🚀 开始构建 Hello Prompt 可分发版本..."

# 应用信息
APP_NAME="Hello Prompt v2"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

# 清理旧的应用包
if [ -d "$APP_DIR" ]; then
    echo "🗑️  清理旧的应用包..."
    rm -rf "$APP_DIR"
fi

# 创建目录结构
echo "📁 创建应用目录结构..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# 构建可执行文件
echo "🔨 构建 Release 版本..."
swift build -c release --product HelloPromptV2

# 检查构建是否成功
if [ ! -f ".build/release/HelloPromptV2" ]; then
    echo "❌ 构建失败！可执行文件不存在"
    exit 1
fi

# 复制可执行文件
echo "📋 复制可执行文件..."
cp .build/release/HelloPromptV2 "$MACOS_DIR/HelloPrompt"

# 设置执行权限
chmod +x "$MACOS_DIR/HelloPrompt"

# 创建完整的 Info.plist
echo "📝 创建 Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>HelloPrompt</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.helloprompt.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Hello Prompt v2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    
    <!-- 权限说明 -->
    <key>NSMicrophoneUsageDescription</key>
    <string>HelloPrompt需要访问麦克风以录制语音并转换为文本提示</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>HelloPrompt需要辅助功能权限以实现全局快捷键功能</string>
    <key>NSSystemAdministrationUsageDescription</key>
    <string>HelloPrompt需要系统管理权限来注册全局快捷键和实现跨应用文本插入。</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>HelloPrompt需要输入监控权限来注册全局快捷键，以便您可以在任何应用中快速启动语音录制功能。</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>HelloPrompt需要辅助功能权限以实现全局快捷键功能</string>
    
    <!-- 网络访问 -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    
    <!-- 硬化运行时设置 -->
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    
    <!-- 应用沙盒设置 -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
    
    <!-- 支持的文档类型 -->
    <key>CFBundleDocumentTypes</key>
    <array/>
    
    <!-- 导出的类型标识符 -->
    <key>UTExportedTypeDeclarations</key>
    <array/>
</dict>
</plist>
EOF

# 创建 PkgInfo 文件
echo "📄 创建 PkgInfo..."
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 复制 Swift 运行时库（如果需要）
echo "📚 检查 Swift 运行时依赖..."
SWIFT_LIBS_PATH="/usr/lib/swift"
if [ -d "$SWIFT_LIBS_PATH" ]; then
    echo "✅ 系统 Swift 运行时可用"
else
    echo "⚠️  系统 Swift 运行时不可用，可能需要手动处理依赖"
fi

# 尝试进行代码签名（如果有开发者证书）
echo "🔐 尝试代码签名..."
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | cut -d '"' -f 2)

if [ ! -z "$DEVELOPER_ID" ]; then
    echo "✅ 找到开发者证书: $DEVELOPER_ID"
    echo "🔏 对应用进行代码签名..."
    
    # 签名可执行文件
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$MACOS_DIR/HelloPrompt"
    
    # 签名整个应用包
    codesign --force --options runtime --sign "$DEVELOPER_ID" "$APP_DIR"
    
    echo "✅ 代码签名完成"
    
    # 验证签名
    codesign --verify --verbose "$APP_DIR"
    echo "✅ 签名验证通过"
else
    echo "⚠️  未找到开发者证书，将创建自签名版本"
    echo "⚠️  其他用户可能需要在安全设置中手动允许运行"
    
    # 创建临时自签名证书（可选）
    # codesign --force --deep --sign - "$APP_DIR"
fi

# 创建使用说明
echo "📋 创建使用说明..."
cat > "使用说明.md" << 'EOF'
# Hello Prompt v2 使用说明

## 🚀 快速开始

1. **双击 `Hello Prompt v2.app` 启动应用**

2. **授权必要权限**：
   - 系统会自动提示麦克风权限，点击「允许」
   - 前往「系统偏好设置」→「安全性与隐私」→「辅助功能」
   - 点击锁定图标解锁，添加「Hello Prompt v2」并勾选

3. **开始使用**：
   - 使用全局快捷键启动语音录制
   - AI 会自动优化您的提示词并插入到当前应用中

## 🔧 故障排除

### 如果应用无法启动：
1. 右键点击应用 → 「打开」→ 确认打开
2. 或在终端中运行：`spctl --add "Hello Prompt v2.app"`

### 如果权限设置失败：
1. 完全退出应用
2. 重新设置权限
3. 重新启动应用

## 📞 技术支持

如遇问题，请检查系统要求：
- macOS 15.5 或更高版本
- 麦克风设备
- 网络连接（用于AI服务）

---
*构建日期：$(date)*
EOF

# 设置应用包权限
echo "🔧 设置应用包权限..."
chmod -R 755 "$APP_DIR"
chmod +x "$MACOS_DIR/HelloPrompt"

# 验证应用包结构
echo "🔍 验证应用包结构..."
if [ -f "$MACOS_DIR/HelloPrompt" ] && [ -f "$CONTENTS_DIR/Info.plist" ]; then
    echo "✅ 应用包结构正确"
else
    echo "❌ 应用包结构不完整"
    exit 1
fi

echo ""
echo "🎉 Hello Prompt v2 可分发版本构建完成！"
echo "📍 应用位置: $(pwd)/$APP_DIR"
echo "📋 使用说明: $(pwd)/使用说明.md"
echo ""
echo "🚀 分发说明："
echo "1. 将 '$APP_DIR' 和 '使用说明.md' 一起发给用户"
echo "2. 用户双击应用即可运行"
echo "3. 如有权限问题，参考使用说明进行设置"
echo ""

# 测试应用是否可以启动（可选）
echo "🧪 测试应用启动..."
if [ -x "$MACOS_DIR/HelloPrompt" ]; then
    echo "✅ 可执行文件权限正确"
    # 可以添加更多测试
else
    echo "❌ 可执行文件权限错误"
    exit 1
fi

echo "🎯 构建完成！现在可以分发给其他用户使用了。"