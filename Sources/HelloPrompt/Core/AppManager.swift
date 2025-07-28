//
//  AppManager.swift
//  HelloPrompt
//
//  应用状态管理器 - 协调整个系统的工作流程，管理全局状态和服务间通信
//  实现Siri风格的用户交互流程和状态机
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import ApplicationServices

// MARK: - 应用状态枚举
public enum AppState: String, CaseIterable {
    case launching = "启动中"
    case idle = "空闲"
    case listening = "监听中"
    case recording = "录音中"
    case processing = "处理中"
    case presenting = "展示结果"
    case modifying = "修改中"
    case inserting = "插入文本"
    case error = "错误状态"
    case suspended = "暂停"
    
    var canTransitionTo: [AppState] {
        switch self {
        case .launching:
            return [.idle, .error]
        case .idle:
            return [.listening, .presenting, .suspended, .error]
        case .listening:
            return [.recording, .idle, .error]
        case .recording:
            return [.processing, .idle, .error]
        case .processing:
            return [.presenting, .error, .idle]
        case .presenting:
            return [.modifying, .inserting, .idle, .error]
        case .modifying:
            return [.processing, .presenting, .idle, .error]
        case .inserting:
            return [.idle, .error]
        case .error:
            return [.idle, .suspended, .error]  // 允许error -> error转换（用于错误更新）
        case .suspended:
            return [.idle, .error]
        }
    }
    
    var isInteractive: Bool {
        switch self {
        case .idle, .presenting, .error:
            return true
        default:
            return false
        }
    }
    
    var requiresUI: Bool {
        switch self {
        case .presenting, .modifying, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - 工作流程进度状态
public struct WorkflowProgress {
    var currentStep: Int = 0
    var totalSteps: Int = 0
    var stepDescription: String = ""
    var progress: Float = 0.0
    var startTime: Date?
    var estimatedCompletion: Date?
    
    mutating func start(totalSteps: Int, description: String) {
        self.totalSteps = totalSteps
        self.currentStep = 0
        self.stepDescription = description
        self.progress = 0.0
        self.startTime = Date()
        self.estimatedCompletion = nil
    }
    
    mutating func nextStep(_ description: String) {
        currentStep += 1
        stepDescription = description
        progress = Float(currentStep) / Float(totalSteps)
        
        // 估算完成时间
        if let startTime = startTime, currentStep > 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let avgTimePerStep = elapsed / Double(currentStep)
            let remainingSteps = totalSteps - currentStep
            estimatedCompletion = Date().addingTimeInterval(avgTimePerStep * Double(remainingSteps))
        }
    }
    
    mutating func complete() {
        currentStep = totalSteps
        progress = 1.0
        stepDescription = "完成"
        estimatedCompletion = Date()
    }
    
    mutating func reset() {
        currentStep = 0
        totalSteps = 0
        stepDescription = ""
        progress = 0.0
        startTime = nil
        estimatedCompletion = nil
    }
}

// MARK: - 系统性能监控
public struct SystemPerformance {
    let cpuUsage: Double
    let memoryUsage: UInt64
    let diskSpace: UInt64
    let networkLatency: TimeInterval?
    let batteryLevel: Float?
    
    var isOptimal: Bool {
        return cpuUsage < 80.0 && 
               memoryUsage < 1024 * 1024 * 1024 && // < 1GB
               diskSpace > 100 * 1024 * 1024 // > 100MB
    }
}

// MARK: - 主应用管理器
@MainActor
public final class AppManager: ObservableObject {
    
    // MARK: - 单例实例
    public static let shared = AppManager()
    
    // MARK: - Published Properties
    @Published public var appState: AppState = .launching
    @Published public var workflowState = WorkflowProgress()
    @Published public var isProcessing = false
    @Published public var currentPrompt: String = ""
    @Published public var lastResult: String = ""
    @Published public var lastOptimizationResult: OptimizationResult?
    @Published public var systemPerformance: SystemPerformance?
    
    // MARK: - 服务实例
    public let audioService = AudioService()
    public let openAIService = OpenAIService()
    public let textInsertionService = TextInsertionService()
    public let configManager = AppConfigManager.shared
    public let errorHandler = ErrorHandler.shared
    public let logManager = LogManager.shared
    
    // MARK: - 私有属性
    private var cancellables = Set<AnyCancellable>()
    private var stateTransitionTimer: Timer?
    private var performanceMonitorTimer: Timer?
    private var lastStateTransition: Date = Date()
    
    // 工作流程控制
    private var currentWorkflowTask: Task<Void, Never>?
    private var isWorkflowRunning = false
    
    // MARK: - 初始化
    private init() {
        LogManager.shared.startupLog("⚙️ AppManager 初始化开始", component: "AppManager")
        
        LogManager.shared.startupLog("📊 设置状态监听", component: "AppManager")
        setupStateObservation()
        
        LogManager.shared.startupLog("📈 设置性能监控", component: "AppManager")
        setupPerformanceMonitoring()
        
        LogManager.shared.startupLog("🔧 配置服务", component: "AppManager")
        configureServices()
        
        LogManager.shared.startupLog("✅ AppManager 初始化完成", component: "AppManager", details: [
            "initialState": appState.rawValue,
            "servicesCount": 4
        ])
    }
    
    deinit {
        // 直接调用清理方法，避免在deinit中使用Task
        cancellables.removeAll()
        currentWorkflowTask?.cancel()
    }
    
    // MARK: - 应用生命周期
    public func initialize() async {
        LogManager.shared.startupLog("🚀 AppManager.initialize() 开始", component: "AppManager", details: [
            "currentState": appState.rawValue
        ])
        
        appState = .launching
        
        LogManager.shared.startupLog("📋 应用初始化工作流开始", component: "AppManager")
        
        workflowState.start(totalSteps: 4, description: "初始化应用组件")
        
        do {
            // 步骤1: 配置管理器初始化
            LogManager.shared.startupLog("1️⃣ 初始化配置管理器", component: "AppManager")
            workflowState.nextStep("初始化配置管理器")
            try await initializeConfigManager()
            LogManager.shared.startupLog("✅ 配置管理器初始化完成", component: "AppManager")
            
            // 步骤2: 音频服务初始化
            LogManager.shared.startupLog("2️⃣ 初始化音频服务", component: "AppManager")
            workflowState.nextStep("初始化音频服务")
            try await audioService.initialize()
            LogManager.shared.startupLog("✅ 音频服务初始化完成", component: "AppManager", details: [
                "isInitialized": audioService.isInitialized
            ])
            
            // 步骤3: OpenAI服务配置
            LogManager.shared.startupLog("3️⃣ 配置OpenAI服务", component: "AppManager")
            workflowState.nextStep("配置OpenAI服务")
            try await configureOpenAIService()
            LogManager.shared.startupLog("✅ OpenAI服务配置完成", component: "AppManager")
            
            // 步骤4: 系统权限检查
            LogManager.shared.startupLog("4️⃣ 检查系统权限", component: "AppManager")
            workflowState.nextStep("检查系统权限")
            try await checkSystemPermissions()
            LogManager.shared.startupLog("✅ 系统权限检查完成", component: "AppManager")
            
            workflowState.complete()
            
            // 转换到空闲状态
            LogManager.shared.startupLog("🎯 转换到空闲状态", component: "AppManager")
            await transitionToState(.idle)
            
            LogManager.shared.startupLog("🎉 应用初始化完成", component: "AppManager", details: [
                "finalState": appState.rawValue,
                "workflowProgress": workflowState.progress
            ])
            
        } catch {
            LogManager.shared.startupLog("❌ 应用初始化失败", level: .error, component: "AppManager", details: [
                "error": error.localizedDescription,
                "errorType": String(describing: type(of: error))
            ])
            
            logManager.error("AppManager", "应用初始化失败: \(error)")
            errorHandler.handle(error as? HelloPromptError ?? 
                               AudioSystemError.audioEngineFailure(error))
            await transitionToState(.error)
        }
    }
    
    public func suspend() async {
        logManager.info("AppManager", "应用暂停")
        
        currentWorkflowTask?.cancel()
        
        if audioService.isRecording {
            audioService.cancelRecording()
        }
        
        await transitionToState(.suspended)
    }
    
    public func resume() async {
        logManager.info("AppManager", "应用恢复")
        
        // 重新检查系统状态
        do {
            try await checkSystemPermissions()
            await transitionToState(.idle)
        } catch {
            await transitionToState(.error)
        }
    }
    
    public func shutdown() async {
        logManager.info("AppManager", "应用关闭")
        
        currentWorkflowTask?.cancel()
        textInsertionService.cleanup()
        cleanup()
        
        // 保存应用状态
        saveApplicationState()
    }
    
    // MARK: - 主工作流程
    
    /// 开始语音到提示词的完整工作流程
    public func startVoiceToPromptWorkflow() async {
        LogManager.shared.info("AppManager", "startVoiceToPromptWorkflow 被调用，当前状态: \(appState)")
        
        // 取消现有的工作流任务
        if let existingTask = currentWorkflowTask {
            LogManager.shared.info("AppManager", "取消现有工作流任务")
            existingTask.cancel()
            currentWorkflowTask = nil
            
            // 等待一小段时间让取消操作完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // 放宽状态检查，允许从更多状态开始工作流程
        if appState == .recording || appState == .processing {
            LogManager.shared.warning("AppManager", "工作流程已在进行中，状态: \(appState)，强制重置")
            await resetApplicationState()
        }
        
        // 如果当前不是idle状态，尝试重置到idle
        if appState != .idle {
            LogManager.shared.info("AppManager", "当前状态非idle(\(appState))，尝试重置状态")
            await resetApplicationState()
        }
        
        LogManager.shared.info("AppManager", "开始执行语音转换工作流程")
        
        currentWorkflowTask = Task {
            await performVoiceToPromptWorkflow()
        }
    }
    
    private func performVoiceToPromptWorkflow() async {
        isWorkflowRunning = true
        
        do {
            workflowState.start(totalSteps: 5, description: "语音转换提示词")
            
            // 步骤1: 开始录音
            await transitionToState(.listening)
            workflowState.nextStep("准备录音")
            
            await transitionToState(.recording)
            workflowState.nextStep("录音中")
            
            try await audioService.startRecording()
            
            // 稳定的录音等待逻辑 - 不受Task取消影响
            LogManager.shared.debug("AppManager", "开始等待录音完成")
            var waitCount = 0
            let recordingStartTime = Date()
            
            while audioService.isRecording && audioService.state == .recording {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitCount += 1
                
                let actualDuration = Date().timeIntervalSince(recordingStartTime)
                
                // 每5秒记录一次等待状态
                if waitCount % 50 == 0 {
                    LogManager.shared.debug("AppManager", "等待录音完成中，已等待 \(String(format: "%.1f", actualDuration)) 秒")
                }
                
                // 真正的超时保护（使用实际时间，而不是循环计数）
                if actualDuration >= 300.0 { // 5分钟真实超时
                    LogManager.shared.warning("AppManager", "录音达到最大时长(\(String(format: "%.1f", actualDuration))秒)，自动停止")
                        _ = try? await audioService.stopRecording()
                    break
                }
                
                // 检查录音状态是否异常
                if audioService.state == .error {
                    LogManager.shared.warning("AppManager", "检测到录音错误状态，停止等待")
                    break
                }
            }
            
            let finalDuration = Date().timeIntervalSince(recordingStartTime)
            LogManager.shared.debug("AppManager", "录音等待完成，实际时间: \(String(format: "%.1f", finalDuration)) 秒")
            
            // 步骤2: 处理音频
            await transitionToState(.processing)
            workflowState.nextStep("处理音频")
            
            // 智能判断录音结束原因
            let audioData: Data
            
            if audioService.isRecording {
                // 录音仍在进行，正常停止
                if let data = try await audioService.stopRecording() {
                    audioData = data
                } else {
                    throw AudioSystemError.audioBufferProcessingFailed
                }
            } else {
                // 录音已经停止，检查停止原因
                switch audioService.detailedState {
                case .cancelled:
                    LogManager.shared.info("AppManager", "录音被用户取消")
                    throw CancellationError()
                case .error(let message):
                    LogManager.shared.error("AppManager", "录音出现错误: \(message)")
                    throw AudioSystemError.audioBufferProcessingFailed
                default:
                    // 可能是VAD自动停止，尝试获取数据
                    if let data = try await audioService.stopRecording() {
                        audioData = data
                    } else {
                        LogManager.shared.warning("AppManager", "无法获取录音数据，可能录音时间过短")
                        throw AudioSystemError.audioQualityTooLow(rms: 0.0)
                    }
                }
            }
            
            // 步骤3: 语音识别
            workflowState.nextStep("语音识别")
            
            let transcriptionResult = await openAIService.transcribeAudio(audioData)
            
            switch transcriptionResult {
            case .success(let result):
                currentPrompt = result.text
                
                // 步骤4: 提示词优化
                workflowState.nextStep("优化提示词")
                
                let optimizationResult = await openAIService.optimizePrompt(
                    result.text,
                    context: getCurrentApplicationContext()
                )
                
                switch optimizationResult {
                case .success(let optimized):
                    lastResult = optimized.optimizedPrompt
                    lastOptimizationResult = optimized
                    workflowState.complete()
                    
                    // 步骤5: 展示结果
                    await transitionToState(.presenting)
                    
                    logManager.info("AppManager", """
                        工作流程完成
                        原始文本: \(result.text.prefix(50))...
                        优化结果: \(optimized.optimizedPrompt.prefix(50))...
                        处理时间: \(String(format: "%.2f", optimized.processingTime))s
                        改进点数量: \(optimized.improvements.count)
                        """)
                    
                case .failure(let error):
                    throw error
                }
                
            case .failure(let error):
                throw error
            }
            
        } catch {
            if error is CancellationError {
                logManager.info("AppManager", "工作流程被取消")
                await transitionToState(.idle)
            } else {
                logManager.error("AppManager", "工作流程失败: \(error)")
                
                if let helloPromptError = error as? HelloPromptError {
                    errorHandler.handle(helloPromptError)
                } else {
                    errorHandler.handle(AudioSystemError.audioEngineFailure(error))
                }
                
                await transitionToState(.error)
            }
        }
        
        isWorkflowRunning = false
    }
    
    /// 语音修改工作流程
    public func startVoiceModificationWorkflow() async {
        guard appState == .presenting, !lastResult.isEmpty else {
            logManager.warning("AppManager", "当前状态不允许开始修改工作流程")
            return
        }
        
        currentWorkflowTask = Task {
            await performVoiceModificationWorkflow()
        }
    }
    
    private func performVoiceModificationWorkflow() async {
        do {
            await transitionToState(.modifying)
            workflowState.start(totalSteps: 4, description: "语音修改提示词")
            
            // 步骤1: 录制修改需求
            workflowState.nextStep("录制修改需求")
            
            try await audioService.startRecording()
            
            while audioService.isRecording {
                try await Task.sleep(nanoseconds: 100_000_000)
                try Task.checkCancellation()
            }
            
            // 步骤2: 处理修改音频
            workflowState.nextStep("处理音频")
            
            // 智能判断录音结束原因
            let audioData: Data
            
            if audioService.isRecording {
                // 录音仍在进行，正常停止
                if let data = try await audioService.stopRecording() {
                    audioData = data
                } else {
                    throw AudioSystemError.audioBufferProcessingFailed
                }
            } else {
                // 录音已经停止，检查停止原因
                switch audioService.detailedState {
                case .cancelled:
                    LogManager.shared.info("AppManager", "修改录音被用户取消")
                    throw CancellationError()
                case .error(let message):
                    LogManager.shared.error("AppManager", "修改录音出现错误: \(message)")
                    throw AudioSystemError.audioBufferProcessingFailed
                default:
                    // 可能是VAD自动停止，尝试获取数据
                    if let data = try await audioService.stopRecording() {
                        audioData = data
                    } else {
                        LogManager.shared.warning("AppManager", "无法获取修改录音数据，可能录音时间过短")
                        throw AudioSystemError.audioQualityTooLow(rms: 0.0)
                    }
                }
            }
            
            // 步骤3: 识别修改需求
            workflowState.nextStep("识别修改需求")
            
            let transcriptionResult = await openAIService.transcribeAudio(audioData)
            
            switch transcriptionResult {
            case .success(let result):
                // 步骤4: 执行修改
                workflowState.nextStep("执行修改")
                
                let modificationResult = await openAIService.modifyPrompt(
                    lastResult,
                    modificationRequest: result.text
                )
                
                switch modificationResult {
                case .success(let modified):
                    lastResult = modified.optimizedPrompt
                    workflowState.complete()
                    
                    await transitionToState(.presenting)
                    
                    logManager.info("AppManager", """
                        修改工作流程完成
                        修改需求: \(result.text)
                        修改结果: \(modified.optimizedPrompt.prefix(50))...
                        """)
                    
                case .failure(let error):
                    throw error
                }
                
            case .failure(let error):
                throw error
            }
            
        } catch {
            logManager.error("AppManager", "修改工作流程失败: \(error)")
            
            if let helloPromptError = error as? HelloPromptError {
                errorHandler.handle(helloPromptError)
            } else {
                errorHandler.handle(AudioSystemError.audioEngineFailure(error))
            }
            
            await transitionToState(.error)
        }
    }
    
    /// 文本插入工作流程
    public func insertTextToActiveApplication() async {
        guard appState == .presenting, !lastResult.isEmpty else {
            logManager.warning("AppManager", "当前状态不允许插入文本")
            return
        }
        
        await transitionToState(.inserting)
        
        workflowState.start(totalSteps: 3, description: "插入文本")
        workflowState.nextStep("检查权限")
        
        // 检查权限状态
        let permissions = textInsertionService.checkPermissions()
        if !(permissions["accessibility"] ?? false) {
            logManager.warning("AppManager", "辅助功能权限未授权，尝试请求权限")
            
            let permissionGranted = await textInsertionService.requestPermissions()
            if !permissionGranted {
                // 权限未授权，显示警告并复制到剪贴板
                await showAccessibilityPermissionWarning()
                copyLastResult()
                await transitionToState(.idle)
                return
            }
        }
        
        workflowState.nextStep("检测目标应用")
        
        // 检查是否可以插入文本
        if !textInsertionService.canInsertText() {
            logManager.warning("AppManager", "当前应用不支持文本插入，复制到剪贴板")
            copyLastResult()
            await transitionToState(.idle)
            return
        }
        
        workflowState.nextStep("插入文本")
        
        // 执行文本插入
        let insertionResult = await textInsertionService.insertText(lastResult)
        
        workflowState.complete()
        
        if insertionResult.success {
            logManager.info("AppManager", """
                文本插入成功:
                策略: \(insertionResult.strategy.rawValue)
                目标应用: \(insertionResult.targetApplication)
                耗时: \(String(format: "%.3f", insertionResult.duration))s
                """)
        } else {
            logManager.error("AppManager", "文本插入失败: \(insertionResult.error?.localizedDescription ?? "未知错误")")
            
            // 插入失败，复制到剪贴板作为后备方案
            copyLastResult()
        }
        
        await transitionToState(.idle)
    }
    
    /// 显示辅助功能权限警告
    private func showAccessibilityPermissionWarning() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = """
            文本插入功能需要辅助功能权限。
            
            作为替代方案，文本已复制到剪贴板，您可以手动粘贴到目标应用程序中。
            
            要启用自动文本插入功能，请在系统设置中授权辅助功能权限。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "好的")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // 打开系统设置的辅助功能页面
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// 复制最后结果到剪贴板
    private func copyLastResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastResult, forType: .string)
        
        logManager.info("AppManager", "结果已复制到剪贴板")
    }
    
    // MARK: - 状态管理
    private func transitionToState(_ newState: AppState) async {
        guard appState.canTransitionTo.contains(newState) else {
            logManager.warning("AppManager", "非法状态转换: \(appState) -> \(newState)")
            return
        }
        
        let oldState = appState
        appState = newState
        lastStateTransition = Date()
        
        logManager.info("AppManager", "状态转换: \(oldState) -> \(newState)")
        
        // 状态进入处理
        await handleStateEntry(newState, from: oldState)
        
        // 性能监控
        if newState == .processing {
            isProcessing = true
        } else if oldState == .processing {
            isProcessing = false
        }
    }
    
    private func handleStateEntry(_ state: AppState, from previousState: AppState) async {
        switch state {
        case .idle:
            workflowState.reset()
            currentPrompt = ""
            
        case .error:
            isProcessing = false
            currentWorkflowTask?.cancel()
            
        case .presenting:
            // 准备展示UI
            break
            
        default:
            break
        }
    }
    
    // MARK: - 服务配置
    private func setupStateObservation() {
        // 监听音频服务状态
        audioService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] audioState in
                self?.handleAudioStateChange(audioState)
            }
            .store(in: &cancellables)
        
        // 监听OpenAI服务状态
        openAIService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apiState in
                self?.handleAPIStateChange(apiState)
            }
            .store(in: &cancellables)
        
        // 监听错误处理器
        errorHandler.$currentError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task {
                    await self?.transitionToState(.error)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleAudioStateChange(_ audioState: AudioProcessingState) {
        logManager.debug("AppManager", "音频状态变化: \(audioState)")
        
        switch audioState {
        case .error:
            Task {
                await transitionToState(.error)
            }
        default:
            break
        }
    }
    
    private func handleAPIStateChange(_ apiState: APIRequestState) {
        logManager.debug("AppManager", "API状态变化: \(apiState)")
        
        switch apiState {
        case .failed:
            Task {
                await transitionToState(.error)
            }
        default:
            break
        }
    }
    
    private func configureServices() {
        // 配置OpenAI服务
        if let apiKey = try? configManager.getOpenAIAPIKey(),
           !apiKey.isEmpty {
            openAIService.configure(
                apiKey: apiKey,
                baseURL: configManager.openAIBaseURL
            )
        }
    }
    
    // MARK: - 初始化辅助方法
    private func initializeConfigManager() async throws {
        // 配置管理器通常不需要异步初始化
        logManager.info("AppManager", "配置管理器已准备就绪")
    }
    
    private func configureOpenAIService() async throws {
        // 检查API密钥，但允许应用在没有密钥时启动
        if let apiKey = try? configManager.getOpenAIAPIKey(), !apiKey.isEmpty {
            openAIService.configure(
                apiKey: apiKey,
                baseURL: configManager.openAIBaseURL
            )
            
            // 测试连接（非阻塞）
            let testResult = await openAIService.testConnection()
            switch testResult {
            case .success:
                logManager.info("AppManager", "OpenAI服务连接测试成功")
            case .failure(let error):
                logManager.warning("AppManager", "OpenAI服务连接测试失败: \(error)")
                // 不抛出错误，允许应用继续运行
            }
        } else {
            logManager.warning("AppManager", "OpenAI API密钥未配置，请在设置中配置后再使用AI功能")
        }
    }
    
    private func checkSystemPermissions() async throws {
        // 智能权限检查 - 如果全局禁用则使用直接检查
        let hasMicrophonePermission: Bool
        let hasAccessibilityPermission: Bool
        
        if PermissionManager.isPermissionCheckingGloballyDisabled {
            logManager.info("AppManager", "权限检查被全局禁用，使用直接系统API检查")
            
            // 直接使用系统API检查权限
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            hasMicrophonePermission = (micStatus == .authorized)
            
            let accessibilityStatus = AXIsProcessTrusted()
            hasAccessibilityPermission = accessibilityStatus
            
            logManager.info("AppManager", "直接权限检查结果 - 麦克风: \(micStatus.rawValue), 辅助功能: \(accessibilityStatus)")
        } else {
            // 使用权限管理器检查权限
        await PermissionManager.shared.checkAllPermissions(reason: "AppManager初始化")
            hasMicrophonePermission = await PermissionManager.shared.hasPermissionAsync(.microphone)
            hasAccessibilityPermission = await PermissionManager.shared.hasPermissionAsync(.accessibility)
        }
        
        // 检查核心权限（麦克风）
        if !hasMicrophonePermission {
            let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            logManager.error("AppManager", "麦克风权限检查失败 - 当前状态: \(currentStatus)")
            
            // 如果是未确定状态，尝试请求权限
            if currentStatus == .notDetermined {
                logManager.info("AppManager", "检测到麦克风权限未确定，尝试请求权限")
                let granted = await requestMicrophonePermissionDirect()
                if !granted {
            throw AudioSystemError.microphonePermissionDenied
                }
            } else {
                throw AudioSystemError.microphonePermissionDenied
            }
        }
        
        // 辅助功能权限不是必需的，只是影响用户体验
        if !hasAccessibilityPermission {
            logManager.warning("AppManager", "辅助功能权限未授权，Ctrl+U快捷键监听将无法工作")
            // 显示权限引导界面（如果需要）
            await showAccessibilityPermissionGuidance()
        }
        
        logManager.info("AppManager", "系统权限检查完成 - 麦克风权限: ✅, 辅助功能权限: \(hasAccessibilityPermission ? "✅" : "❌")")
    }
    
    /// 直接请求麦克风权限
    private func requestMicrophonePermissionDirect() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                self.logManager.info("AppManager", "麦克风权限请求结果: \(granted ? "✅ 已授权" : "❌ 被拒绝")")
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// 显示辅助功能权限引导
    private func showAccessibilityPermissionGuidance() async {
        // 可以在这里添加引导用户授权辅助功能权限的逻辑
        logManager.info("AppManager", "需要引导用户授权辅助功能权限以启用Ctrl+U功能")
    }
    
    // MARK: - 性能监控
    private func setupPerformanceMonitoring() {
        performanceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSystemPerformance()
            }
        }
    }
    
    private func updateSystemPerformance() {
        let performance = SystemPerformance(
            cpuUsage: getCurrentCPUUsage(),
            memoryUsage: getMemoryUsage(),
            diskSpace: getAvailableDiskSpace(),
            networkLatency: nil, // 可以添加网络延迟测试
            batteryLevel: getBatteryLevel()
        )
        
        systemPerformance = performance
        
        // 性能警告
        if !performance.isOptimal {
            logManager.warning("AppManager", """
                系统性能警告
                CPU: \(String(format: "%.1f", performance.cpuUsage))%
                内存: \(formatBytes(performance.memoryUsage))
                磁盘: \(formatBytes(performance.diskSpace))
                """)
        }
    }
    
    // MARK: - 工具方法
    private func getCurrentApplicationContext() -> String {
        return textInsertionService.getApplicationContext()
    }
    
    private func performTextInsertion(_ text: String) async throws {
        // 使用TextInsertionService进行实际的文本插入
        let result = await textInsertionService.insertText(text)
        
        if !result.success {
            if let error = result.error {
                throw error
            } else {
                throw UIError.overlayDisplayFailed
            }
        }
    }
    
    private func saveApplicationState() {
        let state = [
            "lastPrompt": currentPrompt,
            "lastResult": lastResult,
            "appState": appState.rawValue
        ]
        
        UserDefaults.standard.set(state, forKey: "HelloPrompt_LastState")
        logManager.info("AppManager", "应用状态已保存")
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        // 简化的CPU使用率计算
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024 * 10) : 0.0
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    private func getAvailableDiskSpace() -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attributes[.systemFreeSize] as? UInt64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func getBatteryLevel() -> Float? {
        // macOS桌面应用通常不需要监控电池
        return nil
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func cleanup() {
        stateTransitionTimer?.invalidate()
        performanceMonitorTimer?.invalidate()
        currentWorkflowTask?.cancel()
        cancellables.removeAll()
        
        logManager.info("AppManager", "应用管理器已清理")
    }
    
    // MARK: - 公共接口
    
    /// 取消当前工作流程
    public func cancelCurrentWorkflow() {
        currentWorkflowTask?.cancel()
        
        if audioService.isRecording {
            audioService.cancelRecording()
        }
        
        Task {
            await transitionToState(.idle)
        }
        
        logManager.info("AppManager", "当前工作流程已取消")
    }
    
    /// 重置应用状态
    public func resetApplicationState() async {
        cancelCurrentWorkflow()
        
        currentPrompt = ""
        lastResult = ""
        workflowState.reset()
        
        await transitionToState(.idle)
        
        logManager.info("AppManager", "应用状态已重置")
    }
    
    /// 获取应用统计信息
    public func getApplicationStatistics() -> [String: Any] {
        let uptime = Date().timeIntervalSince(lastStateTransition)
        
        return [
            "currentState": appState.rawValue,
            "uptime": String(format: "%.0f", uptime),
            "isProcessing": isProcessing,
            "workflowProgress": workflowState.progress,
            "audioServiceStats": audioService.getAudioDeviceInfo(),
            "openAIServiceStats": openAIService.getPerformanceStatistics(),
            "systemPerformance": systemPerformance?.isOptimal ?? false
        ]
    }
}