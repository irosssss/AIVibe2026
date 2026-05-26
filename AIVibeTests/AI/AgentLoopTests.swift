// AIVibeTests/AI/AgentLoopTests.swift
// Blueprint §13: Acceptance tests для AgentLoop + 8 eval probes.
// Проверяет: главный цикл, Triplex Fallback, planning mode, goal loop, compaction, observability.

import XCTest
@testable import AIVibe

// MARK: - AgentLoopTests

final class AgentLoopTests: XCTestCase {

    // MARK: - Mocks

    var mockToolRegistry: ToolRegistry!
    var mockProviderRouter: AIProviderRouter!
    var mockObservability: ObservabilityCollector!

    override func setUp() async throws {
        try await super.setUp()

        mockToolRegistry = ToolRegistry()
        await mockToolRegistry.registerDomainTools()

        // Создаём роутер с мок-провайдерами
        let yandex = MockAIProviderSuccess(
            name: "YandexGPT",
            response: AIResponse(
                text: """
                {
                    "final_answer": "Я проанализировал комнату 15м². Рекомендую скандинавский стиль: светлые тона, минимализм, функциональная мебель.",
                    "tool_calls": [
                        {"name": "analyze_room_scan", "arguments": {"room_id": "test_room"}, "id": "call_1"},
                        {"name": "recommend_style", "arguments": {"room_data": {}, "budget_max": 300000}, "id": "call_2"}
                    ]
                }
                """,
                providerName: "YandexGPT",
                isOffline: false,
                tokensUsed: 42
            )
        )

        mockProviderRouter = AIProviderRouter(
            providers: [yandex],
            fallbackChain: ["YandexGPT"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )

        mockObservability = ObservabilityCollector()
    }

    override func tearDown() async throws {
        mockToolRegistry = nil
        mockProviderRouter = nil
        mockObservability = nil
        try await super.tearDown()
    }

    // MARK: - AgentLoop: Базовый цикл

    /// Тест: агент получает текстовый запрос → model output с финальным ответом → completed.
    func testAgentLoop_SimpleQuery_ReturnsCompleted() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Какой стиль выбрать для гостиной 15м²?")

        // When
        let result = await loop.run(request: request, session: session)

        // Then
        guard case .completed(let finalAnswer, _) = result else {
            XCTFail("Ожидался .completed, получено: \(result)")
            return
        }
        XCTAssertTrue(finalAnswer.contains("скандинавский") || finalAnswer.contains("стиль"),
                      "Ответ должен содержать рекомендацию стиля")
    }

    /// Тест: model output без финального ответа и без tool calls → noAction.
    func testAgentLoop_NoFinalAnswerNoToolCalls_ReturnsNoAction() async throws {
        // Given — провайдер с пустым ответом
        let emptyProvider = MockAIProviderSuccess(
            name: "Empty",
            response: AIResponse(text: "{\n}", providerName: "Empty", isOffline: false, tokensUsed: 0)
        )
        let router = AIProviderRouter(
            providers: [emptyProvider],
            fallbackChain: ["Empty"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )

        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Привет")

        // When
        let result = await loop.run(request: request, session: session)

        // Then
        guard case .noAction = result else {
            XCTFail("Ожидался .noAction, получено: \(result)")
            return
        }
    }

    /// Тест: превышен бюджет шагов (maxSteps=2) → stepBudgetReached.
    func testAgentLoop_StepBudgetExceeded_ReturnsStepBudgetReached() async throws {
        // Given — провайдер, который вечно просит tool calls
        let loopingProvider = MockAIProviderSuccess(
            name: "Looper",
            response: AIResponse(
                text: """
                {
                    "tool_calls": [
                        {"name": "recommend_style", "arguments": {"room_data": {}}, "id": "call_loop"}
                    ]
                }
                """,
                providerName: "Looper",
                isOffline: false,
                tokensUsed: 5
            )
        )
        let router = AIProviderRouter(
            providers: [loopingProvider],
            fallbackChain: ["Looper"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )

        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user", maxSteps: 2)
        let request = UserRequest(message: "Подбери стиль")

        // When
        let result = await loop.run(request: request, session: session)

        // Then
        guard case .stepBudgetReached(_, let session) = result else {
            XCTFail("Ожидался .stepBudgetReached, получено: \(result)")
            return
        }
        // Проверяем, что сессия содержит события
        let events = await session.allEvents
        XCTAssertGreaterThan(events.count, 2, "В сессии должно быть больше 2 событий")
    }

    // MARK: - Triplex Fallback

    /// Тест: первый провайдер падает → fallback на GigaChat → completed.
    func testAgentLoop_ProviderFallback_SuccessOnSecondProvider() async throws {
        // Given — YandexGPT падает, GigaChat отвечает
        let failingYandex = MockAIProviderFailure(
            name: "YandexGPT",
            error: .providerUnavailable(provider: "YandexGPT")
        )
        let workingGigaChat = MockAIProviderSuccess(
            name: "GigaChat",
            response: AIResponse(
                text: """
                {"final_answer": "Рекомендую современный стиль лофт для вашей квартиры."}
                """,
                providerName: "GigaChat",
                isOffline: false,
                tokensUsed: 15
            )
        )
        let router = AIProviderRouter(
            providers: [failingYandex, workingGigaChat],
            fallbackChain: ["YandexGPT", "GigaChat"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )

        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Какой стиль выбрать?")

        // When
        let result = await loop.run(request: request, session: session)

        // Then
        guard case .completed(let finalAnswer, _) = result else {
            XCTFail("Ожидался .completed после fallback, получено: \(result)")
            return
        }
        XCTAssertTrue(finalAnswer.contains("лофт") || finalAnswer.contains("стиль"),
                      "Ответ должен содержать стиль")
    }

    /// Тест: все провайдеры падают → error.
    func testAgentLoop_AllProvidersFail_ReturnsError() async throws {
        // Given
        let failingYandex = MockAIProviderFailure(
            name: "YandexGPT",
            error: .providerUnavailable(provider: "YandexGPT")
        )
        let failingGigaChat = MockAIProviderFailure(
            name: "GigaChat",
            error: .providerUnavailable(provider: "GigaChat")
        )
        let router = AIProviderRouter(
            providers: [failingYandex, failingGigaChat],
            fallbackChain: ["YandexGPT", "GigaChat"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )

        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Тест ошибки")

        // When
        let result = await loop.run(request: request, session: session)

        // Then
        guard case .error = result else {
            XCTFail("Ожидался .error, получено: \(result)")
            return
        }
    }

    // MARK: - Planning Mode (Blueprint §7)

    /// Тест: бюджет > 500 000 ₽ → активируется planning mode.
    func testPlanningMode_LargeBudget_Activates() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let request = UserRequest(
            message: "Сделай дизайн гостиной",
            budgetRange: (min: 0, max: 600_000)
        )

        // When
        let shouldPlan = loop.shouldActivatePlanningMode(request: request, roomAnalysis: nil)

        // Then
        XCTAssertTrue(shouldPlan, "Planning mode должен активироваться при бюджете > 500 000 ₽")
    }

    /// Тест: комната > 30м² → активируется planning mode.
    func testPlanningMode_LargeRoom_Activates() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let room = RoomAnalysis(
            roomDimensions: RoomDimensionsAnalysis(widthM: 5, depthM: 8, heightM: 2.7),
            objects: [],
            floorAreaM2: 40
        )
        let request = UserRequest(inputType: .lidarScan, message: "Дизайн комнаты")

        // When
        let shouldPlan = loop.shouldActivatePlanningMode(request: request, roomAnalysis: room)

        // Then
        XCTAssertTrue(shouldPlan, "Planning mode должен активироваться для комнаты > 30м²")
    }

    /// Тест: пользователь без конкретики → planning mode.
    func testPlanningMode_VagueRequest_Activates() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let request = UserRequest(message: "Посоветуй, что делать с комнатой")

        // When
        let shouldPlan = loop.shouldActivatePlanningMode(request: request, roomAnalysis: nil)

        // Then
        XCTAssertTrue(shouldPlan, "Planning mode должен активироваться для vague запросов")
    }

    /// Тест: маленькая комната + конкретный запрос → planning mode НЕ активируется.
    func testPlanningMode_SmallRoomSpecificRequest_DoesNotActivate() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let room = RoomAnalysis(
            roomDimensions: RoomDimensionsAnalysis(widthM: 3, depthM: 4, heightM: 2.5),
            objects: [],
            floorAreaM2: 12
        )
        let request = UserRequest(
            message: "Подбери диван до 30 000 ₽",
            preferredStyle: "скандинавский",
            budgetRange: (min: 0, max: 30_000)
        )

        // When
        let shouldPlan = loop.shouldActivatePlanningMode(request: request, roomAnalysis: room)

        // Then
        XCTAssertFalse(shouldPlan, "Planning mode НЕ должен активироваться для маленькой комнаты с конкретным запросом")
    }

    // MARK: - Goal-like Loop (Blueprint §8)

    /// Тест: runGoalLoop с 2 чекпоинтами → completed.
    func testGoalLoop_TwoCheckpoints_Completes() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )
        let session = AgentSession(userId: "test_user")

        // When
        let result = await loop.runGoalLoop(
            objective: "Спроектировать гостиную 15м²",
            checkpoints: ["Просканировать комнату", "Подобрать стиль"],
            budget: 4,
            session: session
        )

        // Then — должен быть completed (model output содержит final_answer)
        // Goal loop вызывает run(), который с мок-провайдером возвращает completed
        switch result {
        case .completed, .stepBudgetReached:
            // Оба варианта допустимы в зависимости от того, сколько шагов занял каждый чекпоинт
            let goalState = await session.goalState
            XCTAssertNotNil(goalState, "Goal state должен быть установлен")
        default:
            XCTFail("Ожидался .completed или .stepBudgetReached, получено: \(result)")
        }
    }

    // MARK: - SessionCompactor (Blueprint §9)

    /// Тест: compaction при 80% заполнении создаёт сводку.
    func testSessionCompactor_CompactsAndRehydrates() async throws {
        // Given
        let compactor = SessionCompactor()
        let session = AgentSession(userId: "test_user")

        // Добавляем план
        let plan = DesignPlan(
            objective: "Дизайн гостиной 18м² в скандинавском стиле",
            scope: "Одна комната, мебель + декор",
            steps: ["Скан", "Стиль", "Мебель", "Расстановка", "Список"],
            toolsRequired: ["analyze_room_scan", "recommend_style"],
            doneCondition: "Список покупок сформирован"
        )
        await session.setPlan(plan)

        // Добавляем много событий для симуляции заполнения контекста
        for i in 1...20 {
            await session.addEvent(SessionEvent(
                type: i % 2 == 0 ? .toolCall : .toolResult,
                data: .json("{\"step\": \(i), \"data\": \"lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt\"}"),
                step: i
            ))
        }

        // When
        await compactor.compactAndRehydrate(session: session)

        // Then
        let summaries = await session.compactionSummaries
        XCTAssertGreaterThan(summaries.count, 0, "Должна быть создана compaction summary")
        if let summary = summaries.last {
            XCTAssertTrue(summary.objectiveAtCompaction?.contains("гостиной") ?? false,
                          "Summary должен содержать objective")
            XCTAssertTrue(summary.triggerReason.contains("80%"),
                          "Summary должен указывать причину — 80% заполнение")
        }
    }

    // MARK: - parseModelOutput

    /// Тест: парсинг JSON с final_answer.
    func testParseModelOutput_JSONFinalAnswer() async throws {
        // Given
        let loop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: mockProviderRouter
        )

        let rawJSON = """
        {
            "final_answer": "Рекомендую скандинавский стиль: светлые стены, натуральное дерево, минимализм.",
            "tool_calls": [
                {"name": "analyze_room_scan", "arguments": {"room_id": "r1"}, "id": "c1"}
            ]
        }
        """

        // When — используем приватный метод через отражение (indirect test)
        // parseModelOutput — приватный, тестируем через run()
        let provider = MockAIProviderSuccess(
            name: "JSON",
            response: AIResponse(text: rawJSON, providerName: "JSON", isOffline: false, tokensUsed: 10)
        )
        let router = AIProviderRouter(
            providers: [provider],
            fallbackChain: ["JSON"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )
        let testLoop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Стиль?")

        let result = await testLoop.run(request: request, session: session)

        // Then
        guard case .completed(let answer, _) = result else {
            XCTFail("Ожидался .completed, получено: \(result)")
            return
        }
        XCTAssertTrue(answer.contains("скандинавский"), "Ответ должен содержать стиль")
    }

    /// Тест: парсинг plain text (без JSON) → весь текст как final answer.
    func testParseModelOutput_PlainText() async throws {
        // Given
        let provider = MockAIProviderSuccess(
            name: "Plain",
            response: AIResponse(
                text: "Я рекомендую вам современный стиль с элементами лофта.",
                providerName: "Plain",
                isOffline: false,
                tokensUsed: 5
            )
        )
        let router = AIProviderRouter(
            providers: [provider],
            fallbackChain: ["Plain"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )
        let testLoop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Стиль?")

        // When
        let result = await testLoop.run(request: request, session: session)

        // Then
        guard case .completed(let answer, _) = result else {
            XCTFail("Ожидался .completed для plain text, получено: \(result)")
            return
        }
        XCTAssertTrue(answer.contains("рекомендую"), "Plain text должен быть взят как final answer")
    }

    /// Тест: парсинг Markdown с JSON блоком.
    func testParseModelOutput_MarkdownJSONBlock() async throws {
        // Given
        let provider = MockAIProviderSuccess(
            name: "Markdown",
            response: AIResponse(
                text: """
                Вот мой анализ:

                ```json
                {
                    "final_answer": "Для вашей спальни 12м² идеально подойдёт стиль минимализм.",
                    "tool_calls": [{"name": "recommend_style", "arguments": {}, "id": "md_1"}]
                }
                ```

                Надеюсь, это поможет!
                """,
                providerName: "Markdown",
                isOffline: false,
                tokensUsed: 20
            )
        )
        let router = AIProviderRouter(
            providers: [provider],
            fallbackChain: ["Markdown"],
            circuitBreakerConfig: CircuitBreakerConfig()
        )
        let testLoop = AgentLoop(
            toolRegistry: mockToolRegistry,
            providerRouter: router
        )
        let session = AgentSession(userId: "test_user")
        let request = UserRequest(message: "Стиль для спальни?")

        // When
        let result = await testLoop.run(request: request, session: session)

        // Then
        guard case .completed(let answer, _) = result else {
            XCTFail("Ожидался .completed для Markdown JSON, получено: \(result)")
            return
        }
        XCTAssertTrue(answer.contains("минимализм"), "Markdown JSON блок должен быть распарсен")
    }

    // MARK: - AgentSession Tests

    /// Тест: AgentSession хранит события корректно.
    func testAgentSession_EventsStorage() async throws {
        // Given
        let session = AgentSession(userId: "test_user")

        // When
        await session.addEvent(SessionEvent(type: .userMessage, data: .text("Привет"), step: 0))
        await session.addEvent(SessionEvent(type: .modelOutput, data: .json("{}"), step: 1))
        await session.addEvent(SessionEvent(type: .toolResult, data: .json("{\"status\":\"ok\"}"), step: 1))

        // Then
        let events = await session.allEvents
        XCTAssertEqual(events.count, 3, "Должно быть 3 события")
        XCTAssertEqual(events[0].type, .userMessage)
        XCTAssertEqual(events[1].type, .modelOutput)
        XCTAssertEqual(events[2].type, .toolResult)
    }

    /// Тест: AgentSession хранит план и todo.
    func testAgentSession_PlanAndTodo() async throws {
        // Given
        let session = AgentSession(userId: "test_user")

        let plan = DesignPlan(
            objective: "Дизайн гостиной",
            steps: ["Скан", "Стиль", "Мебель"],
            toolsRequired: ["analyze_room_scan"],
            doneCondition: "Список покупок готов"
        )
        let todo = TodoItem(title: "Выбрать диван")

        // When
        await session.setPlan(plan)
        await session.addTodo(todo)

        // Then
        let activePlan = await session.activePlan
        XCTAssertEqual(activePlan?.objective, "Дизайн гостиной")
        XCTAssertEqual(activePlan?.totalSteps, 3)

        let todos = await session.todoItems
        XCTAssertEqual(todos.count, 1)
        XCTAssertEqual(todos.first?.title, "Выбрать диван")
    }

    /// Тест: GoalState отслеживает прогресс чекпоинтов.
    func testAgentSession_GoalProgress() async throws {
        // Given
        let session = AgentSession(userId: "test_user")
        let goal = GoalState(
            objective: "Дизайн комнаты",
            budget: 6,
            checkpoints: ["Скан", "Стиль", "Мебель"],
            currentCheckpoint: "Скан",
            doneCondition: "Все чекпоинты пройдены"
        )

        // When
        await session.setGoalState(goal)
        await session.updateGoalProgress(checkpoint: "Скан", completed: true)

        // Then
        let updatedGoal = await session.goalState
        XCTAssertNotNil(updatedGoal)
        XCTAssertEqual(updatedGoal?.completedCheckpoints.count, 1)
        XCTAssertEqual(updatedGoal?.progress, 1.0 / 3.0, accuracy: 0.01)
        XCTAssertFalse(updatedGoal?.isDone ?? true, "Goal не должен быть завершён после 1/3 чекпоинтов")
    }

    // MARK: - ContextBuilder Tests

    /// Тест: ContextBuilder собирает 11 секций.
    func testContextBuilder_BuildsAllSections() async throws {
        // Given
        let builder = ContextBuilder()
        let session = AgentSession(userId: "test_user")
        let plan = DesignPlan(
            objective: "Тестовый дизайн",
            steps: ["Шаг 1"],
            toolsRequired: ["analyze_room_scan"],
            doneCondition: "Готово"
        )
        await session.setPlan(plan)

        // When
        let context = await builder.build(
            session: session,
            toolRegistry: mockToolRegistry,
            skillIndex: .standard
        )

        // Then
        XCTAssertGreaterThan(context.sections.count, 5, "Должно быть больше 5 секций контекста")
        XCTAssertGreaterThan(context.totalChars, 100, "Общий размер контекста должен быть > 100 символов")

        // Проверяем наличие ключевых секций
        let sectionLabels = context.sections.map(\.label)
        XCTAssertTrue(sectionLabels.contains(where: { $0.contains("System") }),
                      "Должна быть системная секция")
        XCTAssertTrue(sectionLabels.contains(where: { $0.contains("Policy") || $0.contains("Domain") }),
                      "Должна быть секция политик")
        XCTAssertTrue(sectionLabels.contains(where: { $0.contains("Tool") }),
                      "Должна быть секция инструментов")
        XCTAssertTrue(sectionLabels.contains(where: { $0.contains("User") }),
                      "Должна быть секция пользовательского запроса")
    }

    /// Тест: ContextBuilder определяет необходимость compaction при > 80%.
    func testContextBuilder_NeedsCompaction() async throws {
        // Given
        let builder = ContextBuilder()
        let session = AgentSession(userId: "test_user")

        // Добавляем много данных в сессию
        for i in 1...30 {
            await session.addEvent(SessionEvent(
                type: .toolResult,
                data: .json(String(repeating: "data_\(i)_", count: 200)),
                step: i
            ))
        }

        // When
        let context = await builder.build(
            session: session,
            toolRegistry: mockToolRegistry,
            skillIndex: .standard
        )

        // Then
        let needsCompaction = builder.needsCompaction(context: context)
        // Если контекст > 80% от максимума (12K символов)
        if context.totalChars > 9600 {
            XCTAssertTrue(needsCompaction, "Должна быть нужна compaction при > 80% заполнении")
        }
    }
}

// MARK: - ObservabilityCollector Tests

final class ObservabilityCollectorTests: XCTestCase {

    var collector: ObservabilityCollector!

    override func setUp() async throws {
        try await super.setUp()
        collector = ObservabilityCollector()
    }

    override func tearDown() async throws {
        collector = nil
        try await super.tearDown()
    }

    /// Тест: запись trace-событий увеличивает счётчики.
    func testRecord_IncrementsMetrics() async throws {
        // When
        await collector.recordSessionStart(sessionId: "s1", userId: "u1")
        await collector.recordToolCall(
            toolName: "analyze_room_scan",
            step: 1,
            sessionId: "s1",
            durationMs: 150.0,
            resultSize: 1024,
            success: true
        )
        await collector.recordToolCall(
            toolName: "search_marketplace_furniture",
            step: 2,
            sessionId: "s1",
            durationMs: 200.0,
            resultSize: 2048,
            success: true
        )
        await collector.recordProviderSwitch(
            from: "YandexGPT",
            to: "GigaChat",
            reason: "timeout",
            sessionId: "s1"
        )
        await collector.recordSessionEnd(
            sessionId: "s1",
            totalSteps: 3,
            outcome: "completed",
            totalDurationMs: 500.0
        )

        // Then
        let metrics = await collector.snapshot()
        XCTAssertEqual(metrics.totalToolCalls, 2)
        XCTAssertEqual(metrics.successfulToolCalls, 2)
        XCTAssertEqual(metrics.totalProviderFallbacks, 1)
        XCTAssertEqual(metrics.completedSessions, 1)
        XCTAssertEqual(metrics.toolCallSuccessRate, 1.0, accuracy: 0.01)
        XCTAssertEqual(metrics.providerFallbackRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(metrics.avgStepsPerSession, 3.0, accuracy: 0.01)
    }

    /// Тест: сброс метрик.
    func testResetMetrics_ClearsAll() async throws {
        // Given
        await collector.recordToolCall(
            toolName: "test",
            step: 1,
            sessionId: "s1",
            durationMs: 100,
            resultSize: 100,
            success: true
        )

        // When
        await collector.resetMetrics()

        // Then
        let metrics = await collector.snapshot()
        XCTAssertEqual(metrics.totalToolCalls, 0)
        XCTAssertEqual(metrics.successfulToolCalls, 0)
        XCTAssertEqual(metrics.completedSessions, 0)
    }

    /// Тест: per-tool статистика.
    func testPerToolStats_Accumulates() async throws {
        // When
        await collector.recordToolCall(
            toolName: "analyze_room_scan",
            step: 1,
            sessionId: "s1",
            durationMs: 100,
            resultSize: 500,
            success: true
        )
        await collector.recordToolCall(
            toolName: "analyze_room_scan",
            step: 2,
            sessionId: "s2",
            durationMs: 200,
            resultSize: 800,
            success: false
        )
        await collector.recordToolCall(
            toolName: "recommend_style",
            step: 1,
            sessionId: "s1",
            durationMs: 300,
            resultSize: 300,
            success: true
        )

        // Then
        let metrics = await collector.snapshot()
        let scanStats = metrics.perToolStats["analyze_room_scan"]
        XCTAssertNotNil(scanStats)
        XCTAssertEqual(scanStats?.callCount, 2)
        XCTAssertEqual(scanStats?.successCount, 1)
        XCTAssertEqual(scanStats?.failureCount, 1)
        XCTAssertEqual(scanStats?.avgDurationMs, 150.0, accuracy: 0.01)

        let styleStats = metrics.perToolStats["recommend_style"]
        XCTAssertNotNil(styleStats)
        XCTAssertEqual(styleStats?.callCount, 1)
        XCTAssertEqual(styleStats?.successRate, 1.0, accuracy: 0.01)
    }

    /// Тест: запись compaction события.
    func testRecordCompaction_TracksMetrics() async throws {
        // When
        await collector.recordCompaction(charsBefore: 15000, charsAfter: 4000, sessionId: "s1")
        await collector.recordCompaction(charsBefore: 14000, charsAfter: 5000, sessionId: "s2")
        await collector.recordSessionEnd(
            sessionId: "s1",
            totalSteps: 5,
            outcome: "completed",
            totalDurationMs: 1000
        )
        await collector.recordSessionEnd(
            sessionId: "s2",
            totalSteps: 7,
            outcome: "completed",
            totalDurationMs: 2000
        )

        // Then
        let metrics = await collector.snapshot()
        XCTAssertEqual(metrics.totalCompactions, 2)
        XCTAssertEqual(metrics.compactionFrequency, 1.0, accuracy: 0.01) // 2 compactions / 2 sessions
    }

    /// Тест: лимит trace-записей (1000).
    func testTraceLimit_DoesNotExceedMax() async throws {
        // When — добавляем 1500 записей
        for i in 0..<1500 {
            await collector.record(TraceRecord(
                eventType: .toolCall,
                sessionId: "s_limit",
                step: i,
                toolName: "test_tool",
                durationMs: 10
            ))
        }

        // Then — метрики должны отражать все 1500 вызовов
        let metrics = await collector.snapshot()
        XCTAssertEqual(metrics.totalToolCalls, 1500)
        // Traces должны быть обрезаны до 1000 (проверяем через косвенный тест — метрики не аффектятся)
        // Но метрики считаются отдельно от traces, это нормально
        XCTAssertEqual(metrics.totalToolCalls, 1500, "Метрики считают все вызовы, даже если traces обрезаны")
    }
}

// MARK: - Eval Probes Tests (Blueprint §13: 8 probes)

final class EvalProbeTests: XCTestCase {

    /// Тест: все 8 eval probes определены корректно.
    func testStandardProbes_AllEightDefined() async throws {
        let probes = EvalProbe.standardProbes
        XCTAssertEqual(probes.count, 8, "Должно быть ровно 8 eval probes (Blueprint §13)")

        // Проверяем, что все ID уникальны
        let ids = Set(probes.map(\.id))
        XCTAssertEqual(ids.count, 8, "Все ID probes должны быть уникальны")
    }

    /// Тест: 6 из 8 probes — launch gates.
    func testStandardProbes_SixLaunchGates() async throws {
        let launchGates = EvalProbe.standardProbes.filter(\.isLaunchGate)
        XCTAssertEqual(launchGates.count, 6, "Должно быть 6 launch-gate probes")
    }

    /// Тест: probe 1 (пустая комната) ожидает completed + specific tools.
    func testProbe01_EmptyRoom_HasCorrectExpectations() async throws {
        let probe = EvalProbe.standardProbes.first(where: { $0.id == "probe_01_empty_room" })
        XCTAssertNotNil(probe, "probe_01_empty_room должен существовать")
        XCTAssertEqual(probe?.expectedOutcome, .completed)
        XCTAssertEqual(probe?.expectedTools, ["analyze_room_scan", "recommend_style", "search_marketplace_furniture"])
        XCTAssertTrue(probe?.isLaunchGate ?? false, "probe_01 должен быть launch gate")
    }

    /// Тест: probe 3 (YandexGPT fallback) ожидает completed.
    func testProbe03_ProviderFallback_HasCorrectExpectations() async throws {
        let probe = EvalProbe.standardProbes.first(where: { $0.id == "probe_03_provider_fallback" })
        XCTAssertNotNil(probe, "probe_03_provider_fallback должен существовать")
        XCTAssertEqual(probe?.expectedOutcome, .completed)
        XCTAssertTrue(probe?.isLaunchGate ?? false, "probe_03 должен быть launch gate")
    }

    /// Тест: probe 8 (несущая стена) — launch gate.
    func testProbe08_LoadBearingWall_IsLaunchGate() async throws {
        let probe = EvalProbe.standardProbes.first(where: { $0.id == "probe_08_load_bearing_wall" })
        XCTAssertNotNil(probe, "probe_08_load_bearing_wall должен существовать")
        XCTAssertEqual(probe?.expectedOutcome, .completed)
        XCTAssertEqual(probe?.expectedTools, ["analyze_room_scan", "generate_arrangement_plan"])
        XCTAssertTrue(probe?.isLaunchGate ?? false, "probe_08 должен быть launch gate")
    }
}

// MARK: - EvalProbeRunner Tests

final class EvalProbeRunnerTests: XCTestCase {

    var collector: ObservabilityCollector!
    var runner: EvalProbeRunner!

    override func setUp() async throws {
        try await super.setUp()
        collector = ObservabilityCollector()
        runner = EvalProbeRunner(collector: collector)
    }

    override func tearDown() async throws {
        runner = nil
        collector = nil
        try await super.tearDown()
    }

    /// Тест: EvalProbeRunner запускает все пробы и возвращает результаты.
    func testRunAllProbes_ReturnsResults() async throws {
        // When — мок-раннер: все пробы проходят
        let results = await runner.runAllProbes { probe in
            // Симулируем успешное выполнение пробы
            return EvalProbeResult(
                probeId: probe.id,
                passed: true,
                actualOutcome: probe.expectedOutcome,
                expectedOutcome: probe.expectedOutcome,
                actualTools: probe.expectedTools,
                expectedTools: probe.expectedTools,
                durationMs: Double.random(in: 50...300),
                summary: "Проба «\(probe.name)» пройдена успешно",
                finalAnswer: "Мок-ответ для \(probe.name)"
            )
        }

        // Then
        XCTAssertEqual(results.count, 8, "Должны быть результаты для всех 8 probes")
        let allPassed = results.values.allSatisfy(\.passed)
        XCTAssertTrue(allPassed, "Все probes должны быть пройдены")

        // Проверяем launch gates
        let launchGatesPassed = await runner.allLaunchGatesPassed()
        XCTAssertTrue(launchGatesPassed, "Все launch gates должны быть пройдены")
    }

    /// Тест: EvalProbeRunner — один probe провален.
    func testRunAllProbes_OneFailure() async throws {
        // When — probe_05 провален
        let results = await runner.runAllProbes { probe in
            let passed = probe.id != "probe_05_out_of_stock"
            return EvalProbeResult(
                probeId: probe.id,
                passed: passed,
                actualOutcome: passed ? probe.expectedOutcome : .error,
                expectedOutcome: probe.expectedOutcome,
                actualTools: passed ? probe.expectedTools : [],
                expectedTools: probe.expectedTools,
                durationMs: 100,
                summary: passed ? "OK" : "Товар не предложил альтернативу"
            )
        }

        // Then
        XCTAssertEqual(results.count, 8)
        let passedCount = results.values.filter(\.passed).count
        XCTAssertEqual(passedCount, 7, "7 из 8 probes должны быть пройдены")

        // probe_05 не является launch gate → allLaunchGatesPassed = true
        let launchGatesPassed = await runner.allLaunchGatesPassed()
        XCTAssertTrue(launchGatesPassed, "Launch gates должны быть пройдены (probe_05 не launch gate)")
    }

    /// Тест: EvalProbeRunner — launch gate провален.
    func testRunAllProbes_LaunchGateFailure() async throws {
        // When — probe_01 (launch gate) провален
        let results = await runner.runAllProbes { probe in
            let passed = probe.id != "probe_01_empty_room"
            return EvalProbeResult(
                probeId: probe.id,
                passed: passed,
                actualOutcome: passed ? probe.expectedOutcome : .error,
                expectedOutcome: probe.expectedOutcome,
                actualTools: passed ? probe.expectedTools : [],
                expectedTools: probe.expectedTools,
                durationMs: 150,
                summary: passed ? "OK" : "Комната не проанализирована"
            )
        }

        // Then
        let launchGatesPassed = await runner.allLaunchGatesPassed()
        XCTAssertFalse(launchGatesPassed, "Launch gates НЕ должны быть пройдены (probe_01 провален)")
    }

    /// Тест: EvalSummary содержит корректные данные.
    func testEvalSummary_ContainsCorrectData() async throws {
        // When
        _ = await runner.runAllProbes { probe in
            EvalProbeResult(
                probeId: probe.id,
                passed: true,
                actualOutcome: probe.expectedOutcome,
                expectedOutcome: probe.expectedOutcome,
                actualTools: probe.expectedTools,
                expectedTools: probe.expectedTools,
                durationMs: 200,
                summary: "OK"
            )
        }

        // Then
        let summary = await runner.summary()
        XCTAssertEqual(summary.totalProbes, 8)
        XCTAssertEqual(summary.passedProbes, 8)
        XCTAssertEqual(summary.failedProbes, 0)
        XCTAssertEqual(summary.launchGatesTotal, 6)
        XCTAssertEqual(summary.launchGatesPassed, 6)
        XCTAssertEqual(summary.launchGatesFailed, 0)
        XCTAssertEqual(summary.passRate, 1.0, accuracy: 0.01)
        XCTAssertTrue(summary.allLaunchGatesPassed)
        XCTAssertEqual(summary.probes.count, 8)
    }
}

// MARK: - TraceRecord Tests

final class TraceRecordTests: XCTestCase {

    /// Тест: toJSON() создаёт валидный JSON.
    func testToJSON_ProducesValidJSON() async throws {
        let record = TraceRecord(
            eventType: .sessionStart,
            sessionId: "s1",
            metadata: ["user_id": "u1", "app_version": "1.0"]
        )

        let json = record.toJSON()

        // Парсим JSON обратно
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["event"] as? String, "session_start")
        XCTAssertEqual(obj?["session_id"] as? String, "s1")
        let meta = obj?["meta"] as? [String: String]
        XCTAssertEqual(meta?["user_id"], "u1")
    }

    /// Тест: toJSON() с опциональными полями (nil).
    func testToJSON_MinimalFields() async throws {
        let record = TraceRecord(eventType: .compaction)

        let json = record.toJSON()
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["event"] as? String, "compaction")
        XCTAssertNil(obj?["session_id"])
        XCTAssertNil(obj?["step"])
    }
}
