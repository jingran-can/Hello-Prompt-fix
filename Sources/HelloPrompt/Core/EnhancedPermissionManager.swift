//
//  EnhancedPermissionManager.swift
//  HelloPrompt
//
//  现代化权限管理系统 - 使用最新API和增强日志追踪
//  提供完整的权限生命周期管理和透明的状态追踪
//

import Foundation
import SwiftUI
import AVFoundation
import ApplicationServices
import Combine
import AppKit
import UserNotifications

// MARK: - 增强的权限管理器
@MainActor
public class EnhancedPermissionManager: ObservableObject {
    
    public static let shared = EnhancedPermissionManager()
    
    // MARK: - Published Properties
    @Published public var permissionStates: [PermissionType: PermissionState] = [:]
    @Published public var isCheckingPermissions = false
    @Published public var lastPermissionCheck: Date = Date.distantPast
    
    // MARK: - Permission Change Callbacks
    public var onPermissionChanged: ((PermissionChangeEvent) -> Void)?
    public var onAllPermissionsReady: (() -> Void)?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var permissionCheckTimer: Timer?
    private var currentPermissionRequest: PermissionType?
    private var lastPermissionRequestTime: Date?
    private var accessibilityPromptCount = 0  // 记录弹窗次数，防止无限循环
    
    // MARK: - 权限配置状态管理
    private var isInPermissionConfigurationFlow = false
    
    private init() {
        LogManager.shared.info("EnhancedPermissionManager", "🚀 初始化增强权限管理系统")
        setupInitialStates()
        setupApplicationStateObserver()
        setupPeriodicCheck()
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
        LogManager.shared.info("EnhancedPermissionManager", "♻️  权限管理系统已清理")
    }
    
    // MARK: - 初始化设置
    private func setupInitialStates() {
        for type in PermissionType.allCases {
            permissionStates[type] = PermissionState(
                type: type,
                status: .notDetermined,
                lastChecked: Date.distantPast,
                requestCount: 0
            )
        }
        LogManager.shared.debug("EnhancedPermissionManager", "📋 初始化了 \(PermissionType.allCases.count) 个权限状态")
    }
    
    // MARK: - 现代化权限请求方法
    
    /// 请求指定类型的权限（使用最新API）
    @discardableResult
    public func requestPermission(_ type: PermissionType, showPrompts: Bool = true) async -> PermissionStatus {
        LogManager.shared.info("EnhancedPermissionManager", "🎯 开始请求\(type.displayName)权限")
        
        let startTime = Date()
        currentPermissionRequest = type
        lastPermissionRequestTime = startTime  // 记录请求时间以防止循环
        
        // 增加请求计数
        if let currentState = permissionStates[type] {
            let newState = PermissionState(
                type: currentState.type,
                status: currentState.status,
                lastChecked: currentState.lastChecked,
                requestCount: currentState.requestCount + 1
            )
            permissionStates[type] = newState
        }
        
        let result: PermissionStatus
        
        switch type {
        case .microphone:
            result = await requestMicrophonePermissionModern(showPrompts: showPrompts)
        case .accessibility:
            result = await requestAccessibilityPermissionModern(showPrompts: showPrompts)
        case .notification:
            result = await requestNotificationPermissionModern(showPrompts: showPrompts)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        LogManager.shared.info("EnhancedPermissionManager", "✅ \(type.displayName)权限请求完成: \(result.statusText) (耗时: \(String(format: "%.2f", duration))s)")
        
        currentPermissionRequest = nil
        await logDetailedPermissionState(type, result)
        
        return result
    }
    
    /// 现代化麦克风权限请求
    private func requestMicrophonePermissionModern(showPrompts: Bool = true) async -> PermissionStatus {
        let currentStatus = await checkMicrophonePermissionAsync()
        
        LogManager.shared.debug("EnhancedPermissionManager", "🎤 当前麦克风权限状态: \(currentStatus.statusText)")
        
        if currentStatus == .notDetermined {
            LogManager.shared.info("EnhancedPermissionManager", "🎤 使用AVAudioSession现代API请求麦克风权限...")
            
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    let status: PermissionStatus = granted ? .granted : .denied
                    
                    LogManager.shared.info("EnhancedPermissionManager", "🎤 麦克风权限请求结果: \(granted ? "✅ 已授权" : "❌ 被拒绝")")
                    
                    Task { @MainActor in
                        await self?.updatePermissionState(.microphone, newStatus: status)
                    }
                    
                    continuation.resume(returning: status)
                }
            }
        }
        
        // 确保缓存状态与实时状态同步（修复状态不同步问题）
        if currentStatus == .granted {
            await updatePermissionState(.microphone, newStatus: .granted)
            LogManager.shared.debug("EnhancedPermissionManager", "🔄 已同步麦克风权限缓存状态")
        }
        
        return currentStatus
    }
    
    /// 现代化辅助功能权限请求
    private func requestAccessibilityPermissionModern(showPrompts: Bool = true) async -> PermissionStatus {
        let currentStatus = checkAccessibilityPermissionRealTime()
        
        LogManager.shared.debug("EnhancedPermissionManager", "🔐 当前辅助功能权限状态: \(currentStatus ? "已授权" : "未授权")")
        
        if !currentStatus {
            LogManager.shared.info("EnhancedPermissionManager", "🔐 检查辅助功能权限...")
            
            // 修复双重弹窗：使用系统弹窗，不显示应用弹窗
            let isTrusted: Bool
            if showPrompts {
                // 使用系统弹窗
                let options: [String: Any] = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ]
                isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
                LogManager.shared.info("EnhancedPermissionManager", "🔐 已触发系统权限弹窗")
            } else {
                // 使用静默检查
                isTrusted = AXIsProcessTrusted()
                LogManager.shared.info("EnhancedPermissionManager", "🔐 使用静默权限检查")
            }
            
            let newStatus: PermissionStatus = isTrusted ? .granted : .denied
            LogManager.shared.info("EnhancedPermissionManager", "🔐 辅助功能权限检查结果: \(isTrusted ? "✅ 已授权" : "⚠️  需要用户手动授权")")
            
            await updatePermissionState(.accessibility, newStatus: newStatus)
            
            // 修复双重弹窗：禁用应用弹窗，只使用系统弹窗
            if newStatus != .granted && showPrompts {
                LogManager.shared.info("EnhancedPermissionManager", "⏸️  系统已显示权限弹窗，跳过应用弹窗避免重复")
            } else if newStatus != .granted && !showPrompts {
                LogManager.shared.info("EnhancedPermissionManager", "⏸️  静默模式，跳过权限指导弹窗")
            }
            
            return newStatus
        }
        
        await updatePermissionState(.accessibility, newStatus: .granted)
        accessibilityPromptCount = 0  // 重置计数器，因为权限已授权
        LogManager.shared.info("EnhancedPermissionManager", "✅ 辅助功能权限已授权，重置提示计数器")
        return .granted
    }
    
    /// 现代化通知权限请求
    private func requestNotificationPermissionModern(showPrompts: Bool = true) async -> PermissionStatus {
        guard let center = getNotificationCenterSafely() else {
            LogManager.shared.warning("EnhancedPermissionManager", "⚠️  无法获取通知中心，跳过通知权限请求")
            return .unknown
        }
        
        LogManager.shared.info("EnhancedPermissionManager", "🔔 使用UNUserNotificationCenter现代API请求通知权限...")
        
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
                let status: PermissionStatus
                
                if let error = error {
                    LogManager.shared.error("EnhancedPermissionManager", "🔔 通知权限请求失败: \(error.localizedDescription)")
                    status = .denied
                } else {
                    status = granted ? .granted : .denied
                    LogManager.shared.info("EnhancedPermissionManager", "🔔 通知权限请求结果: \(granted ? "✅ 已授权" : "❌ 被拒绝")")
                }
                
                Task { @MainActor in
                    await self?.updatePermissionState(.notification, newStatus: status)
                }
                
                continuation.resume(returning: status)
            }
        }
    }
    
    // MARK: - 权限状态检查方法
    
    /// 实时检查辅助功能权限（绕过缓存）
    public func checkAccessibilityPermissionRealTime() -> Bool {
        let result = AXIsProcessTrusted()
        LogManager.shared.debug("EnhancedPermissionManager", "🔍 实时辅助功能权限检查: \(result ? "✅" : "❌")")
        return result
    }
    
    /// 异步检查麦克风权限
    public func checkMicrophonePermissionAsync() async -> PermissionStatus {
        let authStatus = AVAudioSession.sharedInstance().recordPermission
        let status: PermissionStatus
        
        switch authStatus {
        case .granted:
            status = .granted
        case .denied:
            status = .denied
        case .undetermined:
            status = .notDetermined
        @unknown default:
            status = .unknown
        }
        
        LogManager.shared.debug("EnhancedPermissionManager", "🎤 异步麦克风权限检查: \(status.statusText)")
        return status
    }
    
    /// 检查所有权限状态（增强版）
    public func checkAllPermissionsEnhanced(reason: String = "手动检查", showPrompts: Bool = true) async {
        // 全局权限检查禁用检查
        if PermissionManager.isPermissionCheckingGloballyDisabled {
            LogManager.shared.info("EnhancedPermissionManager", "🚫 权限检查已全局禁用，跳过增强检查 - 原因: \(reason)")
            return
        }
        
        // 如果正在权限配置过程中，跳过自动检查
        if isInPermissionConfigurationFlow {
            LogManager.shared.info("EnhancedPermissionManager", "🔧 权限配置流程中，跳过增强检查 - 原因: \(reason)")
            return
        }
        
        guard !isCheckingPermissions else { 
            LogManager.shared.warning("EnhancedPermissionManager", "🔄 权限检查正在进行中，跳过重复检查")
            return 
        }
        
        isCheckingPermissions = true
        LogManager.shared.info("EnhancedPermissionManager", "🔄 开始增强权限检查，原因：\(reason)")
        
        defer {
            isCheckingPermissions = false
        }
        
        // 并行检查权限以提高性能 - 传递showPrompts参数
        async let microphoneCheck = (PermissionType.microphone, await requestPermission(.microphone, showPrompts: showPrompts))
        async let accessibilityCheck = (PermissionType.accessibility, await requestPermission(.accessibility, showPrompts: showPrompts))
        async let notificationCheck = (PermissionType.notification, await requestPermission(.notification, showPrompts: showPrompts))
        
        let results = await [microphoneCheck, accessibilityCheck, notificationCheck]
        
        LogManager.shared.info("EnhancedPermissionManager", "🔄 增强权限检查完成")
        LogManager.shared.debug("EnhancedPermissionManager", "权限状态汇总：\(results.map { "\($0.0.displayName): \($0.1.statusText)" }.joined(separator: ", "))")
        
        // UI状态更新已移除，可在需要时重新实现
    }
    
    // MARK: - 私有辅助方法
    
    private func getCurrentPermissionStatus(_ type: PermissionType) async -> PermissionStatus {
        switch type {
        case .microphone:
            return await checkMicrophonePermissionAsync()
        case .accessibility:
            return checkAccessibilityPermissionRealTime() ? .granted : .notDetermined
        case .notification:
            return await getNotificationPermissionStatusAsync()
        }
    }
    
    private func updatePermissionState(_ type: PermissionType, newStatus: PermissionStatus) async {
        let oldStatus = permissionStates[type]?.status ?? .notDetermined
        
        permissionStates[type] = PermissionState(
            type: type,
            status: newStatus,
            lastChecked: Date(),
            requestCount: permissionStates[type]?.requestCount ?? 0
        )
        
        // 触发权限变化事件
        if oldStatus != newStatus, let callback = onPermissionChanged {
            let event = PermissionChangeEvent(
                type: type,
                oldStatus: oldStatus,
                newStatus: newStatus,
                timestamp: Date()
            )
            
            LogManager.shared.info("EnhancedPermissionManager", "🔄 权限状态变化: \(type.displayName) \(oldStatus.statusText) → \(newStatus.statusText)")
            callback(event)
        }
    }
    
    private func getNotificationPermissionStatusAsync() async -> PermissionStatus {
        guard let center = getNotificationCenterSafely() else {
            return .unknown
        }
        
        return await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: PermissionStatus
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    status = .granted
                case .denied:
                    status = .denied
                case .notDetermined:
                    status = .notDetermined
                @unknown default:
                    status = .unknown
                }
                continuation.resume(returning: status)
            }
        }
    }
    
    private func getNotificationCenterSafely() -> UNUserNotificationCenter? {
        // 使用HelloPromptApp_Integrated的bundleIdentifier fallback
        let bundleId = HelloPromptApp_Integrated.bundleIdentifier
        LogManager.shared.debug("EnhancedPermissionManager", "尝试获取通知中心，Bundle ID: \(bundleId)")
        
        // 检查是否是完整的 .app bundle
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            LogManager.shared.warning("EnhancedPermissionManager", "⚠️  非标准app bundle结构，跳过UNUserNotificationCenter")
            LogManager.shared.info("EnhancedPermissionManager", "当前Bundle URL: \(bundleURL.path)")
            return nil
        }
        
        // 只有在完整 app bundle 中才调用 UNUserNotificationCenter
        return UNUserNotificationCenter.current()
    }
    
    private func showModernAccessibilityGuide() async {
        LogManager.shared.info("EnhancedPermissionManager", "📖 显示现代化辅助功能权限指导")
        
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        Hello Prompt 需要辅助功能权限来监听全局快捷键（Ctrl+U）。
        
        请按照以下步骤授权：
        1. 打开"系统偏好设置"
        2. 选择"安全性与隐私"
        3. 点击"隐私"标签
        4. 选择"辅助功能"
        5. 点击锁图标并输入密码
        6. 勾选"Hello Prompt v2"
        """
        alert.addButton(withTitle: "打开系统偏好设置")
        alert.addButton(withTitle: "稍后设置")
        alert.alertStyle = .informational
        
        let response = await alert.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow())
        
        if response == .alertFirstButtonReturn {
            // 打开系统偏好设置的辅助功能页面
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            LogManager.shared.info("EnhancedPermissionManager", "🔧 已打开系统偏好设置")
        }
    }
    
    private func logDetailedPermissionState(_ type: PermissionType, _ status: PermissionStatus) async {
        let state = permissionStates[type]
        LogManager.shared.info("EnhancedPermissionManager", """
        📋 权限详细状态报告:
        类型: \(type.displayName)
        状态: \(status.statusText)
        请求次数: \(state?.requestCount ?? 0)
        上次检查: \(state?.lastChecked.description ?? "从未")
        是否必需: \(type.isRequired ? "是" : "否")
        优先级: \(type.priority)
        """)
    }
    
    // MARK: - 应用状态监听  
    private func setupApplicationStateObserver() {
        // 监听应用激活状态（智能跳过权限配置过程中的检查）
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    // 🔧 修复循环：只在特定条件下才检查权限
                    guard let self = self else { return }
                    
                    // 防止权限配置过程中的循环检查
                    if self.isInPermissionConfigurationFlow {
                        LogManager.shared.info("EnhancedPermissionManager", "🔧 权限配置流程中，跳过应用激活检查")
                        return
                    }
                    
                    // 检查是否刚刚请求过权限（防止循环）
                    let timeSinceLastCheck = Date().timeIntervalSince(self.lastPermissionRequestTime ?? Date.distantPast)
                    if timeSinceLastCheck < 30.0 { // 30秒内不重复检查
                        LogManager.shared.info("EnhancedPermissionManager", "🕒 距离上次权限检查不足30秒，跳过应用激活检查")
                        return
                    }
                    
                    // 修复双重弹窗：只在真正需要时检查（麦克风权限丢失或首次启动）
                    let currentMicStatus = await self.checkMicrophonePermissionAsync()
                    if currentMicStatus == .granted {
                        LogManager.shared.debug("EnhancedPermissionManager", "✅ 麦克风权限正常，跳过应用激活检查")
                        return
                    }
                    
                    // 检查辅助功能权限，如果已授权则跳过
                    let accessibilityGranted = AXIsProcessTrusted()
                    if accessibilityGranted {
                        LogManager.shared.debug("EnhancedPermissionManager", "✅ 辅助功能权限正常，跳过应用激活检查")
                        return
                    }
                    
                    LogManager.shared.info("EnhancedPermissionManager", "🔍 权限异常，执行权限检查")
                    await self.checkAllPermissionsEnhanced(reason: "权限状态变化", showPrompts: false)
                }
            }
            .store(in: &cancellables)
        
        LogManager.shared.debug("EnhancedPermissionManager", "👁️  增强应用状态监听器已设置（智能模式）")
    }
    
    // MARK: - 定期权限检查
    private func setupPeriodicCheck() {
        // 修复双重弹窗：禁用定期权限检查定时器
        // permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
        //     Task { @MainActor in
        //         await self?.checkAllPermissionsEnhanced(reason: "定期检查")
        //     }
        // }
        LogManager.shared.info("EnhancedPermissionManager", "⏸️ 增强定期权限检查器已禁用，避免双重弹窗")
    }
    
    /// 开始权限配置流程
    public func startPermissionConfigurationFlow() {
        isInPermissionConfigurationFlow = true
        LogManager.shared.info("EnhancedPermissionManager", "🔧 开始权限配置流程，暂停自动检查")
    }
    
    /// 结束权限配置流程
    public func endPermissionConfigurationFlow() {
        isInPermissionConfigurationFlow = false
        LogManager.shared.info("EnhancedPermissionManager", "✅ 权限配置流程结束，恢复正常检查")
    }
}

// MARK: - 扩展功能
extension EnhancedPermissionManager {
    
    /// 强制刷新所有权限状态
    public func forceRefreshAllPermissions() async {
        // 全局权限检查禁用检查
        if PermissionManager.isPermissionCheckingGloballyDisabled {
            LogManager.shared.info("EnhancedPermissionManager", "🚫 权限检查已全局禁用，跳过强制刷新")
            return
        }
        
        LogManager.shared.info("EnhancedPermissionManager", "🔄 强制刷新所有权限状态")
        await checkAllPermissionsEnhanced(reason: "强制刷新")
    }
    
    /// 获取权限摘要报告
    public func getPermissionSummary() -> String {
        let summary = permissionStates.map { type, state in
            "\(type.displayName): \(state.status.statusText)"
        }.joined(separator: ", ")
        
        LogManager.shared.debug("EnhancedPermissionManager", "📊 权限摘要: \(summary)")
        return summary
    }
    
    /// 检查是否所有必需权限都已获得
    public var allRequiredPermissionsGranted: Bool {
        let result = PermissionType.allCases
            .filter { $0.isRequired }
            .allSatisfy { permissionStates[$0]?.status.isGranted ?? false }
        
        LogManager.shared.debug("EnhancedPermissionManager", "✅ 所有必需权限已获得: \(result ? "是" : "否")")
        return result
    }
}