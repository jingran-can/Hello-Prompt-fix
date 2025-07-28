//
//  HelloPromptApp_Integrated.swift
//  HelloPrompt
//
//  完全集成增强系统的应用入口
//  使用 EnhancedWorkflowManager, EnhancedPermissionManager, EnhancedAPIValidator, EnhancedLogManager
//

import SwiftUI
import AppKit
import KeyboardShortcuts
import Combine
import AVFAudio
import AVFoundation
import ApplicationServices

// MARK: - 主应用程序结构（完全集成版）
@main
struct HelloPromptApp_Integrated: App {
    
    // MARK: - 增强系统管理器
    @StateObject private var enhancedWorkflowManager: EnhancedWorkflowManager
    @StateObject private var enhancedPermissionManager: EnhancedPermissionManager = .shared
    @StateObject private var enhancedAPIValidator: EnhancedAPIValidator = .init()
    @StateObject private var enhancedLogger: EnhancedLogManager = .shared
    
    // MARK: - 传统系统（向后兼容）
    @StateObject private var appManager = AppManager.shared
    @StateObject private var configManager = AppConfigManager.shared
    @StateObject private var errorHandler = ErrorHandler.shared
    @StateObject private var hotkeyService = HotkeyService.shared
    @StateObject private var launchAgentManager = LaunchAgentManager.shared
    
    // MARK: - UI状态
    @State private var isShowingSettings = false
    @State private var isShowingAbout = false
    @State private var isShowingOnboarding = false
    @State private var orbState: OrbState = .idle
    @State private var showingResult = false
    @State private var currentResult: OverlayResult?
    @State private var audioLevel: Float = 0.0
    @State private var orbVisible = false
    
    // MARK: - 工作流状态
    @State private var currentWorkflowState: WorkflowState = .idle
    @State private var workflowProgress: Double = 0.0
    @State private var workflowDescription: String = ""
    
    // MARK: - 应用委托
    @NSApplicationDelegateAdaptor(AppDelegate_Integrated.self) var appDelegate
    
    init() {
        // 创建增强工作流管理器
        let openAIService = OpenAIService()
        let configManager = AppConfigManager.shared
        let permissionManager = EnhancedPermissionManager.shared
        
        let workflowManager = EnhancedWorkflowManager(
            audioService: AudioService(),
            openAIService: openAIService,
            configManager: configManager,
            permissionManager: permissionManager
        )
        
        _enhancedWorkflowManager = StateObject(wrappedValue: workflowManager)
    }
    
    // MARK: - 主视图
    var body: some Scene {
        // 主设置窗口
        WindowGroup("Hello Prompt v2") {
            SettingsView()
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    setupApplication()
                }
        }
        .commands {
            appMenuCommands
        }
        .defaultSize(width: 800, height: 600)
        
        // 录音覆盖窗口
        WindowGroup("录音", id: "recording-overlay") {
            RecordingOverlayView(
                orbState: $orbState,
                audioLevel: $audioLevel,
                isVisible: $orbVisible,
                onCancel: {
                    cancelCurrentWorkflow()
                }
            )
            .frame(width: 200, height: 200)
            .background(Color.clear)
            .onAppear {
                configureRecordingWindow()
            }
        }
        .windowStyle(.plain)
        
        // 权限申请窗口
        WindowGroup("权限申请", id: "permission-request") {
            if PermissionManager.shared.shouldShowPermissionWindow {
                PermissionRequestView(
                    onPermissionsGranted: {
                        enhancedLogger.info("HelloPromptApp_Integrated", "权限申请界面报告权限已授权")
                    },
                    onSkipped: {
                        enhancedLogger.info("HelloPromptApp_Integrated", "用户选择跳过权限申请")
                    }
                )
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentSize)
        
        // 新手引导窗口
        WindowGroup("新手引导", id: "onboarding-wizard") {
            if isShowingOnboarding {
                OnboardingWizardView(
                    onCompleted: {
                        isShowingOnboarding = false
                        enhancedLogger.userActionLog("新手引导已完成")
                        
                        // 标记已完成引导
                        UserDefaults.standard.set(true, forKey: "HelloPrompt_OnboardingCompleted")
                    },
                    onSkipped: {
                        isShowingOnboarding = false
                        enhancedLogger.userActionLog("用户跳过新手引导")
                    }
                )
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentSize)
        
        // 结果显示窗口
        WindowGroup("结果显示", id: "result-overlay") {
            if showingResult, currentResult != nil {
                ResultOverlay(
                    result: $currentResult,
                    isShowing: $showingResult,
                    onAction: { action, text in
                        handleResultAction(action, text: text)
                    },
                    onClose: {
                        showingResult = false
                        currentResult = nil
                    },
                    enableAnimations: true,
                    allowEditing: true,
                    showKeyboardHints: true
                )
                .onAppear {
                    configureResultWindow()
                }
            } else {
                EmptyView()
            }
        }
        .windowStyle(.plain)
    }
    
    // MARK: - 应用菜单命令
    @CommandsBuilder
    private var appMenuCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button("关于 Hello Prompt v2") {
                showAbout()
            }
            .keyboardShortcut("a", modifiers: .command)
        }
        
        CommandGroup(after: .appSettings) {
            Button("偏好设置...") {
                showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button("新手引导...") {
                showOnboarding()
            }
            .keyboardShortcut("?", modifiers: .command)
        }
        
        CommandGroup(after: .help) {
            Button("开始录音") {
                startEnhancedWorkflow()
            }
            .keyboardShortcut("u", modifiers: [.control])
            
            Button("停止录音") {
                cancelCurrentWorkflow()
            }
            .keyboardShortcut(.escape, modifiers: [.option])
            
            Divider()
            
            Button("诊断权限问题") {
                diagnosePermissions()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            
            Button("手动检查辅助功能权限") {
                manualAccessibilityCheck()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
    
    // MARK: - 权限诊断工具
    @MainActor
    private func manualAccessibilityCheck() {
        enhancedLogger.info("HelloPromptApp_Integrated", "🔍 执行手动辅助功能权限检查")
        
        let bundleId = HelloPromptApp_Integrated.bundleIdentifier
        enhancedLogger.info("HelloPromptApp_Integrated", "📋 当前Bundle ID: \(bundleId)")
        
        // 获取当前可执行文件路径
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        enhancedLogger.info("HelloPromptApp_Integrated", "📁 当前可执行文件路径: \(executablePath)")
        
        // 检查权限状态
        let hasPermissionDirect = AXIsProcessTrusted()
        enhancedLogger.info("HelloPromptApp_Integrated", "🔐 AXIsProcessTrusted() 结果: \(hasPermissionDirect)")
        
        if hasPermissionDirect {
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 辅助功能权限已正确配置")
            enhancedLogger.info("HelloPromptApp_Integrated", "🎯 Ctrl+U 快捷键应该可以正常工作了")
        } else {
            enhancedLogger.info("HelloPromptApp_Integrated", "⚠️ AXIsProcessTrusted() 显示权限未授权")
            enhancedLogger.info("HelloPromptApp_Integrated", "🔍 权限配置诊断：")
            enhancedLogger.info("HelloPromptApp_Integrated", "   当前应用信息：")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - Bundle ID: \(bundleId)")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - 可执行文件: \(executablePath)")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - 应用名称: HelloPromptV2")
            enhancedLogger.info("HelloPromptApp_Integrated", "")
            enhancedLogger.info("HelloPromptApp_Integrated", "💡 重要说明：")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - AXIsProcessTrusted() 对 SPM 构建的应用可能不准确")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - 即使显示未授权，实际权限可能已经配置正确")
            enhancedLogger.info("HelloPromptApp_Integrated", "   - 建议尝试使用 Ctrl+U 快捷键，看是否能正常工作")
            enhancedLogger.info("HelloPromptApp_Integrated", "")
            enhancedLogger.info("HelloPromptApp_Integrated", "🔄 尝试重新初始化快捷键服务...")
            
            // 尝试重新初始化快捷键服务
            hotkeyService.reinitializeEventTap()
            setupEnhancedGlobalHotkeys()
            
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 快捷键服务重新初始化完成")
            enhancedLogger.info("HelloPromptApp_Integrated", "🎯 现在尝试使用 Ctrl+U 快捷键，应该可以在后台工作了！")
            enhancedLogger.info("HelloPromptApp_Integrated", "")
            enhancedLogger.info("HelloPromptApp_Integrated", "📋 如果快捷键仍然不工作，请按照以下步骤配置：")
            enhancedLogger.info("HelloPromptApp_Integrated", "1. 打开 系统设置 > 隐私与安全性 > 辅助功能")
            enhancedLogger.info("HelloPromptApp_Integrated", "2. 点击 '+' 按钮")
            enhancedLogger.info("HelloPromptApp_Integrated", "3. 在文件选择器中，导航到：")
            enhancedLogger.info("HelloPromptApp_Integrated", "   \(executablePath)")
            enhancedLogger.info("HelloPromptApp_Integrated", "4. 选择 HelloPromptV2 可执行文件")
            enhancedLogger.info("HelloPromptApp_Integrated", "5. 确保开关处于开启状态")
            enhancedLogger.info("HelloPromptApp_Integrated", "6. 重启此应用并测试 Ctrl+U")
        }
    }
    
    @MainActor
    private func diagnosePermissions() {
        enhancedLogger.info("HelloPromptApp_Integrated", "🔍 开始直接权限诊断")
        
        // 检查麦克风权限
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        enhancedLogger.info("HelloPromptApp_Integrated", "🎤 麦克风权限: \(micStatusText(micStatus))")
        
        // 直接检查辅助功能权限
        let accessibilityGranted = AXIsProcessTrusted()
        enhancedLogger.info("HelloPromptApp_Integrated", "🔧 辅助功能权限: \(accessibilityGranted ? "✅ 已授权" : "❌ 未授权")")
        
        // 检查快捷键服务状态
        enhancedLogger.info("HelloPromptApp_Integrated", "⌨️ 快捷键服务状态: \(hotkeyService.isEnabled ? "✅ 已启用" : "❌ 已禁用")")
        
        // 直接设置快捷键回调（无论权限如何）
        setupDirectHotkeyCallbacks()
        
        // 提供解决方案
        if !accessibilityGranted {
            enhancedLogger.info("HelloPromptApp_Integrated", "📋 需要配置辅助功能权限以启用全局快捷键")
            enhancedLogger.info("HelloPromptApp_Integrated", "解决步骤：")
            enhancedLogger.info("HelloPromptApp_Integrated", "1. 打开 系统设置 > 隐私与安全性 > 辅助功能")
            enhancedLogger.info("HelloPromptApp_Integrated", "2. 点击 '+' 按钮添加应用")
            enhancedLogger.info("HelloPromptApp_Integrated", "3. 找到并选择 HelloPrompt 应用")
            enhancedLogger.info("HelloPromptApp_Integrated", "4. 确保开关处于开启状态")
            enhancedLogger.info("HelloPromptApp_Integrated", "5. 重启此应用并测试 Ctrl+U")
            enhancedLogger.info("HelloPromptApp_Integrated", "💡 如果应用已在列表中：先移除，再重新添加")
        } else {
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 所有权限已正确配置，Ctrl+U 快捷键应该可以正常工作")
        }
    }
    
    /// 直接设置快捷键回调
    private func setupDirectHotkeyCallbacks() {
        enhancedLogger.info("HelloPromptApp_Integrated", "🎯 直接设置快捷键回调")
        
        // 设置快捷键回调（绕过复杂的权限管理）
        hotkeyService.onCtrlURecordingStart = {
            self.enhancedLogger.info("HelloPromptApp_Integrated", "🎙️ 快捷键触发：开始录音")
            Task {
                self.startEnhancedWorkflow()
            }
        }
        
        hotkeyService.onCtrlURecordingStop = {
            self.enhancedLogger.info("HelloPromptApp_Integrated", "🛑 快捷键触发：停止录音")
            Task {
                await self.stopEnhancedWorkflow()
            }
        }
        
        enhancedLogger.info("HelloPromptApp_Integrated", "✅ 快捷键回调设置完成")
    }
    
    private func micStatusText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "✅ 已授权"
        case .denied: return "❌ 已拒绝"
        case .notDetermined: return "⚠️ 未确定"
        case .restricted: return "🚫 受限制"
        @unknown default: return "❓ 未知状态"
        }
    }
    
    // MARK: - 智能权限重新检测
    
    /// 智能权限重新检测和快捷键服务初始化
    @MainActor
    private func performIntelligentPermissionRecheck() {
        enhancedLogger.info("HelloPromptApp_Integrated", "🧠 执行智能权限重新检测")
        
        let bundleId = HelloPromptApp_Integrated.bundleIdentifier
        enhancedLogger.debug("HelloPromptApp_Integrated", "📋 当前Bundle ID: \(bundleId)")
        
        // 获取当前可执行文件路径
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        enhancedLogger.debug("HelloPromptApp_Integrated", "📁 当前可执行文件路径: \(executablePath)")
        
        // 直接检查 AXIsProcessTrusted（这是最准确的）
        let hasPermissionDirect = AXIsProcessTrusted()
        enhancedLogger.debug("HelloPromptApp_Integrated", "🔐 AXIsProcessTrusted() 结果: \(hasPermissionDirect)")
        
        // 检查快捷键服务状态
        let isHotkeyEnabled = hotkeyService.isEnabled
        enhancedLogger.debug("HelloPromptApp_Integrated", "⌨️ HotkeyService.isEnabled: \(isHotkeyEnabled)")
        
        // 修复：即使 AXIsProcessTrusted() 返回 false，也尝试重新初始化快捷键服务
        // 因为用户已经配置了权限，可能是 API 检测不准确
        if !isHotkeyEnabled {
            enhancedLogger.info("HelloPromptApp_Integrated", "🔄 检测到快捷键服务未启用，尝试重新初始化")
            enhancedLogger.info("HelloPromptApp_Integrated", "💡 注意：即使权限检测显示未授权，也尝试初始化快捷键服务")
            enhancedLogger.info("HelloPromptApp_Integrated", "   因为 AXIsProcessTrusted() 对 SPM 构建的应用可能不准确")
            
            // 重新初始化快捷键服务
            hotkeyService.reinitializeEventTap()
            setupEnhancedGlobalHotkeys()
            
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 快捷键服务重新初始化完成")
            enhancedLogger.info("HelloPromptApp_Integrated", "🎯 现在尝试使用 Ctrl+U 快捷键，应该可以在后台工作了！")
            enhancedLogger.info("HelloPromptApp_Integrated", "💡 如果快捷键仍然不工作，请按 Cmd+Shift+A 获取详细诊断")
        } else {
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 快捷键服务已启用，Ctrl+U 应该可以正常工作")
        }
    }
    
    // MARK: - 应用启动和初始化
    private func setupApplication() {
        enhancedLogger.startupLog("🚀 Hello Prompt v2 彻底防循环启动", component: "HelloPromptApp_Integrated")
        
        // 首先全局禁用所有权限检查，彻底避免循环
        PermissionManager.disableAllPermissionChecks()
        
        // 运行直接权限诊断
        diagnosePermissions()
        
        // 简化的回调设置（去掉复杂的权限管理器）
        setupSimplifiedCallbacks()
        
        // 初始化AppManager（关键修复）
        Task {
            await appManager.initialize()
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ AppManager初始化完成")
            
            // 重新启用权限检查（在AppManager初始化完成后）
            PermissionManager.enableAllPermissionChecks()
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ 权限检查已重新启用")
            
            // 主动同步权限状态，确保EnhancedPermissionManager状态准确
            await EnhancedPermissionManager.shared.checkAllPermissionsEnhanced(reason: "应用启动状态同步", showPrompts: true)
            enhancedLogger.info("HelloPromptApp_Integrated", "🔄 权限状态已同步")
            
            // 在权限同步后设置全局快捷键（关键修复：之前缺失的调用）
            await MainActor.run {
                setupEnhancedGlobalHotkeys()
                enhancedLogger.info("HelloPromptApp_Integrated", "✅ 全局快捷键已注册")
                
                // 智能权限重新检测和快捷键服务初始化
                performIntelligentPermissionRecheck()
            }
        }
        
        // 检查新手引导
        checkAndShowEnhancedOnboarding()
        
        enhancedLogger.info("HelloPromptApp_Integrated", "✅ 彻底防循环应用启动完成")
    }
    
    /// 简化的回调设置
    private func setupSimplifiedCallbacks() {
        enhancedLogger.info("HelloPromptApp_Integrated", "⚙️ 设置简化回调")
        
        // 只设置必要的工作流回调
        enhancedWorkflowManager.onWorkflowStarted = { workflowId in
            self.enhancedLogger.userActionLog("🚀 工作流已启动", metadata: ["workflow_id": workflowId.uuidString])
            self.updateUIForWorkflowState(.recording)
        }
        
        enhancedWorkflowManager.onWorkflowCompleted = { result in
            self.enhancedLogger.info("HelloPromptApp_Integrated", "🎉 工作流完成")
            self.showEnhancedResult(result)
            self.updateUIForWorkflowState(.completed)
        }
        
        enhancedWorkflowManager.onWorkflowFailed = { error in
            self.enhancedLogger.error("HelloPromptApp_Integrated", "💥 工作流失败: \(error.localizedDescription)")
            self.updateUIForWorkflowState(.error)
        }
        
        enhancedLogger.info("HelloPromptApp_Integrated", "✅ 简化回调设置完成")
    }
    
    private func checkAndShowEnhancedOnboarding() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "HelloPrompt_OnboardingCompleted")
        
        if !hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.isShowingOnboarding = true
                enhancedLogger.userActionLog("首次启动，显示新手引导")
            }
        } else {
            enhancedLogger.info("HelloPromptApp_Integrated", "已完成新手引导，跳过")
        }
    }
    
    // MARK: - API配置验证
    private func validateAPIConfiguration() async {
        enhancedLogger.info("HelloPromptApp_Integrated", "开始验证API配置")
        
        let apiKey = (try? configManager.getOpenAIAPIKey()) ?? ""
        let baseURL = configManager.openAIBaseURL
        
        guard !apiKey.isEmpty else {
            enhancedLogger.warning("HelloPromptApp_Integrated", "API密钥为空，跳过验证")
            return
        }
        
        let result = await enhancedAPIValidator.validateAPIConfiguration(
            apiKey: apiKey,
            baseURL: baseURL,
            organizationId: configManager.openAIOrganization
        )
        
        if result.isValid {
            enhancedLogger.info("HelloPromptApp_Integrated", "✅ API配置验证通过")
        } else {
            let errorDescription = result.errors.first?.localizedDescription ?? "未知错误"
            enhancedLogger.error("HelloPromptApp_Integrated", "❌ API配置验证失败: \(errorDescription)")
        }
    }
    
    // MARK: - 增强工作流管理
    
    /// 开始增强工作流
    private func startEnhancedWorkflow() {
        enhancedLogger.userActionLog("开始增强工作流")
        
        // 检查是否可以开始工作流
        let readiness = enhancedWorkflowManager.canStartWorkflow()
        guard readiness.canStart else {
            enhancedLogger.warning("HelloPromptApp_Integrated", "无法开始工作流: \(readiness.reason ?? "未知原因")")
            return
        }
        
        // 显示录音界面
        orbVisible = true
        
        Task {
            await enhancedWorkflowManager.startVoiceToTextWorkflow()
        }
    }
    
    /// 停止增强工作流
    private func stopEnhancedWorkflow() async {
        enhancedLogger.userActionLog("停止增强工作流")
        await enhancedWorkflowManager.cancelWorkflow()
    }
    
    /// 取消当前工作流
    private func cancelCurrentWorkflow() {
        Task {
            await enhancedWorkflowManager.cancelWorkflow()
        }
    }
    
    // MARK: - 快捷键设置
    private func setupEnhancedGlobalHotkeys() {
        let hotkeyHandlers: [HotkeyIdentifier: () -> Void] = [
            .startRecording: startEnhancedWorkflow,
            .stopRecording: cancelCurrentWorkflow,
            .retryRecording: retryEnhancedWorkflow,
            .insertResult: insertLastResult,
            .copyResult: copyLastResult,
            .showSettings: showSettings,
            .togglePause: togglePause,
            .cancelOperation: cancelOperation
        ]
        
        for (identifier, handler) in hotkeyHandlers {
            let defaultShortcut: KeyboardShortcut
            switch identifier {
            case .startRecording:
                defaultShortcut = KeyboardShortcut("u", modifiers: [.control])
            case .stopRecording:
                defaultShortcut = KeyboardShortcut(.escape, modifiers: [.option])
            default:
                defaultShortcut = KeyboardShortcut(.space, modifiers: [.control, .shift])
            }
            
            _ = hotkeyService.registerHotkey(identifier, shortcut: defaultShortcut, handler: handler)
        }
        
        enhancedLogger.info("HelloPromptApp_Integrated", "增强版全局快捷键已设置")
    }
    
    // MARK: - 状态监听
    private func setupEnhancedStateObservation() {
        // 监听工作流状态变化
        enhancedWorkflowManager.$currentState
            .receive(on: DispatchQueue.main)
            .sink { newState in
                updateUIForWorkflowState(newState)
            }
            .store(in: &appDelegate.cancellables)
        
        // 监听权限状态变化
        enhancedPermissionManager.$permissionStates
            .receive(on: DispatchQueue.main)
            .sink { states in
                let accessibilityGranted = states[.accessibility]?.status.isGranted ?? false
                let microphoneGranted = states[.microphone]?.status.isGranted ?? false
                
                enhancedLogger.debug("HelloPromptApp_Integrated", "权限状态更新 - 辅助功能: \(accessibilityGranted), 麦克风: \(microphoneGranted)")
                
                if accessibilityGranted && !hotkeyService.isEnabled {
                    enhancedLogger.info("HelloPromptApp_Integrated", "辅助功能权限已授权，重新初始化快捷键服务")
                    hotkeyService.reinitializeEventTap()
                }
                
                if microphoneGranted {
                    Task {
                    try? await enhancedWorkflowManager.audioService.initialize()
                    }
                }
            }
            .store(in: &appDelegate.cancellables)
        
        enhancedLogger.debug("HelloPromptApp_Integrated", "👁️ 增强状态观察器已设置")
    }
    
    private func updateUIForWorkflowState(_ state: WorkflowState) {
        currentWorkflowState = state
        
        switch state {
        case .idle:
            orbState = .idle
            orbVisible = false
        case .recording:
            orbState = .recording
            orbVisible = true
        case .processingAudio, .transcribing, .optimizing:
            orbState = .processing
            orbVisible = true
        case .displaying:
            orbState = .result
            orbVisible = true
        case .completed:
            orbState = .idle
            orbVisible = false
        case .error:
            orbState = .error
            orbVisible = false
        }
    }
    
    // MARK: - 结果处理
    private func showEnhancedResult(_ workflowResult: WorkflowResult) {
        let overlayResult = OverlayResult(
            originalText: workflowResult.transcribedText,
            optimizedText: workflowResult.optimizedText,
            processingTime: workflowResult.processingTime,
            confidence: 0.95,
            timestamp: Date()
        )
        
        currentResult = overlayResult
        showingResult = true
        
        enhancedLogger.info("HelloPromptApp_Integrated", """
            显示增强工作流结果:
            原始文本: \(workflowResult.transcribedText.prefix(50))...
            优化文本: \(workflowResult.optimizedText.prefix(50))...
            处理时间: \(String(format: "%.2f", workflowResult.processingTime))s
            """)
    }
    
    // MARK: - 操作处理
    private func retryEnhancedWorkflow() {
        Task {
            await enhancedWorkflowManager.forceReset()
            _ = await enhancedWorkflowManager.startVoiceToTextWorkflow()
        }
    }
    
    private func insertLastResult() {
        Task {
            if let result = enhancedWorkflowManager.lastResult {
                let text = result.optimizedText
                await appManager.insertTextToActiveApplication()
                enhancedLogger.userActionLog("插入文本到当前应用", metadata: ["text_length": text.count])
            }
        }
    }
    
    private func copyLastResult() {
        if let result = enhancedWorkflowManager.lastResult {
            let text = result.optimizedText
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            enhancedLogger.userActionLog("复制结果到剪贴板", metadata: ["text_length": text.count])
        }
    }
    
    private func togglePause() {
        enhancedLogger.userActionLog("切换暂停状态")
    }
    
    private func cancelOperation() {
        cancelCurrentWorkflow()
    }
    
    // MARK: - UI控制
    private func showSettings() {
        isShowingSettings = true
        enhancedLogger.userActionLog("显示设置界面")
    }
    
    private func showOnboarding() {
        isShowingOnboarding = true
        enhancedLogger.userActionLog("显示新手引导")
    }
    
    private func showAbout() {
        let aboutPanel = NSAlert()
        aboutPanel.messageText = "Hello Prompt v2 (增强版)"
        aboutPanel.informativeText = """
        版本 2.0.0 (增强版)
        
        AI驱动的语音转提示词工具
        集成增强工作流、权限管理、API验证和日志系统
        
        © 2024 Hello Prompt Team
        """
        aboutPanel.alertStyle = .informational
        aboutPanel.addButton(withTitle: "确定")
        aboutPanel.runModal()
    }
    
    private func configureRecordingWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let recordingWindows = NSApp.windows.filter { window in
                window.title.contains("录音") || window.identifier?.rawValue == "recording-overlay"
            }
            
            for window in recordingWindows {
                window.level = .screenSaver
                window.backgroundColor = NSColor.clear
                window.isOpaque = false
                window.hasShadow = false
                window.ignoresMouseEvents = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                
                if let screen = NSScreen.main {
                    let screenRect = screen.visibleFrame
                    let windowRect = window.frame
                    let x = screenRect.midX - windowRect.width / 2
                    let y = screenRect.midY - windowRect.height / 2
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
                
                if self.orbVisible {
                    window.orderFront(nil)
                    window.makeKey()
                } else {
                    window.orderOut(nil)
                }
            }
        }
    }
    
    private func configureResultWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let resultWindows = NSApp.windows.filter { window in
                window.title.contains("结果显示") || window.identifier?.rawValue == "result-overlay"
            }
            
            for window in resultWindows {
                window.level = .floating
                window.backgroundColor = NSColor.clear
                window.isOpaque = false
                window.hasShadow = true
                window.ignoresMouseEvents = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                
                if let screen = NSScreen.main {
                    let screenRect = screen.visibleFrame
                    let windowSize = CGSize(width: 600, height: 400)
                    let x = screenRect.midX - windowSize.width / 2
                    let y = screenRect.midY - windowSize.height / 2
                    window.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: windowSize), display: true)
                }
                
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // MARK: - 结果处理
    private func handleResultAction(_ action: OverlayAction, text: String) {
        enhancedLogger.userActionLog("处理结果操作: \(action.rawValue)")
        
        Task {
            switch action {
            case .insert:
                await appManager.insertTextToActiveApplication()
                
            case .copy:
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                enhancedLogger.userActionLog("文本已复制到剪贴板", metadata: ["text_length": text.count])
                
            case .accept:
                await appManager.insertTextToActiveApplication()
                showingResult = false
                currentResult = nil
                
            case .close, .cancel:
                showingResult = false
                currentResult = nil
                
            default:
                enhancedLogger.debug("HelloPromptApp_Integrated", "未处理的操作: \(action.rawValue)")
            }
        }
    }
}

// MARK: - 应用委托（增强版）
class AppDelegate_Integrated: NSObject, NSApplicationDelegate, ObservableObject {
    var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        EnhancedLogManager.shared.startupLog("增强版应用启动完成", component: "AppDelegate_Integrated")
        
        // 立即配置应用激活策略
        NSApp.setActivationPolicy(.regular)
        
        // 强制激活应用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            self.showInitialInterface()
        }
    }
    
    @MainActor
    private func showInitialInterface() {
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        
        if visibleWindows.isEmpty {
            EnhancedLogManager.shared.info("AppDelegate_Integrated", "创建初始设置窗口")
            
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            
            settingsWindow.title = "Hello Prompt v2 - 设置 (增强版)"
            settingsWindow.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            if let firstWindow = visibleWindows.first {
                firstWindow.makeKeyAndOrderFront(self)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        EnhancedLogManager.shared.info("AppDelegate_Integrated", "应用即将退出")
        
        Task {
            await AppManager.shared.shutdown()
            EnhancedLogManager.shared.flush()
        }
        
        cancellables.removeAll()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "设置 (增强版)"
            settingsWindow.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

// MARK: - 应用信息扩展
extension HelloPromptApp_Integrated {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    }
    
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }
    
    static var bundleIdentifier: String {
        // 优先使用Bundle中的ID，如果没有则使用固定值
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            return bundleId
        }
        
        // SPM项目的备用Bundle ID
        return "com.helloprompt.app"
    }
}