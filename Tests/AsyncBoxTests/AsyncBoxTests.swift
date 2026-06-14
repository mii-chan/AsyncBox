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
        try await box.load { 1 }
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
    func loadRejectsOverlappingOperation() async {
        let box = AsyncBox<Int>(state: .loading(1))
        var didPerform = false

        await #expect(throws: AsyncBoxLoadError.alreadyLoading) {
            try await box.load {
                didPerform = true
                return 2
            }
        }

        #expect(!didPerform)
        guard case .loading(1) = box.state else {
            Issue.record("expected .loading(1), got \(box.state)")
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

        do {
            try await box.load { throw CancellationError() }
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        guard case .loaded(1) = box.state else {
            Issue.record("expected .loaded(1), got \(box.state)")
            return
        }
    }

    @Test
    func loadCancellationReturnsToInitialWithoutValue() async {
        let box = AsyncBox<Int>()

        do {
            try await box.load { throw CancellationError() }
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        #expect(box.isInitial)
    }

    @Test
    func cancelledRetryRestoresPreviousErrorWithValue() async {
        let previousError = TestError(id: 1)
        let box = AsyncBox<Int>(state: .error(previousError, 1))

        do {
            try await box.load { throw CancellationError() }
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
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

        do {
            try await box.load { throw CancellationError() }
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }

        guard case .error(let error, nil) = box.state else {
            Issue.record("expected .error(previousError, nil), got \(box.state)")
            return
        }
        #expect(error as? TestError == previousError)
    }
}
