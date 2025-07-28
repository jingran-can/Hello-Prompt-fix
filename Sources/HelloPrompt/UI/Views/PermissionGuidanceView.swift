//
//  PermissionGuidanceView.swift
//  HelloPrompt
//
//  权限引导视图 - 提供清晰的权限说明和步骤指导
//  改善用户理解和授权体验
//

import SwiftUI
import AppKit

// MARK: - 权限引导步骤
public enum PermissionGuidanceStep: Int, CaseIterable {
    case welcome = 0
    case microphoneExplanation = 1
    case microphonePermission = 2
    case accessibilityExplanation = 3
    case accessibilityPermission = 4
    case completion = 5
    
    var title: String {
        switch self {
        case .welcome:
            return "欢迎使用 Hello Prompt v2"
        case .microphoneExplanation:
            return "麦克风权限说明"
        case .microphonePermission:
            return "授权麦克风权限"
        case .accessibilityExplanation:
            return "辅助功能权限说明"
        case .accessibilityPermission:
            return "授权辅助功能权限（可选）"
        case .completion:
            return "设置完成"
        }
    }
    
    var isOptional: Bool {
        switch self {
        case .accessibilityExplanation, .accessibilityPermission:
            return true
        default:
            return false
        }
    }
}

// MARK: - 权限引导视图
public struct PermissionGuidanceView: View {
    
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var currentStep: PermissionGuidanceStep = .welcome
    @State private var isAnimating = false
    
    let onCompleted: () -> Void
    let onSkipped: () -> Void
    
    public init(
        onCompleted: @escaping () -> Void,
        onSkipped: @escaping () -> Void
    ) {
        self.onCompleted = onCompleted
        self.onSkipped = onSkipped
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 进度指示器
            progressIndicator
            
            Divider()
            
            // 主要内容区域
            ScrollView {
                VStack(spacing: 30) {
                    stepContent
                    
                    actionButtons
                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 600, height: 700)
        .onAppear {
            Task {
                await permissionManager.checkAllPermissions(reason: "权限引导")
                updateCurrentStep()
            }
        }
        .onChange(of: permissionManager.allPermissionsGranted) { _ in
            updateCurrentStep()
        }
    }
    
    // MARK: - 进度指示器
    private var progressIndicator: some View {
        HStack(spacing: 12) {
            ForEach(PermissionGuidanceStep.allCases, id: \.self) { step in
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 12, height: 12)
                    .scaleEffect(currentStep == step ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                
                if step != PermissionGuidanceStep.allCases.last {
                    Rectangle()
                        .fill(stepColor(for: step).opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
    }
    
    private func stepColor(for step: PermissionGuidanceStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return .gray.opacity(0.3)
        }
    }
    
    // MARK: - 步骤内容
    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: 25) {
            // 步骤标题
            HStack {
                Text(currentStep.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if currentStep.isOptional {
                    Text("可选")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            
            // 步骤详细内容
            switch currentStep {
            case .welcome:
                welcomeContent
            case .microphoneExplanation:
                microphoneExplanationContent
            case .microphonePermission:
                microphonePermissionContent
            case .accessibilityExplanation:
                accessibilityExplanationContent
            case .accessibilityPermission:
                accessibilityPermissionContent
            case .completion:
                completionContent
            }
        }
    }
    
    // MARK: - 各步骤的具体内容
    
    private var welcomeContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Hello Prompt v2 是一个AI驱动的语音转提示词工具")
                .font(.title2)
                .multilineTextAlignment(.center)
            
            Text("""
            为了正常工作，应用需要获取一些系统权限。
            我们将逐步引导您完成权限设置过程。
            """)
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
    }
    
    private var microphoneExplanationContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("为什么需要麦克风权限？")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "waveform",
                    title: "语音录制",
                    description: "录制您的语音输入"
                )
                
                FeatureRow(
                    icon: "brain.head.profile",
                    title: "AI 处理",
                    description: "将语音转换为优化的提示词"
                )
                
                FeatureRow(
                    icon: "lock.shield",
                    title: "隐私保护",
                    description: "录音仅在本地处理，不会存储"
                )
            }
            
            Text("⚠️ 没有麦克风权限，应用将无法工作")
                .font(.caption)
                .foregroundColor(.red)
                .padding(.top)
        }
    }
    
    private var microphonePermissionContent: some View {
        VStack(spacing: 20) {
            let micStatus = permissionManager.getPermissionStatus(.microphone)
            
            PermissionStatusCard(
                type: .microphone,
                status: micStatus,
                onRequest: {
                    Task {
                        await permissionManager.requestPermission(.microphone)
                    }
                }
            )
            
            if micStatus == .granted {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("麦克风权限已授权！")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(), value: micStatus)
            }
        }
    }
    
    private var accessibilityExplanationContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "accessibility")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("辅助功能权限（可选但推荐）")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "keyboard",
                    title: "全局快捷键",
                    description: "在任何应用中快速启动录音",
                    isOptional: true
                )
                
                FeatureRow(
                    icon: "text.insert",
                    title: "智能文本插入",
                    description: "自动将结果插入到活动应用",
                    isOptional: true
                )
                
                FeatureRow(
                    icon: "apps.iphone",
                    title: "应用检测",
                    description: "根据当前应用优化提示词",
                    isOptional: true
                )
            }
            
            Text("💡 没有此权限时，您可以手动复制粘贴结果")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top)
        }
    }
    
    private var accessibilityPermissionContent: some View {
        VStack(spacing: 20) {
            let accStatus = permissionManager.getPermissionStatus(.accessibility)
            
            PermissionStatusCard(
                type: .accessibility,
                status: accStatus,
                onRequest: {
                    Task {
                        await permissionManager.requestPermission(.accessibility)
                    }
                }
            )
            
            if accStatus == .granted {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("辅助功能权限已授权！")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(), value: accStatus)
            }
        }
    }
    
    private var completionContent: some View {
        VStack(spacing: 25) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("设置完成！")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.green)
            
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("麦克风权限已授权")
                    Spacer()
                }
                
                HStack {
                    Image(systemName: permissionManager.hasPermission(.accessibility) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(permissionManager.hasPermission(.accessibility) ? .green : .secondary)
                    Text("辅助功能权限")
                    Spacer()
                    if !permissionManager.hasPermission(.accessibility) {
                        Text("未授权")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("""
            Hello Prompt v2 已准备就绪！
            
            使用 Control+U 快捷键开始录音，或在应用界面中点击录音按钮。
            """)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 操作按钮
    private var actionButtons: some View {
        HStack(spacing: 20) {
            if currentStep != .welcome && currentStep != .completion {
                Button("上一步") {
                    previousStep()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep.isOptional {
                Button("跳过") {
                    nextStep()
                }
                .buttonStyle(.bordered)
            }
            
            Button(nextButtonTitle) {
                if currentStep == .completion {
                    onCompleted()
                } else {
                    nextStep()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceedToNext)
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .completion:
            return "开始使用"
        case .microphonePermission, .accessibilityPermission:
            return "继续"
        default:
            return "下一步"
        }
    }
    
    private var canProceedToNext: Bool {
        switch currentStep {
        case .microphonePermission:
            return permissionManager.hasPermission(.microphone)
        default:
            return true
        }
    }
    
    // MARK: - 步骤控制
    private func nextStep() {
        if let nextStep = PermissionGuidanceStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = nextStep
            }
        }
    }
    
    private func previousStep() {
        if let prevStep = PermissionGuidanceStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = prevStep
            }
        }
    }
    
    private func updateCurrentStep() {
        // 自动推进到适当的步骤
        if permissionManager.hasPermission(.microphone) && currentStep.rawValue <= PermissionGuidanceStep.microphonePermission.rawValue {
            currentStep = .accessibilityExplanation
        }
        
        if permissionManager.allPermissionsGranted && currentStep != .completion {
            currentStep = .completion
        }
    }
}

// MARK: - 功能行组件
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let isOptional: Bool
    
    init(icon: String, title: String, description: String, isOptional: Bool = false) {
        self.icon = icon
        self.title = title
        self.description = description
        self.isOptional = isOptional
    }
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isOptional ? .orange : .blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    if isOptional {
                        Text("可选")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

// MARK: - 权限状态卡片
private struct PermissionStatusCard: View {
    let type: PermissionType
    let status: PermissionStatus
    let onRequest: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: type.icon)
                    .font(.title)
                    .foregroundColor(statusColor)
                
                VStack(alignment: .leading) {
                    Text(type.rawValue)
                        .font(.headline)
                    
                    Text(status.statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 20, height: 20)
            }
            
            if status != .granted {
                VStack(spacing: 10) {
                    Text(instructionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("授权 \(type.rawValue)") {
                        onRequest()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                )
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .restricted: return .red
        case .unknown: return .gray
        }
    }
    
    private var instructionText: String {
        switch type {
        case .microphone:
            return "点击下方按钮，在弹出的系统对话框中选择\"允许\""
        case .accessibility:
            return "点击下方按钮打开系统设置，将 Hello Prompt v2 添加到辅助功能列表"
        case .notification:
            return "点击下方按钮，在弹出的系统对话框中选择\"允许\""
        }
    }
}

// MARK: - 预览
#if DEBUG
struct PermissionGuidanceView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionGuidanceView(
            onCompleted: {
                print("Guidance completed")
            },
            onSkipped: {
                print("Guidance skipped")
            }
        )
        .previewDisplayName("权限引导界面")
    }
}
#endif