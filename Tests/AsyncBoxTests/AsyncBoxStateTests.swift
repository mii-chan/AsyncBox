import Testing
@testable import AsyncBox

struct TestError: Error, Equatable {
    let id: Int
}

struct TestStateFailure: AsyncBoxStateFailure, Equatable {
    let id: Int
    let isValueValid: Bool
}

@Suite
struct AsyncBoxStateTests {
    @Test
    func valueReturnsLoadedValue() {
        let state = AsyncBoxState<Int>.loaded(1)
        #expect(state.value == 1)
    }

    @Test
    func valueReturnsPreviousValueWhileLoading() {
        let state = AsyncBoxState<Int>.loading(1)
        #expect(state.value == 1)
    }

    @Test
    func valueReturnsPreviousValueOnError() {
        let state = AsyncBoxState<Int>.error(TestError(id: 1), 1)
        #expect(state.value == 1)
    }

    @Test
    func valueIsNilWithoutPreviousValue() {
        #expect(AsyncBoxState<Int>.initial.value == nil)
        #expect(AsyncBoxState<Int>.loading(nil).value == nil)
        #expect(AsyncBoxState<Int>.error(TestError(id: 1), nil).value == nil)
    }

    @Test
    func errorReturnsErrorOnlyInErrorState() {
        let state = AsyncBoxState<Int>.error(TestError(id: 1), nil)
        #expect(state.error as? TestError == TestError(id: 1))
        #expect(AsyncBoxState<Int>.initial.error == nil)
        #expect(AsyncBoxState<Int>.loading(nil).error == nil)
        #expect(AsyncBoxState<Int>.loaded(1).error == nil)
    }

    @Test
    func isLoading() {
        #expect(AsyncBoxState<Int>.loading(nil).isLoading)
        #expect(AsyncBoxState<Int>.loading(1).isLoading)
        #expect(!AsyncBoxState<Int>.initial.isLoading)
        #expect(!AsyncBoxState<Int>.loaded(1).isLoading)
        #expect(!AsyncBoxState<Int>.error(TestError(id: 1), nil).isLoading)
    }

    @Test
    func isInitial() {
        #expect(AsyncBoxState<Int>.initial.isInitial)
        #expect(!AsyncBoxState<Int>.loading(nil).isInitial)
        #expect(!AsyncBoxState<Int>.loaded(1).isInitial)
        #expect(!AsyncBoxState<Int>.error(TestError(id: 1), nil).isInitial)
    }

    @Test
    func hasValueFollowsValue() {
        #expect(AsyncBoxState<Int>.loaded(1).hasValue)
        #expect(AsyncBoxState<Int>.loading(1).hasValue)
        #expect(AsyncBoxState<Int>.error(TestError(id: 1), 1).hasValue)
        #expect(!AsyncBoxState<Int>.initial.hasValue)
        #expect(!AsyncBoxState<Int>.loading(nil).hasValue)
        #expect(!AsyncBoxState<Int>.error(TestError(id: 1), nil).hasValue)
    }
}
