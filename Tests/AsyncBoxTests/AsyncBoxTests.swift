import Testing
@testable import AsyncBox

@MainActor
@Suite
struct AsyncBoxTests {
    // MARK: Initialization

    @Test
    func startsInInitialState() {
        let box = AsyncBox<Int>()
        #expect(box.isInitial)
        #expect(box.value == nil)
    }

    @Test
    func startsLoadedWithInitialValue() {
        let box = AsyncBox(initialValue: 1)
        #expect(box.value == 1)
        #expect(!box.isInitial)
    }

    @Test
    func startsInGivenState() {
        let box = AsyncBox<Int>(state: .loading(1))
        #expect(box.isLoading)
        #expect(box.value == 1)
    }

    // MARK: Transitions

    @Test
    func succeedTransitionsToLoaded() {
        let box = AsyncBox<Int>()
        box.succeed(with: 1)
        guard case .loaded(1) = box.state else {
            Issue.record("expected .loaded(1), got \(box.state)")
            return
        }
    }

    @Test
    func failRetainsCurrentValueForUnclassifiedError() {
        let box = AsyncBox(initialValue: 1)
        box.fail(with: TestError(id: 1))
        #expect(box.error as? TestError == TestError(id: 1))
        #expect(box.value == 1)
    }

    @Test
    func failRetainsCurrentValueWhenItRemainsValid() {
        let box = AsyncBox(initialValue: 1)
        let failure = TestStateFailure(id: 1, isValueValid: true)
        box.fail(with: failure)
        #expect(box.error as? TestStateFailure == failure)
        #expect(box.value == 1)
    }

    @Test
    func failDiscardsCurrentValueWhenItIsInvalid() {
        let box = AsyncBox(initialValue: 1)
        let failure = TestStateFailure(id: 1, isValueValid: false)
        box.fail(with: failure)
        #expect(box.error as? TestStateFailure == failure)
        #expect(box.value == nil)
    }

    @Test
    func startLoadingRetainsCurrentValueAsPrevious() {
        let box = AsyncBox(initialValue: 1)
        box.startLoading()
        #expect(box.isLoading)
        #expect(box.value == 1)
    }

    @Test
    func resetReturnsToInitial() {
        let box = AsyncBox(initialValue: 1)
        box.reset()
        #expect(box.isInitial)
        #expect(box.value == nil)
    }

    // MARK: mutate

    @Test
    func mutateUpdatesLoadedValue() {
        let box = AsyncBox(initialValue: 1)
        box.mutate { $0 += 1 }
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func mutateUpdatesPreviousValueWhileLoading() {
        let box = AsyncBox<Int>(state: .loading(1))
        box.mutate { $0 += 1 }
        #expect(box.isLoading)
        #expect(box.value == 2)
    }

    @Test
    func mutateUpdatesPreviousValueOnError() {
        let box = AsyncBox<Int>(state: .error(TestError(id: 1), 1))
        box.mutate { $0 += 1 }
        #expect(box.error as? TestError == TestError(id: 1))
        #expect(box.value == 2)
    }

    @Test
    func mutateDoesNothingWithoutValue() {
        let box = AsyncBox<Int>()
        box.mutate { $0 += 1 }
        #expect(box.isInitial)

        let loading = AsyncBox<Int>(state: .loading(nil))
        loading.mutate { $0 += 1 }
        #expect(loading.isLoading)
        #expect(loading.value == nil)
    }

    // MARK: load

    @Test
    func loadSucceeds() async throws {
        let box = AsyncBox<Int>()
        let applied = try await box.load { 1 }
        #expect(applied)
        guard case .loaded(1) = box.state else {
            Issue.record("expected .loaded(1), got \(box.state)")
            return
        }
    }

    @Test
    func loadIsLoadingWhilePerforming() async throws {
        let box = AsyncBox(initialValue: 1)
        try await box.load {
            #expect(box.isLoading)
            #expect(box.value == 1)
            return 2
        }
        #expect(box.value == 2)
    }

    @Test
    func loadSkipsWhileLoadingByDefault() async throws {
        let box = AsyncBox<Int>(state: .loading(1))
        var didPerform = false

        let applied = try await box.load {
            didPerform = true
            return 2
        }

        #expect(!applied)
        #expect(!didPerform)
        guard case .loading(1) = box.state else {
            Issue.record("expected .loading(1), got \(box.state)")
            return
        }
    }

    @Test
    func loadRestartsWhileLoading() async throws {
        let box = AsyncBox<Int>(state: .loading(1))
        let applied = try await box.load(ifLoading: .restart) { 2 }
        #expect(applied)
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func loadFailureTransitionsToErrorAndRethrows() async {
        let box = AsyncBox(initialValue: 1)
        await #expect(throws: TestError(id: 1)) {
            try await box.load { throw TestError(id: 1) }
        }
        #expect(box.error as? TestError == TestError(id: 1))
        #expect(box.value == 1)
    }

    @Test
    func loadFailureDiscardsInvalidValue() async {
        let box = AsyncBox(initialValue: 1)
        let failure = TestStateFailure(id: 1, isValueValid: false)
        await #expect(throws: failure) {
            try await box.load { throw failure }
        }
        #expect(box.error as? TestStateFailure == failure)
        #expect(box.value == nil)
    }

    @Test
    func loadCancellationReturnsToLoadedWhenValueExists() async {
        let box = AsyncBox(initialValue: 1)

        await #expect(throws: CancellationError.self) {
            try await box.load { throw CancellationError() }
        }

        guard case .loaded(1) = box.state else {
            Issue.record("expected .loaded(1), got \(box.state)")
            return
        }
    }

    @Test
    func loadCancellationReturnsToInitialWithoutValue() async {
        let box = AsyncBox<Int>()

        await #expect(throws: CancellationError.self) {
            try await box.load { throw CancellationError() }
        }

        #expect(box.isInitial)
    }

    @Test
    func cancelledRetryRestoresPreviousErrorWithValue() async {
        let previousError = TestError(id: 1)
        let box = AsyncBox<Int>(state: .error(previousError, 1))

        await #expect(throws: CancellationError.self) {
            try await box.load { throw CancellationError() }
        }

        guard case .error(let error, 1) = box.state else {
            Issue.record("expected .error(previousError, 1), got \(box.state)")
            return
        }
        #expect(error as? TestError == previousError)
    }

    @Test
    func cancelledRetryRestoresPreviousErrorWithoutValue() async {
        let previousError = TestError(id: 1)
        let box = AsyncBox<Int>(state: .error(previousError, nil))

        await #expect(throws: CancellationError.self) {
            try await box.load { throw CancellationError() }
        }

        guard case .error(let error, nil) = box.state else {
            Issue.record("expected .error(previousError, nil), got \(box.state)")
            return
        }
        #expect(error as? TestError == previousError)
    }

    @Test
    func loadCancellationKeepsValueMutatedWhileLoading() async {
        let box = AsyncBox(initialValue: 1)
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                throw CancellationError()
            }
        }
        await gate.waitUntilEntered()

        box.mutate { $0 += 1 }
        gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    // MARK: Overlapping loads

    @Test
    func loadSkipsWhileAnotherLoadIsInFlight() async throws {
        let box = AsyncBox<Int>()
        let gate = LoadGate()
        let first = Task {
            try await box.load {
                await gate.enter()
                return 1
            }
        }
        await gate.waitUntilEntered()

        var didPerform = false
        let secondApplied = try await box.load {
            didPerform = true
            return 2
        }
        #expect(!secondApplied)
        #expect(!didPerform)

        gate.release()
        let firstApplied = try await first.value
        #expect(firstApplied)
        guard case .loaded(1) = box.state else {
            Issue.record("expected .loaded(1), got \(box.state)")
            return
        }
    }

    @Test
    func restartDiscardsOlderLoadThatCompletesFirst() async throws {
        let box = AsyncBox(initialValue: 0)
        let firstGate = LoadGate()
        let secondGate = LoadGate()
        let first = Task {
            try await box.load {
                await firstGate.enter()
                return 1
            }
        }
        await firstGate.waitUntilEntered()
        let second = Task {
            try await box.load(ifLoading: .restart) {
                await secondGate.enter()
                return 2
            }
        }
        await secondGate.waitUntilEntered()

        firstGate.release()
        let firstApplied = try await first.value
        #expect(!firstApplied)
        guard case .loading(0) = box.state else {
            Issue.record("expected .loading(0), got \(box.state)")
            return
        }

        secondGate.release()
        let secondApplied = try await second.value
        #expect(secondApplied)
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func restartDiscardsOlderLoadThatCompletesLast() async throws {
        let box = AsyncBox(initialValue: 0)
        let firstGate = LoadGate()
        let secondGate = LoadGate()
        let first = Task {
            try await box.load {
                await firstGate.enter()
                return 1
            }
        }
        await firstGate.waitUntilEntered()
        let second = Task {
            try await box.load(ifLoading: .restart) {
                await secondGate.enter()
                return 2
            }
        }
        await secondGate.waitUntilEntered()

        secondGate.release()
        let secondApplied = try await second.value
        #expect(secondApplied)
        #expect(box.value == 2)

        firstGate.release()
        let firstApplied = try await first.value
        #expect(!firstApplied)
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func cancelledRestartRestoresStateBeforeFirstLoad() async throws {
        let previousError = TestError(id: 1)
        let box = AsyncBox<Int>(state: .error(previousError, 1))
        let firstGate = LoadGate()
        let secondGate = LoadGate()
        let first = Task {
            try await box.load {
                await firstGate.enter()
                return 2
            }
        }
        await firstGate.waitUntilEntered()
        let second = Task {
            try await box.load(ifLoading: .restart) {
                await secondGate.enter()
                throw CancellationError()
            }
        }
        await secondGate.waitUntilEntered()

        secondGate.release()
        await #expect(throws: CancellationError.self) { try await second.value }
        guard case .error(let error, 1) = box.state else {
            Issue.record("expected .error(previousError, 1), got \(box.state)")
            return
        }
        #expect(error as? TestError == previousError)

        firstGate.release()
        let firstApplied = try await first.value
        #expect(!firstApplied)
        #expect(box.error as? TestError == previousError)
        #expect(box.value == 1)
    }

    // MARK: Invalidation by direct transitions

    @Test
    func resetDiscardsSuccessOfInFlightLoad() async throws {
        let box = AsyncBox<Int>()
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                return 1
            }
        }
        await gate.waitUntilEntered()

        box.reset()
        gate.release()

        let applied = try await task.value
        #expect(!applied)
        #expect(box.isInitial)
    }

    @Test
    func resetDiscardsFailureOfInFlightLoad() async throws {
        let box = AsyncBox<Int>()
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                throw TestError(id: 1)
            }
        }
        await gate.waitUntilEntered()

        box.reset()
        gate.release()

        let applied = try await task.value
        #expect(!applied)
        #expect(box.isInitial)
    }

    @Test
    func resetDoesNotRestoreCancelledInFlightLoad() async {
        // Restoring here would yield `.error(_, nil)`, not `.initial`.
        let box = AsyncBox<Int>(state: .error(TestError(id: 1), 1))
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                throw CancellationError()
            }
        }
        await gate.waitUntilEntered()

        box.reset()
        gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(box.isInitial)
    }

    @Test
    func loadAfterResetWinsWhenOlderLoadCompletesFirst() async throws {
        let box = AsyncBox<Int>()
        let firstGate = LoadGate()
        let secondGate = LoadGate()
        let first = Task {
            try await box.load {
                await firstGate.enter()
                return 1
            }
        }
        await firstGate.waitUntilEntered()

        box.reset()
        let second = Task {
            try await box.load {
                await secondGate.enter()
                return 2
            }
        }
        await secondGate.waitUntilEntered()

        firstGate.release()
        let firstApplied = try await first.value
        #expect(!firstApplied)
        guard case .loading(nil) = box.state else {
            Issue.record("expected .loading(nil), got \(box.state)")
            return
        }

        secondGate.release()
        let secondApplied = try await second.value
        #expect(secondApplied)
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func loadAfterResetWinsWhenOlderLoadCompletesLast() async throws {
        let box = AsyncBox<Int>()
        let firstGate = LoadGate()
        let secondGate = LoadGate()
        let first = Task {
            try await box.load {
                await firstGate.enter()
                return 1
            }
        }
        await firstGate.waitUntilEntered()

        box.reset()
        let second = Task {
            try await box.load {
                await secondGate.enter()
                return 2
            }
        }
        await secondGate.waitUntilEntered()

        secondGate.release()
        let secondApplied = try await second.value
        #expect(secondApplied)
        #expect(box.value == 2)

        firstGate.release()
        let firstApplied = try await first.value
        #expect(!firstApplied)
        guard case .loaded(2) = box.state else {
            Issue.record("expected .loaded(2), got \(box.state)")
            return
        }
    }

    @Test
    func succeedDiscardsInFlightLoad() async throws {
        let box = AsyncBox<Int>()
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                return 1
            }
        }
        await gate.waitUntilEntered()

        box.succeed(with: 5)
        gate.release()

        let applied = try await task.value
        #expect(!applied)
        guard case .loaded(5) = box.state else {
            Issue.record("expected .loaded(5), got \(box.state)")
            return
        }
    }

    @Test
    func failDiscardsInFlightLoad() async throws {
        let box = AsyncBox<Int>()
        let gate = LoadGate()
        let task = Task {
            try await box.load {
                await gate.enter()
                return 1
            }
        }
        await gate.waitUntilEntered()

        box.fail(with: TestError(id: 1))
        gate.release()

        let applied = try await task.value
        #expect(!applied)
        #expect(box.error as? TestError == TestError(id: 1))
        #expect(box.value == nil)
    }
}
