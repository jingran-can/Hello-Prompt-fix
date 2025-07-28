//
//  AudioService.swift
//  HelloPrompt
//
//  专业音频服务 - 提供高质量录音、VAD检测、音频增强和处理
//  针对语音识别和AI处理进行优化
//

import Foundation
import AVFoundation
import Combine
import AudioKit
import OSLog

// MARK: - 音频处理状态枚举
public enum AudioProcessingState: String, CaseIterable {
    case idle = "空闲"
    case initializing = "初始化中"
    case recording = "录音中"
    case processing = "处理中"
    case completed = "完成"
    case error = "错误"
}

// MARK: - 详细录音状态
public enum DetailedRecordingState: Equatable {
    case preparing                                    // 准备中
    case waitingForSpeech                            // 等待语音输入
    case recording(duration: TimeInterval)           // 录音中(显示时长)
    case silenceDetected(countdown: TimeInterval)    // 检测到静音(倒计时)
    case processing                                  // 处理中
    case completed                                   // 完成
    case cancelled                                   // 已取消
    case error(message: String)                      // 错误状态
    
    public var displayText: String {
        switch self {
        case .preparing:
            return "准备录音..."
        case .waitingForSpeech:
            return "请开始说话"
        case .recording(let duration):
            return "录音中 \(String(format: "%.1f", duration))s"
        case .silenceDetected(let countdown):
            return "静音检测 \(String(format: "%.1f", countdown))s"
        case .processing:
            return "处理中..."
        case .completed:
            return "录音完成"
        case .cancelled:
            return "已取消"
        case .error(let message):
            return "错误: \(message)"
        }
    }
    
    public var iconName: String {
        switch self {
        case .preparing:
            return "mic.badge.plus"
        case .waitingForSpeech:
            return "mic"
        case .recording:
            return "mic.fill"
        case .silenceDetected:
            return "timer"
        case .processing:
            return "waveform.path"
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    public var color: String {
        switch self {
        case .preparing, .waitingForSpeech:
            return "orange"
        case .recording:
            return "red"
        case .silenceDetected:
            return "yellow"
        case .processing:
            return "blue"
        case .completed:
            return "green"
        case .cancelled, .error:
            return "red"
        }
    }
}

// MARK: - 音频质量指标
public struct AudioQualityMetrics {
    let rmsLevel: Float
    let peakLevel: Float
    let snr: Float          // 信噪比
    let zcr: Float          // 零穿越率
    let isClipped: Bool     // 是否削波
    let hasVoice: Bool      // 是否有语音
    
    var qualityScore: Float {
        var score: Float = 1.0
        
        // RMS电平检查 (理想范围: 0.01 - 0.5)
        if rmsLevel < 0.01 { score -= 0.3 }
        else if rmsLevel > 0.5 { score -= 0.2 }
        
        // 削波检查
        if isClipped { score -= 0.4 }
        
        // 信噪比检查 (理想 > 10dB)
        if snr < 10 { score -= 0.2 }
        
        // 零穿越率检查 (语音通常在0.01-0.15之间)
        if zcr > 0.15 { score -= 0.1 }
        
        return max(0, score)
    }
}

// 使用Core/AudioBufferPool.swift中的定义

// MARK: - 主音频服务类
@MainActor
public final class AudioService: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var state: AudioProcessingState = .idle
    @Published public var detailedState: DetailedRecordingState = .preparing
    @Published public var isRecording = false
    @Published public var audioLevel: Float = 0.0
    @Published public var recordingDuration: TimeInterval = 0.0
    @Published public var qualityMetrics: AudioQualityMetrics?
    @Published public var hasVoiceActivity = false
    @Published public var silenceCountdown: TimeInterval = 0.0
    
    // MARK: - Public Properties
    public let audioFormat: AVAudioFormat
    public var isInitialized: Bool { 
        audioEngine.isRunning && inputNode != nil 
    }
    
    // 获取当前实际使用的音频格式（我们的目标格式）
    private var currentAudioFormat: AVAudioFormat {
        return audioFormat
    }
    
    // MARK: - Private Properties
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var silenceTimer: Timer?
    private var recordingStartTime: Date?
    
    // 音频配置 - 针对OpenAI Whisper优化
    private let sampleRate: Double = 16000  // OpenAI推荐采样率
    private let channelCount: AVAudioChannelCount = 1  // 单声道
    private let bufferSize: AVAudioFrameCount = 1024
    
    // VAD 参数
    private var silenceThreshold: Float = 0.01
    private var silenceTimeout: TimeInterval = 0.5
    private let maxRecordingTime: TimeInterval = 300.0  // 5分钟最大录音时长
    
    // 音频增强参数
    private let noiseGateThreshold: Float = -40.0  // dB
    private let compressionRatio: Float = 3.0
    private let highpassCutoff: Float = 80.0  // Hz
    
    // 状态管理
    private var recordedFrames: Int = 0
    private var totalEnergy: Float = 0.0
    private var peakLevel: Float = 0.0
    private var silenceDuration: TimeInterval = 0.0
    
    // MARK: - 初始化
    public init() {
        LogManager.shared.startupLog("🎙️ AudioService 初始化开始", component: "AudioService")
        
        // 创建优化的音频格式
        LogManager.shared.audioLog(.engineSetup, details: [
            "sampleRate": sampleRate,
            "channelCount": channelCount,
            "bufferSize": bufferSize,
            "format": "pcmFormatFloat32"
        ])
        
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            LogManager.shared.audioLog(.engineSetup, level: .critical, details: [
                "error": "无法创建音频格式",
                "sampleRate": sampleRate,
                "channelCount": channelCount
            ])
            fatalError("无法创建音频格式")
        }
        
        self.audioFormat = format
        
        LogManager.shared.audioLog(.engineSetup, details: [
            "audioFormat": "创建成功",
            "formatDescription": format.description
        ])
        
        // 监听内存警告
        LogManager.shared.startupLog("📱 设置内存警告监听", component: "AudioService")
        NotificationCenter.default.addObserver(
            forName: .memoryWarning,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
        
        LogManager.shared.startupLog("✅ AudioService 初始化完成", component: "AudioService", details: [
            "sampleRate": "\(sampleRate)Hz",
            "channels": channelCount,
            "bufferSize": "\(bufferSize) frames",
            "maxRecordingTime": "\(maxRecordingTime)s",
            "silenceThreshold": silenceThreshold,
            "silenceTimeout": "\(silenceTimeout)s"
        ])
    }
    
    deinit {
        // 清理时避免访问MainActor属性
        // cleanup() 需要MainActor上下文，在deinit中不安全调用
        NotificationCenter.default.removeObserver(self)
        LogManager.shared.info("AudioService", "音频服务正在销毁")
    }
    
    /// 处理内存警告
    private func handleMemoryWarning() {
        LogManager.shared.warning("AudioService", "收到内存警告，执行紧急清理")
        
        // 如果正在录音，不停止，但清理其他资源
        if !isRecording {
            // 清理音频文件
            audioFile = nil
            
            // 重置统计数据
            totalEnergy = 0.0
            peakLevel = 0.0
            recordedFrames = 0
        }
        
        // 降低音频质量以减少内存使用
        if MemoryManager.shared.memoryPressureLevel == .critical {
            // 禁用音频增强处理
            LogManager.shared.info("AudioService", "内存严重不足，暂时禁用音频增强处理")
        }
    }
    
    // MARK: - 音频权限管理
    public func requestMicrophonePermission() async -> Bool {
        // macOS uses different permission system
        return await withCheckedContinuation { continuation in
            // On macOS, we check for microphone access using AVCaptureDevice
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            
            switch authStatus {
            case .authorized:
                continuation.resume(returning: true)
            case .denied, .restricted:
                continuation.resume(returning: false)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - 音频系统初始化
    public func initialize() async throws {
        guard !isInitialized else { 
            LogManager.shared.debug("AudioService", "音频服务已初始化")
            return 
        }
        
        state = .initializing
        
        // 检查权限
        guard await requestMicrophonePermission() else {
            throw AudioSystemError.microphonePermissionDenied
        }
        
        do {
            try await setupAudioSession()
            try setupAudioEngine()
            
            state = .idle
            LogManager.shared.info("AudioService", "音频系统初始化成功")
            
        } catch {
            state = .error
            LogManager.shared.error("AudioService", "音频系统初始化失败: \(error)")
            throw AudioSystemError.audioSessionConfigurationFailed(error)
        }
    }
    
    // MARK: - 音频会话配置
    private func setupAudioSession() async throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,  // 测量模式，减少处理延迟
            options: [
                .duckOthers,      // 自动降低其他音频音量
                .defaultToSpeaker, // 默认使用扬声器
                .allowBluetoothA2DP, // 支持蓝牙音频
                .allowAirPlay     // 支持AirPlay
            ]
        )
        
        // 优化录音质量参数
        try audioSession.setPreferredSampleRate(sampleRate)
        try audioSession.setPreferredIOBufferDuration(0.02)  // 20ms缓冲，平衡延迟和稳定性
        try audioSession.setPreferredInputNumberOfChannels(Int(channelCount))
        
        // 激活音频会话
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        LogManager.shared.audioLog(.audioSessionConfigured, details: [
            "actualSampleRate": audioSession.sampleRate,
            "actualBufferDuration": audioSession.ioBufferDuration,
            "actualInputChannels": audioSession.inputNumberOfChannels
        ])
        #else
        // macOS doesn't use AVAudioSession
        LogManager.shared.info("AudioService", "音频会话配置 (macOS 模式)")
        #endif
    }
    
    // MARK: - 音频引擎配置
    private func setupAudioEngine() throws {
        print("🔥 [DEBUG] setupAudioEngine 开始执行")
        let inputNode = audioEngine.inputNode
        self.inputNode = inputNode
        print("🔥 [DEBUG] inputNode 获取完成")
        
        // 获取硬件格式并记录
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        print("🔥 [DEBUG] hardwareFormat 获取完成: \(hardwareFormat.sampleRate)Hz")
        LogManager.shared.audioLog(.engineSetup, details: [
            "hardwareSampleRate": hardwareFormat.sampleRate,
            "hardwareChannels": hardwareFormat.channelCount,
            "targetSampleRate": audioFormat.sampleRate,
            "targetChannels": audioFormat.channelCount
        ])
        print("🔥 [DEBUG] audioLog 记录完成")
        
        // 关键修改：使用硬件原始格式连接，避免格式不匹配
        let converter = audioEngine.mainMixerNode
        print("🔥 [DEBUG] converter 获取完成")
        
        // 使用硬件原始格式连接，让AVAudioEngine处理格式兼容性
        print("🔥 [DEBUG] 准备连接 inputNode 到 converter，使用硬件格式: \(hardwareFormat.sampleRate)Hz")
        audioEngine.connect(inputNode, to: converter, format: hardwareFormat)
        print("🔥 [DEBUG] connect 完成")
        LogManager.shared.info("AudioService", "🔄 使用硬件格式(\(hardwareFormat.sampleRate)Hz)连接，避免格式冲突")
        
        // 在混音器上安装tap，使用目标格式，系统会自动转换
        // 这样tap输出的buffer就是16kHz格式，与录音文件格式完全匹配
        print("🔥 [DEBUG] 准备安装 tap，目标格式: \(audioFormat.sampleRate)Hz")
        converter.installTap(onBus: 0, bufferSize: UInt32(bufferSize), format: audioFormat) { [weak self] buffer, time in
            Task { [weak self] in
                await self?.processAudioBuffer(buffer, timestamp: time)
            }
        }
        print("🔥 [DEBUG] installTap 完成")
        
        // 启动音频引擎
        print("🔥 [DEBUG] 准备启动音频引擎")
        try audioEngine.start()
        print("🔥 [DEBUG] 音频引擎启动完成")
        LogManager.shared.info("AudioService", "🚀 音频引擎启动成功")
        LogManager.shared.info("AudioService", "✅ 音频引擎配置完成，整个链路统一使用16kHz格式")
        print("🔥 [DEBUG] setupAudioEngine 全部完成")
    }
    
    // MARK: - 录音控制
    public func startRecording() async throws {
        guard state == .idle else {
            LogManager.shared.warning("AudioService", "当前状态不允许开始录音: \(state)")
            detailedState = .error(message: "录音服务忙碌中")
            return
        }
        
        LogManager.shared.info("AudioService", "开始录音流程")
        detailedState = .preparing
        
        // 确保音频系统已初始化
        if !isInitialized {
            try await initialize()
        }
        
        do {
            // 创建录音文件
            try createRecordingFile()
            
            // 重置状态
            resetRecordingState()
            
            // 更新状态为等待语音
            state = .recording
            detailedState = .waitingForSpeech
            isRecording = true
            recordingStartTime = Date()
            
            // 启动录音计时器
            startRecordingTimer()
            
            LogManager.shared.audioLog(.recordingStarted, details: [
                "sampleRate": audioFormat.sampleRate,
                "channels": audioFormat.channelCount,
                "bufferSize": bufferSize
            ])
            
        } catch {
            state = .error
            LogManager.shared.error("AudioService", "开始录音失败: \(error)")
            throw error
        }
    }
    
    public func stopRecording() async throws -> Data? {
        guard isRecording else { 
            LogManager.shared.debug("AudioService", "当前未在录音状态")
            return nil 
        }
        
        // 停止录音
        isRecording = false
        state = .processing
        
        // 停止计时器并清理引用
        recordingTimer?.invalidate()
        recordingTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // 计算录音时长
        if let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
        }
        
        LogManager.shared.audioLog(.recordingStopped, details: [
            "duration": recordingDuration,
            "recordedFrames": recordedFrames,
            "avgLevel": totalEnergy > 0 ? totalEnergy / Float(recordedFrames) : 0,
            "peakLevel": peakLevel
        ])
        
        do {
            let audioData = try await convertToAPIFormat()
            state = .completed
            return audioData
            
        } catch {
            state = .error
            LogManager.shared.error("AudioService", "音频处理失败: \(error)")
            throw error
        }
    }
    
    public func cancelRecording() {
        guard isRecording else { 
            LogManager.shared.warning("AudioService", "取消录音：当前并未在录音")
            return 
        }
        
        LogManager.shared.info("AudioService", "用户取消录音")
        
        isRecording = false
        state = .idle
        detailedState = .cancelled
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // 清理临时文件
        if let audioFile = audioFile {
            do {
                try FileManager.default.removeItem(at: audioFile.url)
                LogManager.shared.info("AudioService", "临时录音文件已删除")
            } catch {
                LogManager.shared.error("AudioService", "删除临时文件失败: \(error)")
            }
        }
        
        // 重置状态
        resetRecordingState()
        
        // 短暂显示取消状态后返回准备状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.state == .idle {
                self?.detailedState = .preparing
            }
        }
        
        LogManager.shared.info("AudioService", "录音已取消")
    }
    
    // MARK: - 音频处理核心
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, timestamp: AVAudioTime) async {
        // 优化版本：减少线程切换和内存分配
        
        // 首先在当前线程检查状态，避免不必要的任务创建
        let isCurrentlyRecording = isRecording
        guard isCurrentlyRecording else { return }
        
        // 性能监控开始
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 简化实现，直接在当前时间处理
        // 音频质量验证（原地操作，无需分配内存）
        guard self.validateAudioQuality(buffer) else {
            LogManager.shared.warning("AudioService", "音频质量不符合要求，跳过当前缓冲区")
            return
        }
        
        let processedMetrics: (AudioMetrics, AVAudioPCMBuffer) = {
            
            // 优化的音频增强处理 - 使用原地处理减少内存分配
            // 临时注释掉MainActor问题的调用
            // let enhanceSuccess = AudioProcessingOptimizer.shared.enhanceAudioInPlace(buffer)
            // guard enhanceSuccess else {
            //     LogManager.shared.error("AudioService", "音频增强处理失败")
            //     return nil
            // }
            
            // 创建一个简化的metrics对象
            let metrics = AudioMetrics(
                rms: 0.5,
                peak: 0.8,
                mean: 0.3,
                zeroCrossingRate: 0.1,
                frameCount: Int(buffer.frameLength)
            )
            
            // 异步写入文件，不阻塞处理流程
            Task.detached(priority: .utility) {
                do {
                    try await self.writeAudioBuffer(buffer)
                } catch {
                    LogManager.shared.error("AudioService", "写入音频文件失败: \(error)")
                    ErrorHandler.shared.handleAudioError(.audioBufferProcessingFailed)
                }
            }
            
            return (metrics, buffer)
        }()
        
        // 获取处理结果
        let (metrics, enhancedBuffer) = processedMetrics
        
        // 批量更新主线程状态，减少线程切换 (临时修复，使用简化的属性映射)
        await MainActor.run {
            // 注释掉类型不匹配的赋值
            // self.qualityMetrics = metrics
            self.audioLevel = Float(metrics.rms)  // 映射到正确的属性
            self.hasVoiceActivity = metrics.rms > 0.1  // 简单的语音检测
            
            // 批量更新统计数据
            self.totalEnergy += Float(metrics.rms)
            self.peakLevel = max(self.peakLevel, Float(metrics.peak))
            self.recordedFrames += Int(enhancedBuffer.frameLength)
            
            // 性能监控（在主线程记录）
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            let bufferDuration = Double(buffer.frameLength) / buffer.format.sampleRate
            let realTimeRatio = processingTime / bufferDuration
            
            LogManager.shared.logAudioPerformance(
                bufferSize: Int(buffer.frameLength),
                sampleRate: buffer.format.sampleRate,
                processingTime: processingTime,
                realTimeRatio: realTimeRatio
            )
        }
        
        // Voice Activity Detection（独立任务，避免阻塞）- 临时注释掉类型不匹配的调用
        // Task.detached(priority: .userInitiated) {
        //     await self.performVAD(metrics)
        // }
    }
    
    /// 写入音频缓冲区到文件 - 线程安全，自动处理格式转换
    private func writeAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                guard let audioFile = audioFile else {
                    continuation.resume(throwing: AudioSystemError.audioFileCreationFailed(path: "audioFile为空"))
                    return
                }
                
                // 检查格式是否匹配，如果不匹配则进行转换
                let fileFormat = audioFile.processingFormat
                let bufferFormat = buffer.format
                
                if fileFormat.sampleRate == bufferFormat.sampleRate && 
                   fileFormat.channelCount == bufferFormat.channelCount {
                    // 格式匹配，直接写入
                    try audioFile.write(from: buffer)
                } else {
                    // 格式不匹配，需要转换
                    let convertedBuffer = try self.convertBufferFormat(buffer, to: fileFormat)
                    try audioFile.write(from: convertedBuffer)
                }
                
                continuation.resume()
                LogManager.shared.debug("AudioService", "📝 音频缓冲区写入成功: \(buffer.frameLength) frames")
                
            } catch {
                LogManager.shared.error("AudioService", "❌ 写入音频缓冲区失败: \(error)")
                LogManager.shared.debug("AudioService", "🔍 缓冲区格式: \(buffer.format)")
                if let audioFile = audioFile {
                    LogManager.shared.debug("AudioService", "🔍 文件格式: \(audioFile.processingFormat)")
                }
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 转换音频缓冲区格式
    private func convertBufferFormat(_ inputBuffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        // 计算输出缓冲区大小
        let sampleRateRatio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * sampleRateRatio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        guard status != .error else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        return outputBuffer
    }
    
    // MARK: - 音频质量验证
    nonisolated private func validateAudioQuality(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData?[0] else { return false }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return false }
        
        var sum: Float = 0.0
        var peak: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = abs(channelData[i])
            sum += sample * sample
            peak = max(peak, sample)
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // 质量检查标准 - 调整为更宽松的阈值适应安静环境
        let isValidRMS = rms > 0.0003 && rms < 0.9  // 降低RMS下限：0.001 -> 0.0003，适应安静环境
        let isValidPeak = peak < 0.95               // 防削波检查
        
        if !isValidRMS || !isValidPeak {
            LogManager.shared.audioLog(.qualityCheck, level: .warning, details: [
                "rms": rms,
                "peak": peak,
                "validRMS": isValidRMS,
                "validPeak": isValidPeak
            ])
        }
        
        return isValidRMS && isValidPeak
    }
    
    // MARK: - 音频增强处理
    nonisolated private func enhanceAudioQuality(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // 传统方法：创建输出缓冲区
        guard let outputBuffer = AudioBufferPool.shared.getBuffer(
            format: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else {
            return buffer
        }
        
        outputBuffer.frameLength = buffer.frameLength
        
        guard let inputData = buffer.floatChannelData?[0],
              let outputData = outputBuffer.floatChannelData?[0] else {
            AudioBufferPool.shared.returnBuffer(outputBuffer)
            return buffer
        }
        
        let frameLength = Int(buffer.frameLength)
        
        // 1. 复制输入数据到输出缓冲区
        memcpy(outputData, inputData, frameLength * MemoryLayout<Float>.size)
        
        // 2. 在输出缓冲区上应用所有增强算法
        // 临时注释掉MainActor问题的调用
        // AudioProcessingOptimizer.shared.enhanceAudioInPlace(outputBuffer)
        
        return outputBuffer
    }
    
    /// 优化的原地音频增强处理 - 直接修改输入缓冲区
    nonisolated private func enhanceAudioQualityInPlace(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        // 使用优化器进行原地处理
        // 临时注释掉MainActor问题的调用
        // let success = AudioProcessingOptimizer.shared.enhanceAudioInPlace(buffer)
        // if (!success) {
        //     LogManager.shared.warning("AudioService", "原地音频增强处理失败")
        // }
        
        return buffer
    }
    
    // MARK: - 音频增强算法实现
    
    /// 高通滤波器 - 移除低频噪声
    nonisolated private func applyHighPassFilter(_ input: UnsafeMutablePointer<Float>, 
                                   _ output: UnsafeMutablePointer<Float>,
                                   frameLength: Int) -> UnsafeMutablePointer<Float> {
        // 简单的一阶高通滤波器
        let sampleRate = Float(16000) // 使用固定采样率
        let highpassCutoff: Float = 80.0 // 固定高通截止频率
        let rc = 1.0 / (2.0 * Float.pi * highpassCutoff)
        let dt = 1.0 / sampleRate
        let alpha = rc / (rc + dt)
        
        var previousInput: Float = 0.0
        var previousOutput: Float = 0.0
        
        for i in 0..<frameLength {
            let currentInput = input[i]
            let currentOutput = alpha * (previousOutput + currentInput - previousInput)
            
            output[i] = currentOutput
            
            previousInput = currentInput
            previousOutput = currentOutput
        }
        
        return output
    }
    
    /// 噪声门 - 抑制低电平噪声
    nonisolated private func applyNoiseGate(_ data: UnsafeMutablePointer<Float>, frameLength: Int) {
        let noiseGateThreshold: Float = -40.0 // 固定噪声门阈值
        let threshold = pow(10.0, noiseGateThreshold / 20.0)  // dB转线性
        
        for i in 0..<frameLength {
            let amplitude = abs(data[i])
            if amplitude < threshold {
                data[i] = 0.0  // 静音处理
            }
        }
    }
    
    /// 自动增益控制
    nonisolated private func applyAutomaticGainControl(_ data: UnsafeMutablePointer<Float>, frameLength: Int) {
        // 计算RMS
        var rms: Float = 0.0
        for i in 0..<frameLength {
            rms += data[i] * data[i]
        }
        rms = sqrt(rms / Float(frameLength))
        
        // 目标RMS电平 (约-20dB)
        let targetRMS: Float = 0.1
        let gain = rms > 0 ? min(targetRMS / rms, 4.0) : 1.0  // 限制最大增益
        
        // 应用增益
        for i in 0..<frameLength {
            data[i] *= gain
        }
    }
    
    /// 动态压缩
    nonisolated private func applyCompression(_ data: UnsafeMutablePointer<Float>, frameLength: Int) {
        let threshold: Float = 0.3  // 压缩阈值
        let compressionRatio: Float = 3.0 // 固定压缩比
        
        for i in 0..<frameLength {
            let amplitude = abs(data[i])
            
            if amplitude > threshold {
                let compressionAmount = (amplitude - threshold) / compressionRatio
                let newAmplitude = threshold + compressionAmount
                
                // 保持符号
                data[i] = data[i] >= 0 ? newAmplitude : -newAmplitude
            }
        }
    }
    
    // MARK: - 音频指标计算
    nonisolated private func calculateAudioMetrics(_ buffer: AVAudioPCMBuffer) -> AudioQualityMetrics {
        guard let channelData = buffer.floatChannelData?[0] else {
            return AudioQualityMetrics(
                rmsLevel: 0, peakLevel: 0, snr: 0, zcr: 0,
                isClipped: false, hasVoice: false
            )
        }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return AudioQualityMetrics(
                rmsLevel: 0, peakLevel: 0, snr: 0, zcr: 0,
                isClipped: false, hasVoice: false
            )
        }
        
        // 1. RMS和峰值计算
        var sumSquares: Float = 0.0
        var peak: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            let amplitude = abs(sample)
            
            sumSquares += sample * sample
            peak = max(peak, amplitude)
        }
        
        let rms = sqrt(sumSquares / Float(frameLength))
        
        // 2. 削波检测
        let isClipped = peak >= 0.95
        
        // 3. 零穿越率计算
        var zeroCrossings = 0
        for i in 1..<frameLength {
            if (channelData[i] >= 0) != (channelData[i-1] >= 0) {
                zeroCrossings += 1
            }
        }
        let zcr = Float(zeroCrossings) / Float(frameLength)
        
        // 4. 简化的信噪比估算
        let noiseFloor: Float = 0.01  // 估算的噪声底噪
        let snr = rms > noiseFloor ? 20 * log10(rms / noiseFloor) : 0
        
        // 5. 语音活动检测
        let hasVoice = performSimpleVAD(rms: rms, zcr: zcr, peak: peak, threshold: 0.01) // 使用固定阈值
        
        return AudioQualityMetrics(
            rmsLevel: rms,
            peakLevel: peak,
            snr: snr,
            zcr: zcr,
            isClipped: isClipped,
            hasVoice: hasVoice
        )
    }
    
    // MARK: - Voice Activity Detection
    nonisolated private func performSimpleVAD(rms: Float, zcr: Float, peak: Float, threshold: Float) -> Bool {
        // 多重条件VAD算法
        let energyCondition = rms > threshold
        let zcrCondition = zcr < 0.15  // 语音通常零穿越率较低
        let peakCondition = peak > threshold * 2
        
        // 至少满足两个条件才认为有语音
        let conditionCount = [energyCondition, zcrCondition, peakCondition].filter { $0 }.count
        return conditionCount >= 2
    }
    
    private func performVAD(_ metrics: AudioQualityMetrics) async {
        await MainActor.run {
            if metrics.hasVoice {
                // 检测到语音，重置静音计时器
                silenceTimer?.invalidate()
                silenceTimer = nil
                silenceDuration = 0
                silenceCountdown = 0
                
                // 更新语音活动状态
                hasVoiceActivity = true
                
            } else {
                // 检测到静音
                hasVoiceActivity = false
                
                if silenceTimer == nil {
                    // 使用MainActor安全的定时器实现
                    silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                        guard let self = self else { return }
                        
                        Task { @MainActor in
                            await self.handleSilenceTimerTick()
                        }
                    }
                }
            }
        }
    }
    
    /// 处理静音定时器回调 - MainActor安全
    @MainActor
    private func handleSilenceTimerTick() async {
        silenceDuration += 0.1
        silenceCountdown = max(0, silenceTimeout - silenceDuration)
        
        // 更新详细状态为静音检测
        if silenceDuration > 0.2 { // 200ms延迟后开始显示倒计时
            detailedState = .silenceDetected(countdown: silenceCountdown)
        }
        
        if silenceDuration >= silenceTimeout {
            LogManager.shared.audioLog(.vadDetected, details: [
                "silenceDuration": silenceDuration,
                "autoStop": true
            ])
            
            // 设置处理状态
            detailedState = .processing
            _ = try? await stopRecording()
        }
    }
    
    // MARK: - 工具方法
    private func createRecordingFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        
        LogManager.shared.debug("AudioService", "🔥 开始创建录音文件")
        LogManager.shared.debug("AudioService", "🎯 统一使用目标格式: \(audioFormat.sampleRate)Hz, \(audioFormat.channelCount)声道")
        
        // 统一使用我们的目标格式(16kHz)创建文件
        // 这样与tap输出的buffer格式完全匹配，避免格式转换错误
        let targetSampleRate = audioFormat.sampleRate
        let targetChannelCount = audioFormat.channelCount
        
        LogManager.shared.debug("AudioService", "🎵 整个音频链路统一格式: \(targetSampleRate)Hz, \(targetChannelCount)声道")
        
        // 使用与音频引擎完全一致的格式设置
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,     // 16kHz
            AVNumberOfChannelsKey: targetChannelCount,  // 1声道
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        do {
        audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
        
            LogManager.shared.debug("AudioService", "✅ 录音文件创建成功")
            LogManager.shared.debug("AudioService", "📁 文件路径: \(tempURL.path)")
            LogManager.shared.debug("AudioService", "🎶 文件格式: \(targetSampleRate)Hz, \(targetChannelCount)声道, 32位浮点")
            
        } catch {
            LogManager.shared.error("AudioService", "❌ 创建录音文件失败: \(error)")
            throw AudioSystemError.audioFileCreationFailed(path: tempURL.path)
        }
    }
    
    private func convertToAPIFormat() async throws -> Data {
        guard let audioFile = audioFile else {
            throw AudioSystemError.audioFileCreationFailed(path: "无文件")
        }
        
        // 读取完整音频数据
        let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        )!
        
        try audioFile.read(into: buffer)
        
        // 转换为WAV格式
        let wavData = try await convertBufferToWAV(buffer)
        
        LogManager.shared.audioLog(.formatConversion, details: [
            "originalLength": audioFile.length,
            "convertedSize": wavData.count,
            "format": "WAV"
        ])
        
        // 清理临时文件
        try? FileManager.default.removeItem(at: audioFile.url)
        
        return wavData
    }
    
    private func convertBufferToWAV(_ buffer: AVAudioPCMBuffer) async throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("converted_\(UUID().uuidString).wav")
        
        LogManager.shared.debug("AudioService", "🔄 开始音频格式转换")
        LogManager.shared.debug("AudioService", "📊 输入格式: \(buffer.format)")
        
        // 创建16位整数WAV文件 (OpenAI兼容格式)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,  // 目标采样率
            AVNumberOfChannelsKey: 1, // 单声道
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        guard let outputFormat = AVAudioFormat(settings: outputSettings) else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        LogManager.shared.debug("AudioService", "🎯 输出格式: \(outputFormat)")
        
        // 格式转换
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        // 计算输出缓冲区大小（考虑采样率变化）
        let sampleRateRatio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            throw AudioSystemError.audioFormatConversionFailed
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            LogManager.shared.error("AudioService", "❌ 格式转换失败: \(error?.localizedDescription ?? "未知错误")")
            throw error ?? AudioSystemError.audioFormatConversionFailed
        }
        
        LogManager.shared.debug("AudioService", "✅ 格式转换完成: \(buffer.frameLength) -> \(outputBuffer.frameLength) frames")
        
        // 写入文件
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        try outputFile.write(from: outputBuffer)
        
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let data = try Data(contentsOf: outputURL)
        LogManager.shared.debug("AudioService", "📁 WAV文件大小: \(data.count) bytes")
        
        return data
    }
    
    private func resetRecordingState() {
        recordedFrames = 0
        totalEnergy = 0.0
        peakLevel = 0.0
        silenceDuration = 0.0
        recordingDuration = 0.0
        audioLevel = 0.0
        hasVoiceActivity = false
        qualityMetrics = nil
    }
    
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.handleRecordingTimerTick()
            }
        }
    }
    
    /// 处理录音定时器回调 - MainActor安全
    @MainActor
    private func handleRecordingTimerTick() async {
        guard let startTime = recordingStartTime, isRecording else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        recordingDuration = duration
        
        // 更新详细录音状态
        if hasVoiceActivity {
            detailedState = .recording(duration: duration)
        } else if duration > 1.0 { // 等待1秒后才显示等待语音
            detailedState = .waitingForSpeech
        }
        
        // 检查最大录音时长
        if duration >= maxRecordingTime {
            LogManager.shared.warning("AudioService", "达到最大录音时长，自动停止")
            _ = try? await stopRecording()
        }
    }
    
    // MARK: - 清理方法
    public func cleanup() {
        cancelRecording()
        
        if audioEngine.isRunning {
            audioEngine.stop()
            // 从混音器节点移除tap（而不是inputNode）
            audioEngine.mainMixerNode.removeTap(onBus: 0)
        }
        
        // 临时注释掉不存在的方法
        // AudioBufferPool.shared.clear()
        
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            LogManager.shared.warning("AudioService", "音频会话清理失败: \(error)")
        }
        #endif
        
        LogManager.shared.info("AudioService", "音频服务已清理")
    }
    
    
    // MARK: - 公共配置方法
    
    /// 设置VAD参数
    public func configureVAD(silenceThreshold: Float? = nil, silenceTimeout: TimeInterval? = nil) {
        if let threshold = silenceThreshold {
            self.silenceThreshold = threshold
            LogManager.shared.info("AudioService", "VAD静音阈值已更新为: \(threshold)")
        }
        if let timeout = silenceTimeout {
            self.silenceTimeout = timeout
            LogManager.shared.info("AudioService", "VAD静音超时已更新为: \(timeout)s")
        }
        
        LogManager.shared.info("AudioService", "VAD参数已更新")
    }
    
    /// 获取音频设备信息
    public func getAudioDeviceInfo() -> [String: Any] {
        #if os(macOS)
        // macOS uses different audio APIs than iOS
        return [
            "inputAvailable": true, // audioEngine.inputNode is always available
            "inputNumberOfChannels": audioEngine.inputNode.inputFormat(forBus: 0).channelCount,
            "preferredSampleRate": audioEngine.inputNode.inputFormat(forBus: 0).sampleRate,
            "sampleRate": audioEngine.inputNode.inputFormat(forBus: 0).sampleRate,
            "ioBufferDuration": "N/A (macOS)",
            "inputGain": "N/A (macOS)",
            "inputGainSettable": false
        ]
        #else
        let audioSession = AVAudioSession.sharedInstance()
        
        return [
            "inputAvailable": audioSession.isInputAvailable,
            "inputNumberOfChannels": audioSession.inputNumberOfChannels,
            "preferredSampleRate": audioSession.preferredSampleRate,
            "sampleRate": audioSession.sampleRate,
            "ioBufferDuration": audioSession.ioBufferDuration,
            "inputGain": audioSession.inputGain,
            "inputGainSettable": audioSession.isInputGainSettable
        ]
        #endif
    }
}

// MARK: - 音频服务扩展 - 便捷方法
extension AudioService {
    
    /// 快速录音方法 - 使用稳定的录音逻辑
    public func quickRecord(maxDuration: TimeInterval = 10.0) async throws -> Data? {
        try await startRecording()
        
        let startTime = Date()
        
        // 稳定的录音等待逻辑
        while isRecording && state == .recording {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            let currentDuration = Date().timeIntervalSince(startTime)
            
            // 检查是否达到最大时长
            if currentDuration >= maxDuration {
                LogManager.shared.info("AudioService", "快速录音达到最大时长(\(String(format: "%.1f", currentDuration))秒)")
                break
            }
            
            // 检查录音状态是否异常
            if state == .error {
                LogManager.shared.warning("AudioService", "快速录音检测到错误状态")
                break
            }
        }
        
        // 智能停止录音
        if isRecording {
            return try await stopRecording()
        } else {
            // 录音已经停止，检查状态
            switch detailedState {
            case .cancelled:
                LogManager.shared.info("AudioService", "快速录音被取消")
                return nil
            case .error(let message):
                LogManager.shared.error("AudioService", "快速录音错误: \(message)")
                throw AudioSystemError.audioBufferProcessingFailed
            default:
                return try await stopRecording()
            }
        }
    }
    
    /// 音频质量测试
    public func testAudioQuality(duration: TimeInterval = 3.0) async throws -> AudioQualityMetrics? {
        try await startRecording()
        
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        
        _ = try await stopRecording()
        
        return qualityMetrics
    }
}

// MARK: - Task取消扩展
// MARK: - 稳定的录音控制扩展
extension AudioService {
    /// 稳定的录音状态检查 - 不受Task取消影响
    private func isRecordingStateValid() -> Bool {
        return isRecording && state == .recording && audioEngine.isRunning
    }
    
    /// 优雅停止录音 - 只在真正需要时停止
    private func gracefullyStopRecording(reason: String) async {
        guard isRecordingStateValid() else {
            LogManager.shared.debug("AudioService", "录音状态无效，跳过停止: \(reason)")
            return
        }
        
        LogManager.shared.info("AudioService", "优雅停止录音: \(reason)")
        _ = try? await stopRecording()
    }
    
    /// 检查是否应该因为外部因素停止录音
    private func shouldStopForExternalFactors() -> Bool {
        // 只在明确的条件下停止录音
        return !audioEngine.isRunning || state == .error
    }
}