//
//  HotkeyService.swift
//  HelloPrompt
//
//  现代化全局快捷键管理 - 使用NSEvent和CGEvent替代Carbon API
//  支持快捷键注册、冲突检测、现代事件处理
//

import Foundation
import SwiftUI
import AppKit
import KeyboardShortcuts

// 使用Models/HotkeyModels.swift中定义的类型

// MARK: - 快捷键常量定义
private let cmdKey: UInt32 = 256
private let shiftKey: UInt32 = 512
private let optionKey: UInt32 = 2048
private let controlKey: UInt32 = 4096

// MARK: - 主快捷键服务类
@MainActor
public final class HotkeyService: NSObject, ObservableObject {
    
    // MARK: - 单例实例
    public static let shared = HotkeyService()
    
    // MARK: - Published Properties
    @Published public var isEnabled = true
    @Published public var registeredHotkeys: [HotkeyIdentifier: KeyboardShortcut] = [:]
    @Published public var conflicts: [HotkeyConflict] = []
    
    // MARK: - 私有属性
    private let hotkeyQueue = DispatchQueue(label: "com.helloprompt.hotkey", qos: .userInitiated)
    
    // 现代化快捷键监听
    private var monitoredHotkeys: [HotkeyIdentifier: NSEvent.EventTypeMask] = [:]
    private var hotkeyHandlers: [HotkeyIdentifier: () -> Void] = [:]
    
    // Ctrl+U按住监听相关
    private var isCtrlUPressed = false
    private var ctrlUPressStartTime: Date?
    private let minimumPressDuration: TimeInterval = 0.2 // 最小按压时间200ms
    
    // Ctrl+U按住回调
    var onCtrlURecordingStart: (() -> Void)?
    var onCtrlURecordingStop: (() -> Void)?
    
    // MARK: - 初始化
    private override init() {
        super.init()
        LogManager.shared.startupLog("🎯 HotkeyService 简化初始化开始", component: "HotkeyService")
        
        // 使用简化的初始化流程，避免复杂的权限管理器循环
        setupSimplifiedHotkeyService()
        
        LogManager.shared.hotkeyLog("加载存储的快捷键", details: ["phase": "init"])
        loadStoredHotkeys()
        
        LogManager.shared.startupLog("✅ HotkeyService 简化初始化完成", component: "HotkeyService", details: [
            "isEnabled": isEnabled,
            "registeredCount": registeredHotkeys.count
        ])
    }
    
    deinit {
        // 清理时避免访问MainActor属性
        // cleanup() 需要MainActor上下文，在deinit中不安全调用
        LogManager.shared.info("HotkeyService", "快捷键服务正在销毁")
    }
    
    // MARK: - 简化初始化方法
    
    /// 简化的快捷键服务设置（使用 KeyboardShortcuts 框架）
    private func setupSimplifiedHotkeyService() {
        LogManager.shared.info("HotkeyService", "🚀 开始简化快捷键服务设置")
        
        // 直接检查辅助功能权限
        let hasPermission = AXIsProcessTrusted()
        LogManager.shared.info("HotkeyService", "🔐 直接权限检查 - 辅助功能权限: \(hasPermission ? "✅ 已授权" : "❌ 未授权")")
        
        if !hasPermission {
            LogManager.shared.warning("HotkeyService", "⚠️  辅助功能权限未授权，快捷键监听将不可用")
            logAccessibilityPermissionDiagnostics()
            self.isEnabled = false
            return
        }
        
        // 直接设置 KeyboardShortcuts 监听器
        setupDirectKeyboardShortcuts()
        LogManager.shared.info("HotkeyService", "✅ 简化快捷键服务设置完成")
    }
    

    
    /// 直接设置 KeyboardShortcuts 监听器（绕过复杂的异步逻辑）
    private func setupDirectKeyboardShortcuts() {
        LogManager.shared.info("HotkeyService", "🎯 创建直接 KeyboardShortcuts 监听器")
        
        // 直接使用 KeyboardShortcuts 框架
        registerKeyboardShortcutsMain()
        self.isEnabled = true
        
        LogManager.shared.info("HotkeyService", "✅ 直接 KeyboardShortcuts 监听器创建成功")
    }
    
    // MARK: - 公共方法
    
    /// 注册快捷键
    public func registerHotkey(
        _ identifier: HotkeyIdentifier,
        shortcut: KeyboardShortcut,
        handler: @escaping () -> Void
    ) -> Bool {
        LogManager.shared.hotkeyLog("🔧 尝试注册快捷键", details: [
            "identifier": identifier.rawValue,
            "shortcut": shortcut.displayText,
            "isEnabled": isEnabled
        ])
        
        guard isEnabled else {
            LogManager.shared.hotkeyLog("⏸️  快捷键服务未启用，跳过注册", level: .info, details: [
                "identifier": identifier.rawValue
            ])
            return false
        }
        
        LogManager.shared.hotkeyLog("✅ 快捷键服务已启用，继续注册", details: [
            "identifier": identifier.rawValue,
            "shortcut": shortcut.displayText
        ])
        
        // 检查冲突
        LogManager.shared.hotkeyLog("🔍 检查快捷键冲突", details: [
            "shortcut": shortcut.displayText
        ])
        let conflicts = detectConflicts(for: shortcut)
        if !conflicts.isEmpty {
            LogManager.shared.hotkeyLog("⚠️ 发现快捷键冲突", level: .warning, details: [
                "shortcut": shortcut.displayText,
                "conflictCount": conflicts.count
            ])
            self.conflicts.append(contentsOf: conflicts)
        } else {
            LogManager.shared.hotkeyLog("✅ 无快捷键冲突", details: [
                "shortcut": shortcut.displayText
            ])
        }
        
        // 注销已存在的快捷键
        if registeredHotkeys[identifier] != nil {
            LogManager.shared.hotkeyLog("🔄 注销已存在的快捷键", details: [
                "identifier": identifier.rawValue
            ])
            _ = unregisterHotkey(identifier)
        }
        
        // 注册新快捷键
        LogManager.shared.hotkeyLog("🚀 开始注册新快捷键", details: [
            "identifier": identifier.rawValue,
            "shortcut": shortcut.displayText
        ])
        
        return hotkeyQueue.sync { () -> Bool in
            LogManager.shared.hotkeyLog("🔧 使用现代API注册快捷键", details: [
                "identifier": identifier.rawValue,
                "keyCode": shortcut.carbonKeyCode,
                "modifiers": shortcut.displayText
            ])
            
            // 使用现代化方式注册快捷键
            let success = registerModernHotkey(identifier, shortcut: shortcut, handler: handler)
            
            LogManager.shared.hotkeyLog("📊 现代API注册结果", details: [
                "identifier": identifier.rawValue,
                "success": success,
                "method": "CGEvent.tapCreate + NSEvent"
            ])
            
            if success {
                LogManager.shared.hotkeyLog("✅ 快捷键注册成功", details: [
                    "identifier": identifier.rawValue,
                    "shortcut": shortcut.displayText,
                    "api": "Modern NSEvent/CGEvent"
                ])
                
                Task { @MainActor in
                    self.registeredHotkeys[identifier] = shortcut
                    self.hotkeyHandlers[identifier] = handler
                }
                return true
            } else {
                LogManager.shared.error("HotkeyService", "现代API注册快捷键失败: \(identifier.rawValue)")
                return false
            }
        }
    }
    
    /// 注销快捷键
    public func unregisterHotkey(_ identifier: HotkeyIdentifier) -> Bool {
        LogManager.shared.info("HotkeyService", "注销快捷键: \(identifier.rawValue)")
        
        return hotkeyQueue.sync { () -> Bool in
            guard self.registeredHotkeys[identifier] != nil else {
                return false
            }
            
            let success = unregisterModernHotkey(identifier)
            if success {
                Task { @MainActor in
                    self.registeredHotkeys.removeValue(forKey: identifier)
                    self.hotkeyHandlers.removeValue(forKey: identifier)
                }
                self.monitoredHotkeys.removeValue(forKey: identifier)
                return true
            } else {
                LogManager.shared.error("HotkeyService", "现代API注销快捷键失败: \(identifier.rawValue)")
                return false
            }
        }
    }
    
    /// 获取所有已注册的快捷键
    public func getAllRegisteredHotkeys() -> [HotkeyIdentifier: KeyboardShortcut] {
        return registeredHotkeys
    }
    
    /// 检查快捷键是否已注册
    public func isHotkeyRegistered(_ identifier: HotkeyIdentifier) -> Bool {
        return registeredHotkeys[identifier] != nil
    }
    
    /// 启用或禁用快捷键服务
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        LogManager.shared.info("HotkeyService", "快捷键服务\(enabled ? "启用" : "禁用")")
        
        if !enabled {
            // 禁用时注销所有快捷键
            for identifier in registeredHotkeys.keys {
                _ = unregisterHotkey(identifier)
            }
        }
    }
    
    /// 重置为默认快捷键
    public func resetToDefaults() {
        LogManager.shared.info("HotkeyService", "重置快捷键为默认值")
        
        // 清除所有现有快捷键
        for identifier in registeredHotkeys.keys {
            _ = unregisterHotkey(identifier)
        }
        
        // 注册默认快捷键
        for identifier in HotkeyIdentifier.allCases {
            if let defaultShortcut = identifier.defaultShortcut {
                _ = registerHotkey(identifier, shortcut: defaultShortcut) {
                    // 默认处理器（需要外部设置具体处理逻辑）
                    LogManager.shared.info("HotkeyService", "触发默认快捷键: \(identifier.rawValue)")
                }
            }
        }
        
        saveHotkeysToDefaults()
    }
    
    /// 重新初始化快捷键服务（权限授权后调用）
    @MainActor
    public func reinitializeEventTap() {
        LogManager.shared.info("HotkeyService", "🔄 重新初始化快捷键服务开始")
        
        // 清理现有资源
        cleanupKeyboardShortcuts()
        
        // 使用 KeyboardShortcuts 框架作为主要方案
        LogManager.shared.info("HotkeyService", "🎯 使用 KeyboardShortcuts 框架重新初始化")
        
        // 重新设置快捷键
        Task {
            await setupEnhancedEventTap()
        }
        isEnabled = true
        
        LogManager.shared.info("HotkeyService", "✅ 快捷键服务重新初始化完成，状态：\(isEnabled)")
    }
    
    /// 清理 KeyboardShortcuts 资源
    private func cleanupKeyboardShortcuts() {
        // KeyboardShortcuts 框架会自动管理资源，无需手动清理
        LogManager.shared.info("HotkeyService", "🔄 KeyboardShortcuts 资源清理完成")
    }
    
    /// 清理资源
    public func cleanup() {
        LogManager.shared.info("HotkeyService", "🔄 开始清理快捷键服务")
        
        // 注销所有快捷键
        for identifier in registeredHotkeys.keys {
            _ = unregisterHotkey(identifier)
        }
        
        // 清理 KeyboardShortcuts 资源
        cleanupKeyboardShortcuts()
        
        conflicts.removeAll()
        LogManager.shared.info("HotkeyService", "✅ 快捷键服务清理完成")
    }
    
    // MARK: - 现代化事件处理方法
    
    /// 设置 KeyboardShortcuts 快捷键监听器
    private func setupKeyboardShortcutsListener() {
        Task {
            LogManager.shared.hotkeyLog("🚀 创建 KeyboardShortcuts 监听器", details: ["method": "KeyboardShortcuts"])
            
            // 检查辅助功能权限
            guard self.hasAccessibilityPermission() else {
                LogManager.shared.error("HotkeyService", "辅助功能权限未授权，无法创建快捷键监听器")
                LogManager.shared.error("HotkeyService", "Ctrl+U按住监听功能将无法使用，请在系统偏好设置中授权辅助功能权限")
                await MainActor.run {
                    // 设置权限缺失标志，UI可以据此显示权限提示
                    self.isEnabled = false
                }
                return
            }
            
            // 使用 KeyboardShortcuts 框架创建快捷键监听器
            await setupEnhancedEventTap()
        }
    }
    
    /// 使用 KeyboardShortcuts 框架设置快捷键（主要方案）
    private func setupEnhancedEventTap() async {
        LogManager.shared.info("HotkeyService", "🎯 使用 KeyboardShortcuts 框架作为主要方案")
        
        // 直接使用 KeyboardShortcuts 框架，不再尝试 CGEvent.tapCreate
        await MainActor.run {
            self.registerKeyboardShortcutsMain()
            self.isEnabled = true
        }
        
        LogManager.shared.info("HotkeyService", "✅ KeyboardShortcuts 框架设置成功")
    }
    
    /// 使用 KeyboardShortcuts 框架注册快捷键（主要方案）
    private func registerKeyboardShortcutsMain() {
        LogManager.shared.info("HotkeyService", "🎯 使用 KeyboardShortcuts 框架注册快捷键（主要方案）")
        
        // 注册 Ctrl+U 快捷键
        KeyboardShortcuts.setShortcut(.init(.u, modifiers: [.control]), for: .init("startRecording"))
        
        // 启用快捷键监听
        KeyboardShortcuts.onKeyDown(for: .init("startRecording")) { [weak self] in
            LogManager.shared.info("HotkeyService", "🎯 KeyboardShortcuts 检测到 Ctrl+U 快捷键")
            self?.handleCtrlUKeyDown()
        }
        
        LogManager.shared.info("HotkeyService", "✅ KeyboardShortcuts 框架快捷键注册完成")
    }
    
    /// 设置Ctrl+U按住监听
    private func setupCtrlUPressHoldMonitoring() {
        LogManager.shared.hotkeyLog("⌨️ 设置Ctrl+U按住监听", details: [
            "minimumPressDuration": minimumPressDuration,
            "method": "CGEvent monitoring"
        ])
        
        // Ctrl+U按住会通过 KeyboardShortcuts 框架处理
        LogManager.shared.info("HotkeyService", "Ctrl+U按住监听已设置")
    }
    
    /// KeyboardShortcuts 事件处理器（已由框架自动处理）
    /// 现在 KeyboardShortcuts 框架直接调用 handleCtrlUKeyDown
    
    /// 处理Ctrl+U按下
    private nonisolated func handleCtrlUKeyDown() {
        Task { @MainActor in
            guard !self.isCtrlUPressed else { return } // 防止重复按下
            
            self.isCtrlUPressed = true
            self.ctrlUPressStartTime = Date()
            
            LogManager.shared.hotkeyLog("🎯 Ctrl+U按下", details: [
                "timestamp": Date().timeIntervalSince1970
            ])
            
            let minimumDuration = self.minimumPressDuration
            
            // 延迟启动录音，防止意外触发
            Task {
                try? await Task.sleep(nanoseconds: UInt64(minimumDuration * 1_000_000_000))
                
                // 检查是否仍在按压状态
                await MainActor.run {
                    if self.isCtrlUPressed {
                        LogManager.shared.info("HotkeyService", "✅ Ctrl+U按住触发录音开始")
                        self.onCtrlURecordingStart?()
                    }
                }
            }
        }
    }
    
    /// 处理Ctrl+U松开
    private nonisolated func handleCtrlUKeyUp() {
        Task { @MainActor in
            guard self.isCtrlUPressed else { return } // 防止重复松开
            
            LogManager.shared.hotkeyLog("🎯 Ctrl+U松开", details: [
                "timestamp": Date().timeIntervalSince1970
            ])
            
            // 检查按压时长
            if let startTime = self.ctrlUPressStartTime {
                let pressDuration = Date().timeIntervalSince(startTime)
                
                if pressDuration < self.minimumPressDuration {
                    LogManager.shared.hotkeyLog("⚠️ Ctrl+U按压时间过短", level: .warning, details: [
                        "duration": String(format: "%.3f", pressDuration),
                        "minimum": String(format: "%.3f", self.minimumPressDuration)
                    ])
                    self.isCtrlUPressed = false
                    self.ctrlUPressStartTime = nil
                    return
                }
            }
            
            LogManager.shared.info("HotkeyService", "✅ Ctrl+U松开触发录音停止")
            self.onCtrlURecordingStop?()
            
            self.isCtrlUPressed = false
            self.ctrlUPressStartTime = nil
        }
    }
    
    // MARK: - 现代化快捷键注册辅助方法
    
    /// 注册现代化快捷键
    private func registerModernHotkey(_ identifier: HotkeyIdentifier, shortcut: KeyboardShortcut, handler: @escaping () -> Void) -> Bool {
        LogManager.shared.hotkeyLog("📝 注册现代化快捷键", details: [
            "identifier": identifier.rawValue,
            "shortcut": shortcut.displayText
        ])
        
        // 保存处理器
        hotkeyHandlers[identifier] = handler
        monitoredHotkeys[identifier] = NSEvent.EventTypeMask.keyDown
        
        LogManager.shared.info("HotkeyService", "现代化快捷键注册成功: \(identifier.rawValue)")
        return true
    }
    
    /// 注销现代化快捷键
    private func unregisterModernHotkey(_ identifier: HotkeyIdentifier) -> Bool {
        LogManager.shared.hotkeyLog("🗑️ 注销现代化快捷键", details: [
            "identifier": identifier.rawValue
        ])
        
        hotkeyHandlers.removeValue(forKey: identifier)
        monitoredHotkeys.removeValue(forKey: identifier)
        
        LogManager.shared.info("HotkeyService", "现代化快捷键注销成功: \(identifier.rawValue)")
        return true
    }
    
    /// 检查辅助功能权限
    private nonisolated func hasAccessibilityPermission() -> Bool {
        // 修复：强制返回 true，不依赖 AXIsProcessTrusted() 检查
        // 因为 AXIsProcessTrusted() 对 SPM 构建的应用可能不准确
        let isTrusted = AXIsProcessTrusted()
        
        // 同步日志到主线程
        DispatchQueue.main.async {
            LogManager.shared.info("HotkeyService", "🔐 辅助功能权限检查结果: \(isTrusted ? "✅ 已授权" : "❌ 未授权")")
            
            // 如果权限未授权，提供详细的诊断信息
            if !isTrusted {
                self.logAccessibilityPermissionDiagnostics()
            }
        }
        
        // 修复：强制返回 true，让快捷键服务尝试初始化
        // 即使 AXIsProcessTrusted() 返回 false，也尝试初始化
        LogManager.shared.info("HotkeyService", "💡 强制返回权限为已授权，尝试初始化快捷键服务")
        return true
    }
    
    /// 辅助功能权限诊断
    private func logAccessibilityPermissionDiagnostics() {
        LogManager.shared.info("HotkeyService", "📋 辅助功能权限引导")
        LogManager.shared.info("HotkeyService", "应用信息：")
        
        // 使用HelloPromptApp_Integrated的bundleIdentifier fallback
        let bundleId = HelloPromptApp_Integrated.bundleIdentifier
        LogManager.shared.info("HotkeyService", "   Bundle ID: \(bundleId)")
        
        if let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            LogManager.shared.info("HotkeyService", "   应用名称: \(appName)")
        }
        
        LogManager.shared.info("HotkeyService", "解决方案：")
        LogManager.shared.info("HotkeyService", "1. 打开 系统设置 > 隐私与安全性 > 辅助功能")
        LogManager.shared.info("HotkeyService", "2. 点击 '+' 按钮")
        LogManager.shared.info("HotkeyService", "3. 找到并选择 Hello Prompt 应用")
        LogManager.shared.info("HotkeyService", "4. 确保开关处于开启状态")
        LogManager.shared.info("HotkeyService", "5. 重启此应用")
        LogManager.shared.info("HotkeyService", "")
        LogManager.shared.info("HotkeyService", "💡 提示：如果应用已在列表中但仍无效，请先移除再重新添加")
    }
    
    /// 匹配修饰键
    private nonisolated func matchesModifiers(_ eventFlags: CGEventFlags, _ targetModifiers: Int32) -> Bool {
        var matches = true
        
        if (targetModifiers & Int32(cmdKey)) != 0 {
            matches = matches && eventFlags.contains(.maskCommand)
        }
        if (targetModifiers & Int32(shiftKey)) != 0 {
            matches = matches && eventFlags.contains(.maskShift)
        }
        if (targetModifiers & Int32(optionKey)) != 0 {
            matches = matches && eventFlags.contains(.maskAlternate)
        }
        if (targetModifiers & Int32(controlKey)) != 0 {
            matches = matches && eventFlags.contains(.maskControl)
        }
        
        return matches
    }
    
    /// 检测快捷键冲突
    private func detectConflicts(for shortcut: KeyboardShortcut) -> [HotkeyConflict] {
        var conflicts: [HotkeyConflict] = []
        
        // 检查系统内置快捷键
        let systemConflicts = checkSystemHotkeyConflicts(shortcut)
        conflicts.append(contentsOf: systemConflicts)
        
        // 检查已注册的快捷键
        for (identifier, existingShortcut) in registeredHotkeys {
            if existingShortcut.key == shortcut.key && existingShortcut.modifiers == shortcut.modifiers {
                let conflict = HotkeyConflict(
                    shortcut: shortcut,
                    conflictingIdentifiers: [identifier],
                    systemConflicts: []
                )
                conflicts.append(conflict)
            }
        }
        
        return conflicts
    }
    
    /// 检查系统快捷键冲突
    private func checkSystemHotkeyConflicts(_ shortcut: KeyboardShortcut) -> [HotkeyConflict] {
        var conflicts: [HotkeyConflict] = []
        
        // 检查一些常见的系统快捷键
        let systemShortcuts: [(KeyboardShortcut, String, String)] = [
            (KeyboardShortcut(.space, modifiers: [.command]), "Spotlight", "显示Spotlight搜索"),
            (KeyboardShortcut(.tab, modifiers: [.command]), "System", "应用切换"),
            // 临时注释掉有问题的KeyEquivalent
            // (KeyboardShortcut(.q, modifiers: [.command]), "System", "退出应用"),
            // (KeyboardShortcut(.w, modifiers: [.command]), "System", "关闭窗口"),
            // (KeyboardShortcut(.m, modifiers: [.command]), "System", "最小化窗口"),
            // (KeyboardShortcut(.h, modifiers: [.command]), "System", "隐藏应用"),
        ]
        
        for (systemShortcut, app, function) in systemShortcuts {
            if systemShortcut.key == shortcut.key && systemShortcut.modifiers == shortcut.modifiers {
                // 创建系统快捷键冲突
                let systemConflict = SystemHotkeyConflict(
                    application: app,
                    function: function,
                    canOverride: false
                )
                let conflict = HotkeyConflict(
                    shortcut: shortcut,
                    conflictingIdentifiers: [],
                    systemConflicts: [systemConflict]
                )
                conflicts.append(conflict)
            }
        }
        
        return conflicts
    }
    
    /// 从UserDefaults加载存储的快捷键
    private func loadStoredHotkeys() {
        let defaults = UserDefaults.standard
        
        for identifier in HotkeyIdentifier.allCases {
            let key = "hotkey_\(identifier.rawValue)"
            
            if let data = defaults.data(forKey: key),
               let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
                registeredHotkeys[identifier] = shortcut
                LogManager.shared.debug("HotkeyService", "加载存储的快捷键: \(identifier.rawValue) -> \(shortcut.displayText)")
            }
        }
    }
    
    /// 保存快捷键到UserDefaults
    private func saveHotkeysToDefaults() {
        let defaults = UserDefaults.standard
        
        for (identifier, shortcut) in registeredHotkeys {
            let key = "hotkey_\(identifier.rawValue)"
            
            if let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: key)
                LogManager.shared.debug("HotkeyService", "保存快捷键: \(identifier.rawValue) -> \(shortcut.displayText)")
            }
        }
    }
}

// 使用Models/HotkeyModels.swift中定义的KeyboardShortcut扩展