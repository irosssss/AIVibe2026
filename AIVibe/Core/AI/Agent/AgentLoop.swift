// AIVibe/Core/AI/Agent/AgentLoop.swift
// Stage 3: Core Agentic Loop — главный цикл агента.
// Blueprint §4: run_aivibe_agent() с Triplex Fallback, auto-compaction, planning/goal modes.

import Foundation
import Logging

// MARK: - User Request

/// Входной запрос пользователя для агента.
public struct UserRequest: Sendable {
    /// Тип входных данных.
    public let inputType: InputType
    /// Текстовый промпт пользователя.
    public let message: String
    /// Бюджетный диапазон (мин/макс в рублях), nil если не указан.
    public let budgetRange: (min: Int, max: Int)?
    /// Предпочитаемый стиль (nil = автоопределение).
    public let preferredStyle: String?
    /// ID комнаты (если есть скан).
    public let roomId: String?
    /// ID сессии.
    public let sessionId: String?

    public enum InputType: String, Sendable {
        case textPrompt
        case lidarScan
        case photo
    }

    public init(
        inputType: InputType = .textPrompt,
        message: String,
        budgetRange: (min: Int, max: Int)? = nil,
        preferredStyle: String? = nil,
        roomId: String? = nil,
        sessionId: String? = nil
    ) {
        self.inputType = inputType
        self.message = message
        self.budgetRange = budgetRange
        self.preferredStyle = preferredStyle
        self.roomId = roomId
        self.sessionId = sessionId
    }

    /// Извлекает бюджетный максимум (или nil).
    public var budgetMax: Int? { budgetRange?.max }

    /// Извлекает бюджетный минимум (или nil).
    public var budgetMin: Int? { budgetRange?.min }
}

// MARK: - Agent Loop Result

/// Результат работы агента.
public enum AgentLoopResult: Sendable {
    /// Успешное завершение с финальным ответом.
    case completed(finalAnswer: String, session: AgentSession)
    /// Остановлен — превышен бюджет шагов.
    case stepBudgetReached(lastAnswer: String?, session: AgentSession)
    /// Остановлен — нет финального ответа и нет tool calls.
    case noAction(session: AgentSession)
    /// Приостановлен — требуется одобрение пользователя.
    case approvalRequired(action: String, riskClass: String, session: AgentSession)
    /// Ошибка.
    case error(Error, session: AgentSession)
}

// MARK: - Model Output

/// Вывод AI-модели (парсится из ответа провайдера).
public struct ModelOutput: Sendable {
    /// Финальный ответ (если модель завершила).
    public let finalAnswer: String?
    /// Tool calls, которые модель запросила выполнить.
    public let toolCalls: [ToolCallRequest]
    /// Обновление плана (если модель хочет планировать).
    public let planUpdate: DesignPlan?
    /// Обновление todo.
    public let todoUpdates: [TodoItem]?
    /// Raw текст ответа.
    public let rawText: String

    public var hasFinalAnswer: Bool { finalAnswer != nil }
    public var hasToolCalls: Bool { !toolCalls.isEmpty }

    public init(
        finalAnswer: String? = nil,
        toolCalls: [ToolCallRequest] = [],
        planUpdate: DesignPlan? = nil,
        todoUpdates: [TodoItem]? = nil,
        rawText: String = ""
    ) {
        self.finalAnswer = finalAnswer
        self.toolCalls = toolCalls
        self.planUpdate = planUpdate
        self.todoUpdates = todoUpdates
        self.rawText = rawText
    }
}

// MARK: - Agent Loop

/// Главный цикл агента — BluePrint §4.
///
/// ```
/// func run_aivibe_agent(task, session):
///   for step in range(session.maxSteps):
///     context = context_builder.build(session)
///     if context.needs_compaction():
///       session = compactor.compact_and_rehydrate(session)
///       context = context_builder.build(session)
///     model_output = model.generate(context, tools, provider)
///     if model_output.final_answer: return finalize(...)
///     if not model_output.tool_calls: return stop("no_final_answer_or_tool_call")
///     for call in scheduler.order(model_output.tool_calls):
///       tool = registry.get(call.name)
///       if tool is None: error_result("unknown_tool")
///       args = tool.validate(call.arguments)
///       decision = permissions.evaluate(tool, args, session)
///       if decision.type == "deny": denied_result
///       elif decision.type == "approval_required": pause_for_approval
///       elif decision.type == "sandbox": sandbox.execute(tool, args)
///       else: result = tool.execute(args)
///       result = result_limiter.enforce(result, max_chars=8000)
///       session.add_tool_result(call.id, result)
///   return stop("step_budget_reached")
/// ```
public actor AgentLoop {

    // MARK: - Dependencies

    /// Сборщик контекста.
    private let contextBuilder: ContextBuilder

    /// Реестр инструментов.
    private let toolRegistry: ToolRegistry

    /// Роутер AI-провайдеров (Triplex Fallback).
    private let providerRouter: AIProviderRouter

    /// Индекс скиллов.
    private let skillIndex: SkillIndexSnapshot

    /// Permission engine.
    private let permissionEngine: PermissionEngine

    /// Планировщик tool calls.
    private let toolScheduler: ToolScheduler

    /// Ограничитель результатов.
    private let resultLimiter: ResultLimiter

    /// Compactor (сжатие сессии).
    private let compactor: SessionCompactor

    /// Логгер.
    private let logger = Logger(label: "ai.agent-loop")

    // MARK: - Init

    public init(
        contextBuilder: ContextBuilder = ContextBuilder(),
        toolRegistry: ToolRegistry,
        providerRouter: AIProviderRouter,
        skillIndex: SkillIndexSnapshot = .standard,
        permissionEngine: PermissionEngine = PermissionEngine(),
        toolScheduler: ToolScheduler = ToolScheduler(),
        resultLimiter: ResultLimiter = ResultLimiter(),
        compactor: SessionCompactor = SessionCompactor()
    ) {
        self.contextBuilder = contextBuilder
        self.toolRegistry = toolRegistry
        self.providerRouter = providerRouter
        self.skillIndex = skillIndex
        self.permissionEngine = permissionEngine
        self.toolScheduler = toolScheduler
        self.resultLimiter = resultLimiter
        self.compactor = compactor
    }

    // MARK: - Main Loop

    /// Запускает главный цикл агента.
    ///
    /// - Parameters:
    ///   - request: Запрос пользователя.
    ///   - session: Сессия (новая или существующая).
    /// - Returns: Результат работы агента.
    // swiftlint:disable:next function_body_length
    public func run(
        request: UserRequest,
        session: AgentSession
    ) async -> AgentLoopResult {

        let maxSteps = session.maxSteps

        logger.info("🚀 Агент запущен: \"\(request.message.prefix(80))...\" [\(request.inputType.rawValue)]")

        // Шаг 0: Добавляем запрос пользователя в сессию
        await session.addEvent(SessionEvent(
            type: .userMessage,
            data: .text(request.message),
            step: 0
        ))

        // Главный цикл
        for step in 1...maxSteps {

            logger.info("🔄 Шаг \(step)/\(maxSteps)")

            // 1. Сборка контекста
            var context = await contextBuilder.build(
                session: session,
                toolRegistry: toolRegistry,
                skillIndex: skillIndex
            )

            // 2. Auto-compaction при 80% заполнении (Blueprint §9)
            if contextBuilder.needsCompaction(context: context) {
                logger.warning("📦 Контекст заполнен (\(context.totalChars) символов) → compaction")
                await compactor.compactAndRehydrate(session: session)
                context = await contextBuilder.build(
                    session: session,
                    toolRegistry: toolRegistry,
                    skillIndex: skillIndex
                )
            }

            // 3. Отправка запроса AI-модели (Triplex Fallback)
            let modelOutput: ModelOutput
            do {
                modelOutput = try await generateModelOutput(context: context)
            } catch {
                logger.error("❌ Все провайдеры исчерпаны: \(error.localizedDescription)")
                await session.addEvent(SessionEvent(
                    type: .error,
                    data: .text(error.localizedDescription),
                    step: step
                ))
                return .error(error, session: session)
            }

            // Сохраняем model output в сессию
            await session.addEvent(SessionEvent(
                type: .modelOutput,
                data: .json(modelOutput.rawText),
                step: step
            ))

            // 4. Проверяем финальный ответ
            if let finalAnswer = modelOutput.finalAnswer {
                logger.info("✅ Финальный ответ получен на шаге \(step)")
                return .completed(finalAnswer: finalAnswer, session: session)
            }

            // 5. Проверяем tool calls
            if modelOutput.toolCalls.isEmpty {
                logger.warning("⚠️ Нет финального ответа и нет tool calls — остановка")
                return .noAction(session: session)
            }

            // 6. Обрабатываем tool calls
            let orderedCalls = toolScheduler.order(modelOutput.toolCalls)

            for group in orderedCalls {
            for call in group {
                // Execute через ToolRegistry
                let result = await toolRegistry.execute(call: call)

                // Сохраняем результат в сессию
                await session.addEvent(SessionEvent(
                    type: .toolResult,
                    data: .json(result.data),
                    step: step
                ))

                // Проверяем на approval required
                if result.status == .approvalRequired {
                    let actionText = result.data.isEmpty ? "неизвестное действие" : result.data
                    let riskClass = result.toolName
                    logger.info("🔐 Требуется одобрение: \(actionText)")
                    return .approvalRequired(
                        action: actionText,
                        riskClass: riskClass,
                        session: session
                    )
                }

                // Проверяем на deny
                if result.status == .denied {
                    let reason = result.data.isEmpty ? "нет причины" : result.data
                    logger.warning("🚫 Инструмент \(call.name) отклонён: \(reason)")
                }
            }
            }

            // 7. Обрабатываем plan update (если модель прислала)
            if let planUpdate = modelOutput.planUpdate {
                await session.setPlan(planUpdate)
            }

            // 8. Обрабатываем todo updates
            if let todos = modelOutput.todoUpdates {
                for todo in todos {
                    await session.addTodo(todo)
                }
            }
        }

        // Бюджет шагов исчерпан
        logger.warning("⏰ Бюджет шагов исчерпан (\(maxSteps))")
        return .stepBudgetReached(lastAnswer: nil, session: session)
    }

    // MARK: - Private: Model Output Generation

    /// Генерирует ModelOutput через Triplex Fallback (YandexGPT → GigaChat → CoreML).
    ///
    /// BluePrint §4: Provider fallback в цикле:
    /// 1. YandexGPT 5 Pro (timeout 30s)
    /// 2. GigaChat Ultra (timeout 30s)
    /// 3. Core ML on-device (если оба облачных недоступны)
    /// Circuit Breaker: 3 ошибки → skip 5 мин → health check каждые 60с
    private func generateModelOutput(context: AgentContext) async throws -> ModelOutput {
        let promptString = context.toPromptString()

        let aiPrompt = AIPrompt(
            messages: [
                ChatMessage(role: .system, content: promptString),
                ChatMessage(role: .user, content: "Проанализируй контекст и выполни следующие действия. Если у тебя есть финальный ответ — верни его. Если нужны данные — вызови инструменты (tool calls) в JSON формате.")
            ],
            temperature: 0.7,
            maxTokens: 2048
        )

        let response = try await providerRouter.complete(prompt: aiPrompt)

        // Парсим ответ модели → ModelOutput
        return parseModelOutput(response.text)
    }

    /// Парсит текстовый ответ AI-модели в структурированный ModelOutput.
    ///
    /// Поддерживает форматы:
    /// - JSON с `final_answer`, `tool_calls`, `plan_update`, `todo_updates`
    /// - Markdown с ```json блоками
    /// - Plain text (если нет JSON → финальный ответ)
    private func parseModelOutput(_ raw: String) -> ModelOutput {

        // Попытка найти JSON блок
        let jsonStr: String?
        if let match = raw.range(of: "```json\n"), let end = raw.range(of: "\n```", range: match.upperBound..<raw.endIndex) {
            jsonStr = String(raw[match.upperBound..<end.lowerBound])
        } else if raw.hasPrefix("{") && raw.hasSuffix("}") {
            jsonStr = raw
        } else if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            jsonStr = String(raw[start...end])
        } else {
            jsonStr = nil
        }

        // Если нет JSON → весь ответ как final answer
        guard let jsonStr = jsonStr,
              let jsonData = jsonStr.data(using: .utf8) else {
            return ModelOutput(finalAnswer: raw, rawText: raw)
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

            // final_answer
            let finalAnswer = obj?["final_answer"] as? String

            // tool_calls
            var toolCalls: [ToolCallRequest] = []
            if let callsArray = obj?["tool_calls"] as? [[String: Any]] {
                for callDict in callsArray {
                    let name = callDict["name"] as? String ?? ""
                    let args = callDict["arguments"] as? [String: Any] ?? [:]
                    let callIdStr = callDict["id"] as? String ?? UUID().uuidString
                    let callId = UUID(uuidString: callIdStr) ?? UUID()
                    toolCalls.append(ToolCallRequest(
                        id: callId,
                        name: name,
                        arguments: args
                    ))
                }
            }

            // plan_update
            var planUpdate: DesignPlan?
            if let planDict = obj?["plan_update"] as? [String: Any] {
                planUpdate = DesignPlan(
                    objective: planDict["objective"] as? String ?? "",
                    scope: planDict["scope"] as? String ?? "",
                    assumptions: planDict["assumptions"] as? [String] ?? [],
                    risks: planDict["risks"] as? [String] ?? [],
                    steps: planDict["steps"] as? [String] ?? [],
                    toolsRequired: planDict["tools_required"] as? [String] ?? [],
                    approvalPoints: planDict["approval_points"] as? [String] ?? [],
                    validationMethod: planDict["validation_method"] as? String ?? "",
                    rollbackRecovery: planDict["rollback_recovery"] as? String ?? "",
                    doneCondition: planDict["done_condition"] as? String ?? ""
                )
            }

            // todo_updates
            var todoUpdates: [TodoItem]?
            if let todoArray = obj?["todo_updates"] as? [[String: Any]] {
                todoUpdates = todoArray.map { todoDict in
                    TodoItem(
                        title: todoDict["title"] as? String ?? "",
                        completed: todoDict["completed"] as? Bool ?? false
                    )
                }
            }

            return ModelOutput(
                finalAnswer: finalAnswer,
                toolCalls: toolCalls,
                planUpdate: planUpdate,
                todoUpdates: todoUpdates,
                rawText: raw
            )

        } catch {
            logger.warning("⚠️ Ошибка парсинга JSON ответа: \(error.localizedDescription)")
            return ModelOutput(finalAnswer: raw, rawText: raw)
        }
    }

    // MARK: - Goal-like Loop (Blueprint §8)

    /// Запускает goal-like loop для long-running задач.
    ///
    /// Blueprint §8: Активируется при явном запросе «спроектируй всю комнату с нуля».
    /// Objective + checkpoints + progress tracking + stop rules.
    public func runGoalLoop(
        objective: String,
        checkpoints: [String],
        budget: Int = 12,
        session: AgentSession
    ) async -> AgentLoopResult {

        let goal = GoalState(
            objective: objective,
            budget: budget,
            checkpoints: checkpoints,
            currentCheckpoint: checkpoints.first,
            doneCondition: "Все чекпоинты (\(checkpoints.count)) выполнены: \(checkpoints.joined(separator: ", "))"
        )

        await session.setGoalState(goal)

        logger.info("🎯 Goal-like loop запущен: \"\(objective)\" (\(checkpoints.count) чекпоинтов)")

        // Создаём план для goal
        let plan = DesignPlan(
            objective: objective,
            steps: checkpoints,
            toolsRequired: ["analyze_room_scan", "recommend_style", "search_marketplace_furniture", "generate_arrangement_plan", "draft_shopping_list"],
            doneCondition: goal.doneCondition
        )
        await session.setPlan(plan)

        // Запускаем обычный цикл, но с goal tracking
        for step in 1...budget {
            let currentCheckpoint = await session.goalState?.currentCheckpoint

            if let cp = currentCheckpoint {
                let request = UserRequest(
                    message: "Выполни чекпоинт: «\(cp)». Общая цель: \(objective)",
                    sessionId: session.id
                )
                let result = await run(request: request, session: session)

                switch result {
                case .completed:
                    // Отмечаем чекпоинт выполненным
                    await session.updateGoalProgress(checkpoint: cp, completed: true)

                    // Проверяем done condition
                    if await session.goalState?.isDone ?? false {
                        logger.info("🎉 Goal достигнут!")
                        return result
                    }

                    // Переходим к следующему чекпоинту
                    if let nextCp = checkpoints.dropFirst(step).first {
                        await session.setGoalState(GoalState(
                            objective: objective,
                            budget: budget,
                            checkpoints: checkpoints,
                            completedCheckpoints: await session.goalState?.completedCheckpoints ?? [],
                            currentCheckpoint: nextCp,
                            doneCondition: goal.doneCondition
                        ))
                    } else {
                        return result  // Все чекпоинты пройдены
                    }

                case .approvalRequired, .stepBudgetReached, .noAction, .error:
                    return result
                }
            } else {
                return .error(
                    NSError(domain: "AgentLoop", code: -1, userInfo: [NSLocalizedDescriptionKey: "Нет текущего чекпоинта"]),
                    session: session
                )
            }
        }

        return .stepBudgetReached(
            lastAnswer: "Бюджет шагов (\(budget)) исчерпан. Прогресс: \(await session.goalState?.progress ?? 0 * 100)%",
            session: session
        )
    }

    // MARK: - Planning Mode (Blueprint §7)

    /// Активирует planning mode.
    ///
    /// BluePrint §7: Planning mode когда:
    /// - Комната большая (>30м²) или сложной формы (>6 углов)
    /// - Бюджет > 500 000 ₽
    /// - Пользователь не указал стиль
    /// - Пользователь просит "посоветуй что делать" без конкретики
    /// - Обнаружены архитектурные ограничения
    ///
    /// Во время планирования:
    /// - Allowed: analyze_room_scan, search_marketplace_furniture, recommend_style, read_resource, update_plan
    /// - Blocked: generate_arrangement_plan, draft_shopping_list, confirm_purchase_order, share_project_publicly
    public func shouldActivatePlanningMode(request: UserRequest, roomAnalysis: PlanningRoomAnalysis?) -> Bool {
        // Большой бюджет
        if let budgetMax = request.budgetMax, budgetMax > 500_000 {
            return true
        }

        // Не указан стиль
        if request.preferredStyle == nil && request.inputType == .lidarScan {
            return true
        }

        // Большая комната
        if let room = roomAnalysis, room.roomDimensions.floorAreaM2 > 30 {
            return true
        }

        // Сложная форма (6+ объектов с углами)
        if let room = roomAnalysis, room.objects.count > 6 {
            return true
        }

        // Пользователь без конкретики
        let vaguePhrases = ["посоветуй", "что делать", "с чего начать", "как лучше", "не знаю"]
        let lowerMessage = request.message.lowercased()
        if vaguePhrases.contains(where: { lowerMessage.contains($0) }) {
            return true
        }

        return false
    }
}

// MARK: - Session Compactor

/// Сжимает сессию при превышении контекстного окна (BluePrint §9).
///
/// ## Compaction summary format (Blueprint §9):
/// ```
/// Current objective:     Дизайн гостиной 18м², скандинавский стиль, бюджет 350 000 ₽
/// User constraints:      Белые стены, не менять пол, нужен большой диван
/// Active plan:           plan_id=pl_01, step 3/5 — подбор мебели
/// ...
/// ```
public actor SessionCompactor {

    private let logger = Logger(label: "ai.session-compactor")

    public init() {}

    /// Выполняет compaction и rehydration сессии.
    ///
    /// 1. Создаёт compaction summary (сжатая сводка текущего состояния)
    /// 2. Удаляет старые tool results (оставляет только последние 3)
    /// 3. Перезаписывает контекст — сводка + последние события
    public func compactAndRehydrate(session: AgentSession) async {
        let allEvents = await session.allEvents
        let charsBefore = Double(allEvents.map { eventCount in
            eventCount.data.asText?.count ?? 0
        }.reduce(0, +))

        // 1. Создаём compaction summary
        let summary = await buildCompactionSummary(session: session, charsBefore: charsBefore)

        // 2. Добавляем сводку в историю
        await session.addCompactionSummary(summary)

        // 3. Оставляем только последние 3 tool result события + сводка как контекст
        // (Tool results сдвигаются в compaction_summaries, новые результаты продолжают добавляться)

        let charsAfter = Double(summary.objectiveAtCompaction?.count ?? 0)

        logger.info("📦 Compaction: \(Int(charsBefore)) → \(Int(charsAfter)) символов (экономия \(Int(charsBefore - charsAfter)))")
    }

    /// Строит compaction summary (Blueprint §9).
    private func buildCompactionSummary(session: AgentSession, charsBefore: Double) async -> CompactionSummary {
        let plan = await session.activePlan
        let goal = await session.goalState

        let objectiveText = plan?.objective ?? goal?.objective ?? "не указана"
        let planStepText: String = {
            if let plan = plan {
                return "step \(plan.currentStepIndex + 1)/\(plan.totalSteps) — \(plan.currentStep ?? "завершён")"
            }
            return "нет активного плана"
        }()

        let allEvents = await session.allEvents
        let toolEvents = allEvents.filter { $0.type == .toolResult || $0.type == .toolCall }

        return CompactionSummary(
            triggerReason: "80% контекстного окна заполнено",
            charsBefore: charsBefore,
            charsAfter: Double(objectiveText.count + toolEvents.count * 100),
            objectiveAtCompaction: objectiveText,
            planStepAtCompaction: planStepText,
            eventsRemoved: max(0, toolEvents.count - 3)  // Оставляем 3 последних tool events
        )
    }
}

// MARK: - PlanningRoomAnalysis placeholder (для shouldActivatePlanningMode)

/// Упрощённый анализ комнаты — используется в планировании (Blueprint §7).
/// Полная версия: RoomAnalysis в AnalyzeRoomScanTool.
public struct PlanningRoomAnalysis: Sendable {
    public let roomDimensions: RoomDimensionsAnalysis
    public let objects: [DetectedObjectAnalysis]
    public let floorAreaM2: Double

    public init(roomDimensions: RoomDimensionsAnalysis, objects: [DetectedObjectAnalysis], floorAreaM2: Double) {
        self.roomDimensions = roomDimensions
        self.objects = objects
        self.floorAreaM2 = floorAreaM2
    }
}

public struct RoomDimensionsAnalysis: Sendable {
    public let widthM: Double
    public let depthM: Double
    public let heightM: Double

    public var floorAreaM2: Double { widthM * depthM }

    public init(widthM: Double, depthM: Double, heightM: Double) {
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
    }
}

public struct DetectedObjectAnalysis: Sendable {
    public let type: String
    public let materialHint: String?

    public init(type: String, materialHint: String? = nil) {
        self.type = type
        self.materialHint = materialHint
    }
}
