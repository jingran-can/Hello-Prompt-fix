//
//  EnhancedWorkflowManager.swift
//  HelloPrompt
//
//  增强的工作流管理器 - 统一管理ASR+LLM+显示的完整工作流程
//  解决状态同步问题，确保录音悬浮球正确显示和隐藏
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

// MARK: - 工作流状态
public enum WorkflowState: String, CaseIterable, Sendable {
    case idle = "idle"
    case recording = "recording"
    case processingAudio = "processing_audio"
    case transcribing = "transcribing"  
    case optimizing = "optimizing"
    case displaying = "displaying"
    case completed = "completed"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .idle: return "待机"
        case .recording: return "录音中"
        case .processingAudio: return "处理音频"
        case .transcribing: return "语音转文字"
        case .optimizing: return "AI优化中"
        case .displaying: return "显示结果"
        case .completed: return "完成"
        case .error: return "错误"
        }
    }
    
    var shouldShowOverlay: Bool {
        switch self {
        case .idle, .completed: return false
        case .recording, .processingAudio, .transcribing, .optimizing, .displaying: return true
        case .error: return false // Hide overlay on error
        }
    }
    
    var overlayState: OrbState {
        switch self {
        case .idle, .completed, .error: return .idle
        case .recording: return .recording
        case .processingAudio, .transcribing, .optimizing: return .processing
        case .displaying: return .result
        }
    }
}

// MARK: - 工作流结果
public struct WorkflowResult {
    let originalAudio: Data
    let transcribedText: String
    let optimizedText: String
    let processingTime: TimeInterval
    let metadata: [String: Any]
    let timestamp: Date
}

// MARK: - 工作流错误
public enum WorkflowError: LocalizedError {
    case recordingFailed(Error)
    case audioProcessingFailed(Error)
    case transcriptionFailed(Error)
    case optimizationFailed(Error)
    case configurationError(String)
    case permissionDenied(String)
    case timeoutError(String)
    
    public var errorDescription: String? {
        switch self {
        case .recordingFailed(let error):
            return "录音失败: \(error.localizedDescription)"
        case .audioProcessingFailed(let error):
            return "音频处理失败: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "语音转文字失败: \(error.localizedDescription)"
        case .optimizationFailed(let error):
            return "AI优化失败: \(error.localizedDescription)"
        case .configurationError(let message):
            return "配置错误: \(message)"
        case .permissionDenied(let permission):
            return "权限被拒绝: \(permission)"
        case .timeoutError(let operation):
            return "操作超时: \(operation)"
        }
    }
}

// MARK: - 增强工作流管理器
@MainActor
public class EnhancedWorkflowManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var currentState: WorkflowState = .idle
    @Published public var progress: Double = 0.0
    @Published public var isProcessing: Bool = false
    @Published public var currentStepDescription: String = ""
    @Published public var lastResult: WorkflowResult?
    @Published public var overlayVisible: Bool = false
    @Published public var overlayState: OrbState = .idle
    
    // MARK: - Dependencies
    public let audioService: AudioService
    private let openAIService: OpenAIService
    private let configManager: AppConfigManager
    private let permissionManager: EnhancedPermissionManager
    private let logger = EnhancedLogManager.shared
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var workflowStartTime: Date?
    private var currentWorkflowId: UUID?
    private var stateTimeouts: [Timer] = []
    
    // MARK: - Configuration
    private let maxRecordingDuration: TimeInterval = 300.0  // 5分钟最大录音时长
    private let recordingTimeout: TimeInterval = 300.0      // 5分钟录音超时，与AudioService一致
    private let processingTimeout: TimeInterval = 60.0      // 1分钟处理超时
    private let overlayDisplayDuration: TimeInterval = 3.0
    
    // MARK: - Callbacks
    public var onWorkflowStarted: ((UUID) -> Void)?
    public var onWorkflowCompleted: ((WorkflowResult) -> Void)?
    public var onWorkflowFailed: ((WorkflowError) -> Void)?
    public var onStateChanged: ((WorkflowState, WorkflowState) -> Void)?
    
    public init(
        audioService: AudioService,
        openAIService: OpenAIService,
        configManager: AppConfigManager,
        permissionManager: EnhancedPermissionManager
    ) {
        self.audioService = audioService
        self.openAIService = openAIService
        self.configManager = configManager
        self.permissionManager = permissionManager
        
        logger.info("EnhancedWorkflowManager", "🔄 增强工作流管理器已初始化")
        setupStateObservation()
    }
    
    nonisolated func cleanup() {
        Task { @MainActor in
            cleanupTimeouts()
            logger.info("EnhancedWorkflowManager", "♻️  工作流管理器已清理")
        }
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - 主要工作流方法
    
    /// 开始完整的语音转AI优化文本工作流
    public func startVoiceToTextWorkflow() async -> WorkflowResult? {
        logger.startPerformanceTracking("complete_workflow")
        
        let workflowId = UUID()
        currentWorkflowId = workflowId
        workflowStartTime = Date()
        
        logger.userActionLog("🚀 开始完整工作流", metadata: ["workflow_id": workflowId.uuidString])
        onWorkflowStarted?(workflowId)
        
        do {
            // Step 1: Start Recording
            let audioData = try await performRecording()
            
            // Step 2: Process Audio
            let processedAudio = try await processAudio(audioData)
            
            // Step 3: Transcribe Audio
            let transcribedText = try await transcribeAudio(processedAudio)
            
            // Step 4: Optimize Text with LLM
            let optimizedText = try await optimizeText(transcribedText)
            
            // Step 5: Display Result
            try await displayResult(transcribedText, optimizedText)
            
            // Step 6: Complete Workflow
            let result = WorkflowResult(
                originalAudio: audioData,
                transcribedText: transcribedText,
                optimizedText: optimizedText,
                processingTime: Date().timeIntervalSince(workflowStartTime ?? Date()),
                metadata: ["workflow_id": workflowId.uuidString],
                timestamp: Date()
            )
            
            await completeWorkflow(result)
            return result
            
        } catch {
            let workflowError = error as? WorkflowError ?? WorkflowError.configurationError(error.localizedDescription)
            await failWorkflow(workflowError)
            return nil
        }
    }
    
    /// 取消当前工作流
    public func cancelWorkflow() async {
        logger.warning("EnhancedWorkflowManager", "⏹️  用户取消工作流")
        
        // Stop any ongoing operations
        if audioService.isRecording {
            _ = try? await audioService.stopRecording()
        }
        
        await transitionToState(.idle)
        cleanupTimeouts()
        currentWorkflowId = nil
    }
    
    // MARK: - 工作流步骤实现
    
    private func performRecording() async throws -> Data {
        logger.info("EnhancedWorkflowManager", "🎤 步骤1: 开始录音")
        await transitionToState(.recording)
        
        // Check permissions - 使用实时检查保持一致性
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard microphoneStatus == .authorized else {
            logger.error("EnhancedWorkflowManager", "录音权限检查失败: \(microphoneStatus.rawValue)")
            throw WorkflowError.permissionDenied("麦克风权限")
        }
        
        // 调试信息：检查缓存状态不同步问题
        let cachedStatus = permissionManager.permissionStates[.microphone]?.status.isGranted == true
        if !cachedStatus {
            logger.warning("EnhancedWorkflowManager", "🔄 权限状态已修复：实时检查=✅，缓存状态=❌（已忽略）")
        }
        
        // Start recording with timeout
        setupTimeout(for: .recording, duration: recordingTimeout)
        
        do {
            try await audioService.startRecording()
            
            // 稳定的录音等待逻辑
            logger.debug("EnhancedWorkflowManager", "⏰ 等待录音完成...")
            while audioService.isRecording && audioService.state == .recording {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                // 检查是否应该停止等待
                if audioService.state == .error {
                    logger.warning("EnhancedWorkflowManager", "录音状态错误，停止等待")
                    break
                }
            }
            
            // 智能获取录音数据
            let audioData: Data
            if audioService.isRecording {
                // 录音仍在进行，正常停止
                if let data = try await audioService.stopRecording() {
                    audioData = data
                } else {
                    throw WorkflowError.recordingFailed(NSError(domain: "RecordingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "录音处理失败"]))
                }
            } else {
                // 录音已停止，检查状态
                switch audioService.detailedState {
                case .cancelled:
                    logger.info("EnhancedWorkflowManager", "录音被取消")
                    throw CancellationError()
                case .error(let message):
                    logger.error("EnhancedWorkflowManager", "录音错误: \(message)")
                    throw WorkflowError.recordingFailed(NSError(domain: "RecordingError", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
                default:
                    // 尝试获取已录制的数据
                    if let data = try await audioService.stopRecording() {
                        audioData = data
                    } else {
                        throw WorkflowError.recordingFailed(NSError(domain: "RecordingError", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法获取录音数据，可能录音时间过短"]))
                    }
                }
            }
            
            logger.info("EnhancedWorkflowManager", "✅ 录音完成，数据大小: \(audioData.count) bytes")
            return audioData
        } catch {
            logger.error("EnhancedWorkflowManager", "❌ 录音失败: \(error.localizedDescription)")
            throw WorkflowError.recordingFailed(error)
        }
    }
    
    private func processAudio(_ audioData: Data) async throws -> Data {
        logger.info("EnhancedWorkflowManager", "🔊 步骤2: 处理音频数据")
        await transitionToState(.processingAudio)
        
        updateProgress(0.25, "处理音频格式...")
        
        // Simulate audio processing (format conversion, noise reduction, etc.)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        logger.debug("EnhancedWorkflowManager", "✅ 音频处理完成")
        return audioData // In real implementation, this would be processed audio
    }
    
    private func transcribeAudio(_ audioData: Data) async throws -> String {
        logger.info("EnhancedWorkflowManager", "📝 步骤3: 语音转文字")
        await transitionToState(.transcribing)
        
        updateProgress(0.50, "正在转录语音...")
        
        // Setup timeout for transcription
        setupTimeout(for: .transcribing, duration: processingTimeout)
        
        do {
            // Perform transcription using audio data directly
            let result = await openAIService.transcribeAudio(audioData)
            
            switch result {
            case .success(let transcriptionResult):
                logger.info("EnhancedWorkflowManager", "✅ 转录完成: \(transcriptionResult.text.prefix(50))...")
                return transcriptionResult.text
            case .failure(let error):
                logger.error("EnhancedWorkflowManager", "❌ 语音转文字失败: \(error.localizedDescription)")
                throw WorkflowError.transcriptionFailed(error)
            }
            
        } catch {
            logger.error("EnhancedWorkflowManager", "❌ 语音转文字失败: \(error.localizedDescription)")
            throw WorkflowError.transcriptionFailed(error)
        }
    }
    
    private func optimizeText(_ originalText: String) async throws -> String {
        logger.info("EnhancedWorkflowManager", "🤖 步骤4: AI优化文本")
        await transitionToState(.optimizing)
        
        updateProgress(0.75, "AI正在优化文本...")
        
        // Setup timeout for optimization
        setupTimeout(for: .optimizing, duration: processingTimeout)
        
        do {
            let result = await openAIService.optimizePrompt(originalText)
            
            switch result {
            case .success(let optimizationResult):
                logger.info("EnhancedWorkflowManager", "✅ AI优化完成: \(optimizationResult.optimizedText.prefix(50))...")
                return optimizationResult.optimizedText
            case .failure(let error):
                logger.error("EnhancedWorkflowManager", "❌ AI优化失败: \(error.localizedDescription)")
                throw WorkflowError.optimizationFailed(error)
            }
            
        } catch {
            logger.error("EnhancedWorkflowManager", "❌ AI优化失败: \(error.localizedDescription)")
            throw WorkflowError.optimizationFailed(error)
        }
    }
    
    private func displayResult(_ originalText: String, _ optimizedText: String) async throws {
        logger.info("EnhancedWorkflowManager", "📺 步骤5: 显示结果")
        await transitionToState(.displaying)
        
        updateProgress(0.90, "准备显示结果...")
        
        // Create and show result overlay
        overlayState = .result
        
        // Set timer to hide overlay after display duration
        let timer = Timer.scheduledTimer(withTimeInterval: overlayDisplayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.transitionToState(.completed)
            }
        }
        stateTimeouts.append(timer)
        
        logger.info("EnhancedWorkflowManager", "✅ 结果显示完成")
    }
    
    private func completeWorkflow(_ result: WorkflowResult) async {
        logger.endPerformanceTracking("complete_workflow")
        
        await transitionToState(.completed)
        updateProgress(1.0, "工作流完成")
        
        lastResult = result
        onWorkflowCompleted?(result)
        
        logger.info("EnhancedWorkflowManager", "🎉 工作流成功完成", metadata: [
            "total_time": result.processingTime,
            "transcribed_length": result.transcribedText.count,
            "optimized_length": result.optimizedText.count
        ])
        
        // Automatically return to idle after completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor in
                await self?.transitionToState(.idle)
            }
        }
    }
    
    private func failWorkflow(_ error: WorkflowError) async {
        logger.error("EnhancedWorkflowManager", "💥 工作流失败: \(error.localizedDescription)")
        
        await transitionToState(.error)
        onWorkflowFailed?(error)
        
        // Auto-return to idle after error
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor in
                await self?.transitionToState(.idle)
            }
        }
    }
    
    // MARK: - 状态管理
    
    private func transitionToState(_ newState: WorkflowState) async {
        let oldState = currentState
        
        guard oldState != newState else { return }
        
        logger.debug("EnhancedWorkflowManager", "🔄 状态转换: \(oldState.displayName) → \(newState.displayName)")
        
        // Clear any existing timeouts
        cleanupTimeouts()
        
        // Update state
        currentState = newState
        overlayVisible = newState.shouldShowOverlay
        overlayState = newState.overlayState
        isProcessing = [.recording, .processingAudio, .transcribing, .optimizing].contains(newState)
        
        // Update progress and description
        switch newState {
        case .idle:
            progress = 0.0
            currentStepDescription = ""
        case .recording:
            progress = 0.1
            currentStepDescription = "正在录音..."
        case .processingAudio:
            progress = 0.25
            currentStepDescription = "处理音频中..."
        case .transcribing:
            progress = 0.5
            currentStepDescription = "语音转文字中..."
        case .optimizing:
            progress = 0.75
            currentStepDescription = "AI优化中..."
        case .displaying:
            progress = 0.9
            currentStepDescription = "显示结果中..."
        case .completed:
            progress = 1.0
            currentStepDescription = "完成"
        case .error:
            currentStepDescription = "出现错误"
        }
        
        // Trigger state change callback on main thread
        Task { @MainActor in
            onStateChanged?(oldState, newState)
        }
        
        logger.debug("EnhancedWorkflowManager", "📊 状态更新完成 - 悬浮球显示: \(overlayVisible), 状态: \(overlayState)")
    }
    
    private func updateProgress(_ value: Double, _ description: String) {
        progress = value
        currentStepDescription = description
        logger.debug("EnhancedWorkflowManager", "📈 进度更新: \(Int(value * 100))% - \(description)")
    }
    
    // MARK: - 超时管理
    
    private func setupTimeout(for state: WorkflowState, duration: TimeInterval) {
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.currentState == state {
                    self?.logger.warning("EnhancedWorkflowManager", "⏰ 状态超时: \(state.displayName)")
                    await self?.failWorkflow(.timeoutError(state.displayName))
                }
            }
        }
        stateTimeouts.append(timer)
    }
    
    private func cleanupTimeouts() {
        stateTimeouts.forEach { $0.invalidate() }
        stateTimeouts.removeAll()
    }
    
    // MARK: - 状态观察
    
    private func setupStateObservation() {
        // Observe audio service state changes
        audioService.$isRecording
            .sink { [weak self] isRecording in
                Task { @MainActor [state = self?.currentState] in
                    if !isRecording && state == .recording {
                        self?.logger.debug("EnhancedWorkflowManager", "🎤 录音服务停止，准备处理音频")
                    }
                }
            }
            .store(in: &cancellables)
        
        logger.debug("EnhancedWorkflowManager", "👁️  状态观察器已设置")
    }
    
    // MARK: - 工具方法
    
    /// 检查工作流是否可以开始
    public func canStartWorkflow() -> (canStart: Bool, reason: String?) {
        // Check permissions - 使用实时检查避免状态不同步
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard microphoneStatus == .authorized else {
            logger.warning("EnhancedWorkflowManager", "麦克风权限检查失败: \(microphoneStatus.rawValue)")
            return (false, "需要麦克风权限")
        }
        
        // 同时检查缓存状态（用于调试）
        let cachedStatus = permissionManager.permissionStates[.microphone]?.status.isGranted == true
        if !cachedStatus {
            logger.warning("EnhancedWorkflowManager", "⚠️ 权限状态不同步：实时检查=✅，缓存状态=❌")
        }
        
        // Check configuration
        guard configManager.configurationValid else {
            return (false, "需要配置OpenAI API密钥")
        }
        
        // Check current state
        guard currentState == .idle else {
            return (false, "工作流正在进行中")
        }
        
        logger.debug("EnhancedWorkflowManager", "✅ 工作流准备就绪，麦克风权限: \(microphoneStatus.rawValue)")
        return (true, nil)
    }
    
    /// 获取当前工作流摘要
    public func getWorkflowSummary() -> String {
        let summary = """
        当前状态: \(currentState.displayName)
        进度: \(Int(progress * 100))%
        描述: \(currentStepDescription)
        悬浮球显示: \(overlayVisible ? "是" : "否")
        """
        return summary
    }
    
    /// 强制重置工作流状态
    public func forceReset() async {
        logger.warning("EnhancedWorkflowManager", "🔄 强制重置工作流状态")
        
        cleanupTimeouts()
        currentWorkflowId = nil
        workflowStartTime = nil
        
        if audioService.isRecording {
            _ = try? await audioService.stopRecording()
        }
        
        await transitionToState(.idle)
    }
}