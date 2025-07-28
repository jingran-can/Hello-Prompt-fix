//
//  EnhancedAPIValidator.swift
//  HelloPrompt
//
//  增强的API配置验证器 - 提供完整的OpenAI API验证和模型测试
//  包含连接测试、API密钥验证、base URL检查和模型能力测试
//

import Foundation
import SwiftUI
import OpenAI

// 使用 OpenAIService.swift 中定义的 APIValidationResult 和 APIValidationError

// MARK: - API验证器增强版
@MainActor
public final class EnhancedAPIValidator: ObservableObject {
    
    // MARK: - Published Properties
    @Published public var isValidating = false
    @Published public var validationProgress: Double = 0.0
    @Published public var currentValidationStep = ""
    @Published public var lastValidationResult: APIValidationResult?
    @Published public var supportedModels: [String] = []
    
    // MARK: - Private Properties
    private let logger = EnhancedLogManager.shared
    private var openAIClient: OpenAI?
    private let testTimeout: TimeInterval = 30.0
    
    // MARK: - Validation Steps
    private enum ValidationStep: String, CaseIterable {
        case apiKeyFormat = "验证API密钥格式"
        case baseURLFormat = "验证Base URL格式"
        case networkConnection = "测试网络连接"
        case authentication = "验证身份认证"
        case modelList = "获取支持的模型列表"
        case modelTesting = "测试模型能力"
        case quotaCheck = "检查使用配额"
        
        var weight: Double {
            switch self {
            case .apiKeyFormat: return 0.05
            case .baseURLFormat: return 0.05
            case .networkConnection: return 0.15
            case .authentication: return 0.20
            case .modelList: return 0.25
            case .modelTesting: return 0.20
            case .quotaCheck: return 0.10
            }
        }
    }
    
    // MARK: - Main Validation Method
    
    /// 完整的API配置验证
    public func validateAPIConfiguration(
        apiKey: String,
        baseURL: String,
        organizationId: String? = nil
    ) async -> APIValidationResult {
        
        logger.startPerformanceTracking("api_validation")
        logger.info("EnhancedAPIValidator", "🧪 开始API配置验证", metadata: [
            "base_url": baseURL,
            "has_org_id": organizationId != nil,
            "api_key_prefix": String(apiKey.prefix(8))
        ])
        
        isValidating = true
        validationProgress = 0.0
        defer { isValidating = false }
        
        let startTime = Date()
        var currentProgress: Double = 0.0
        var errors: [APIValidationError] = []
        var warnings: [String] = []
        
        // Step 1: API Key Format Validation
        currentValidationStep = ValidationStep.apiKeyFormat.rawValue
        logger.debug("EnhancedAPIValidator", "📝 Step 1: \(currentValidationStep)")
        
        if let error = validateAPIKeyFormat(apiKey) {
            errors.append(error)
            let result = APIValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                estimatedQuota: nil,
                responseTime: Date().timeIntervalSince(startTime)
            )
            logger.error("EnhancedAPIValidator", "❌ API密钥格式验证失败: \(error.localizedDescription)")
            return result
        }
        
        currentProgress += ValidationStep.apiKeyFormat.weight
        validationProgress = currentProgress
        
        // Step 2: Base URL Format Validation
        currentValidationStep = ValidationStep.baseURLFormat.rawValue
        logger.debug("EnhancedAPIValidator", "🌐 Step 2: \(currentValidationStep)")
        
        if let error = validateBaseURLFormat(baseURL) {
            errors.append(error)
            let result = APIValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                estimatedQuota: nil,
                responseTime: Date().timeIntervalSince(startTime)
            )
            logger.error("EnhancedAPIValidator", "❌ Base URL格式验证失败: \(error.localizedDescription)")
            return result
        }
        
        currentProgress += ValidationStep.baseURLFormat.weight
        validationProgress = currentProgress
        
        // Step 3: Initialize OpenAI Client
        openAIClient = createOpenAIClient(apiKey: apiKey, baseURL: baseURL, organizationId: organizationId)
        
        // Step 4: Network Connection Test
        currentValidationStep = ValidationStep.networkConnection.rawValue
        logger.debug("EnhancedAPIValidator", "🌐 Step 4: \(currentValidationStep)")
        
        do {
            _ = try await testNetworkConnection()
            currentProgress += ValidationStep.networkConnection.weight
            validationProgress = currentProgress
        } catch {
            errors.append(.networkUnavailable)
            let result = APIValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                estimatedQuota: nil,
                responseTime: Date().timeIntervalSince(startTime)
            )
            logger.error("EnhancedAPIValidator", "❌ 网络连接测试失败: \(error.localizedDescription)")
            return result
        }
        
        // Step 5: Authentication Test
        currentValidationStep = ValidationStep.authentication.rawValue
        logger.debug("EnhancedAPIValidator", "🔐 Step 5: \(currentValidationStep)")
        
        do {
            let models = try await testAuthentication()
            supportedModels = models
            currentProgress += ValidationStep.authentication.weight
            validationProgress = currentProgress
        } catch {
            errors.append(.authenticationFailed)
            let result = APIValidationResult(
                isValid: false,
                errors: errors,
                warnings: warnings,
                estimatedQuota: nil,
                responseTime: Date().timeIntervalSince(startTime)
            )
            logger.error("EnhancedAPIValidator", "❌ 身份验证失败: \(error.localizedDescription)")
            return result
        }
        
        // Step 6: Model Testing (Optional)
        currentValidationStep = ValidationStep.modelTesting.rawValue
        logger.debug("EnhancedAPIValidator", "🤖 Step 6: \(currentValidationStep)")
        
        do {
            let testResult = try await testModelCapabilities()
            if !testResult {
                warnings.append("某些模型测试失败，但基本功能可用")
            }
            currentProgress += ValidationStep.modelTesting.weight
            validationProgress = currentProgress
        } catch {
            warnings.append("模型能力测试失败: \(error.localizedDescription)")
            currentProgress += ValidationStep.modelTesting.weight
            validationProgress = currentProgress
        }
        
        // Final result
        validationProgress = 1.0
        let result = APIValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            estimatedQuota: nil,
            responseTime: Date().timeIntervalSince(startTime)
        )
        
        lastValidationResult = result
        logger.endPerformanceTracking("api_validation")
        logger.info("EnhancedAPIValidator", "✅ API配置验证完成", metadata: [
            "is_valid": result.isValid,
            "errors_count": errors.count,
            "warnings_count": warnings.count,
            "supported_models": supportedModels.count
        ])
        
        return result
    }
    
    // MARK: - Private Validation Methods
    
    private func validateAPIKeyFormat(_ apiKey: String) -> APIValidationError? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedKey.isEmpty {
            return .invalidAPIKey
        }
        
        if trimmedKey.count < 10 {
            return .invalidAPIKey
        }
        
        return nil
    }
    
    private func validateBaseURLFormat(_ baseURL: String) -> APIValidationError? {
        guard let url = URL(string: baseURL) else {
            return .invalidBaseURL
        }
        
        guard let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return .invalidBaseURL
        }
        
        return nil
    }
    
    private func createOpenAIClient(apiKey: String, baseURL: String, organizationId: String?) -> OpenAI {
        // Parse custom URL
        let customURL = URL(string: baseURL)
        let host = customURL?.host ?? "api.openai.com"
        let scheme = customURL?.scheme ?? "https"
        let orgId = (organizationId?.isEmpty == false) ? organizationId : nil
        
        let configuration = OpenAI.Configuration(
            token: apiKey,
            organizationIdentifier: orgId,
            host: host,
            scheme: scheme
        )
        
        return OpenAI(configuration: configuration)
    }
    
    private func testNetworkConnection() async throws -> Bool {
        guard let client = openAIClient else {
            throw APIValidationError.invalidAPIKey
        }
        
        // 简单的网络连接测试
        _ = try await client.models()
        return true
    }
    
    private func testAuthentication() async throws -> [String] {
        guard let client = openAIClient else {
            throw APIValidationError.authenticationFailed
        }
        
        let modelsResponse = try await client.models()
        return modelsResponse.data.map { $0.id }
    }
    
    private func testModelCapabilities() async throws -> Bool {
        guard let client = openAIClient else {
            throw APIValidationError.authenticationFailed
        }
        
        // 测试GPT模型
        let chatQuery = ChatQuery(
            messages: [ChatQuery.ChatCompletionMessageParam.user(.init(content: .string("test")))],
            model: "gpt-4o-mini"
        )
        
        _ = try await client.chats(query: chatQuery)
        return true
    }
}