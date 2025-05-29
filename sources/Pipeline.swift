//
//  ChatAgentPipeline.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

class PipelineBuilder<T> {
    private let deps: Set<UUID>
    private var root = [Pipeline<T>.Action]()
    private var children = [PipelineBuilder<T>]()

    init() {
        deps = Set()
    }

    private init(deps: Set<UUID>) {
        self.deps = deps
    }

    @discardableResult
    func add(description: String,
             actionClosure: @escaping Pipeline<T>.Action.Closure) -> UUID {
        let action = Pipeline<T>.Action(description: description,
                                        dependencies: deps,
                                        closure: actionClosure)
        root.append(action)
        return action.id
    }

    func makeChild() -> PipelineBuilder<T> {
        let child = PipelineBuilder(deps: Set(transitiveActions.map { $0.id }))
        children.append(child)
        return child
    }
    private var transitiveActions: [Pipeline<T>.Action] {
        return root + children.flatMap { $0.transitiveActions }
    }

    func build(maxConcurrentActions: Int,
               completion: ((Pipeline<T>.Disposition) -> ())? = nil) -> Pipeline<T> {
        return Pipeline(actions: transitiveActions,
                        maxConcurrentActions: maxConcurrentActions,
                        completion: completion)
    }
}
class PipelineQueue<T> {
    private var pipelines = [Pipeline<T>]()

    func append(_ pipeline: Pipeline<T>) {
        dispatchPrecondition(condition: .onQueue(.main))
        let originalCompletion = pipeline.completion
        pipeline.completion = { [weak self] disposition in
            originalCompletion?(disposition)
            self?.pipelineDidComplete()
        }
        self.pipelines.append(pipeline)
        if self.pipelines.count == 1 {
            DLog("pipeline queue got a first element so begin executing it")
            pipeline.begin()
        }
    }

    private func pipelineDidComplete() {
        DLog("Pipeline completed. Run next if available")
        pipelines.removeFirst()
        pipelines.first?.begin()
    }

    func cancelAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        DLog("Cancel pipeline queue")
        let saved = pipelines
        pipelines.removeAll()
        for pipeline in saved {
            pipeline.cancel()
        }
    }
}

class Pipeline<T>: CustomDebugStringConvertible {
    var debugDescription: String {
        var lines = [String]()
        for action in actions {
            let deps = Array(action.dependencies).map { uuid -> String in
                return self.action(uuid: uuid)?.description ?? "Unknown action \(uuid) (BUG)"
            }.joined(separator: ", ")
            let status: String
            if runningActions.contains(where: { $0.id == action.id }) {
                status = "Running"
            } else if eligibleActions.contains(where: { $0.id == action.id }) {
                status = "Eligible"
            } else if blockedActions.contains(where: { $0.id == action.id }) {
                status = "Blocked"
            } else if completedActionIDs.contains(action.id) {
                status = "Completed"
            } else {
                status = "Unknown (bug)"
            }
            lines.append("\(action.description) [\(status)]: \(deps)")
        }
        return lines.joined(separator: "\n")
    }

    private func action(uuid: UUID) -> Action? {
        return actions.first { $0.id == uuid }
    }

    struct Action {
        typealias Closure = ([UUID: T], @escaping (Result<T, Error>) -> ()) -> ()
        var id = UUID()
        var description: String
        // Begins the action. The passed-in closure must be called eventually. If
        // the Error is nonnil then the pipeline aborts.
        var dependencies: Set<UUID>
        var closure: Closure
    }
    enum Disposition {
        case pending
        case success([UUID: T])
        case failure(Error)
        case canceled

        var isPending: Bool {
            switch self {
            case .pending: true
            default: false
            }
        }
    }
    let actions: [Action]
    let maxConcurrentActions: Int
    var completion: ((Disposition) -> ())?
    private var runningActions = [Action]()
    private var eligibleActions = [Action]()
    private var blockedActions = [Action]()
    private var completedActionIDs = Set<UUID>()
    private var disposition = Disposition.pending
    private var begun = false
    private var values = [UUID: T]()

    init(actions: [Action],
         maxConcurrentActions: Int,
         completion: ((Disposition) -> ())? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(maxConcurrentActions > 0, "maxConcurrentActions must be positive")
        let ids = actions.map { $0.id }
        precondition(Set(ids).count == ids.count, "Action IDs must be unique")

        self.actions = actions
        self.completion = completion
        self.maxConcurrentActions = maxConcurrentActions
        blockedActions = actions
    }

    func begin() {
        dispatchPrecondition(condition: .onQueue(.main))
        it_assert(!begun)

        let allDeps = blockedActions.reduce(into: Set<UUID>()) { deps, action in
            deps.formUnion(action.dependencies)
        }
        if !allDeps.subtracting(Set(blockedActions.map(\.id))).isEmpty {
            it_fatalError("Pipeline has unsatisfiable dependencies")
        }
        begun = true
        schedule()
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        finish(.canceled)
    }

    private func isBlocked(_ action: Action) -> Bool {
        return !action.dependencies.subtracting(completedActionIDs).isEmpty
    }

    private func moveBlockedToEligible() {
        let indexes = blockedActions.indexes { action in
            !isBlocked(action)
        }
        let newlyEligibleActions = blockedActions[indexes]
        blockedActions.remove(at: indexes)
        eligibleActions.append(contentsOf: newlyEligibleActions)
        DLog("These pipeline actions are now eligible: \(newlyEligibleActions.map(\.description).joined(separator: ", "))")
    }

    private func moveEligibleToRunning() {
        while (!eligibleActions.isEmpty &&
               runningActions.count < maxConcurrentActions &&
               disposition.isPending) {
            let actionToRun = eligibleActions.removeFirst()
            runningActions.append(actionToRun)
            DLog("Run pipeline action \(actionToRun.description)")
            actionToRun.closure(values) { [weak self] result in
                dispatchPrecondition(condition: .onQueue(.main))
                switch result {
                case .success(let value):
                    DLog("Pipeline action \(actionToRun.description) completed successfuly with value \(value)")
                    self?.actionDidComplete(actionToRun.id, value: value)
                case .failure(let error):
                    DLog("Pipeline action \(actionToRun.description) failed with error \(error.localizedDescription)")
                    self?.finish(.failure(error))
                }
            }
        }
    }

    private var finishedSuccessfully: Bool {
        (disposition.isPending &&
         runningActions.isEmpty &&
         eligibleActions.isEmpty &&
         blockedActions.isEmpty)
    }

    private func schedule() {
        dispatchPrecondition(condition: .onQueue(.main))
        DLog("schedule() beginning")
        moveBlockedToEligible()
        moveEligibleToRunning()
        if finishedSuccessfully {
            finish(.success(values))
        }
    }

    private func finish(_ disposition: Disposition) {
        if !self.disposition.isPending {
            return
        }
        DLog("pipeline finished with disposition \(disposition)")
        self.disposition = disposition
        runningActions = []
        eligibleActions = []
        blockedActions = []
        completion?(disposition)
    }

    private func actionDidComplete(_ actionID: UUID, value: T) {
        if !disposition.isPending {
            return
        }
        values[actionID] = value
        completedActionIDs.insert(actionID)
        runningActions.removeAll { $0.id == actionID }
        schedule()
    }
}
