import AppKit
import MouseCore
import Observation

/// Drives the hardware check against the live session: each step is a small script that writes to the mouse,
/// waits for the owner (answers, mouse moves, a key press, a connection or battery change), and records an outcome.
/// Test writes are transient; the owner's settings are put back after every step and fully restored at the end.
@MainActor @Observable
final class CheckRunner {
    static let shared = CheckRunner(model: AppModel.shared)
    /// macOS virtual key code of F18 (side button 4 is remapped to it in the buttons step).
    static let f18KeyCode: UInt16 = 79

    enum Phase: Equatable {
        case idle
        case preflight
        case instructions(String, actionTitle: String)
        case working(String)
        case question(String)
        case measure(String, seconds: Double)
        case keyPress(String)
        case waiting(String, until: Date)
        case restoring
        case results
    }

    enum Input: Equatable {
        case proceed, yes, no, key, timeout
        case timestamps([Double])
    }

    struct Skipped: Error {}
    struct Cancelled: Error {}
    struct StepFailure: Error { let message: String }

    private(set) var phase: Phase = .idle
    /// Changes on every phase change; views use it as an identity so each capture box starts fresh.
    private(set) var phaseToken = 0
    private(set) var stepIndex = 0
    private(set) var outcomes: [CheckStepID: StepOutcome] = [:]
    private(set) var reportURL: URL?
    private(set) var reportMarkdown: String?
    var enteredPresets: [Int] = [400, 800, 1200, 2400, 3200]
    var enteredButtons = ButtonMapping()
    var useFactoryDefaults = false

    private let model: AppModel
    @ObservationIgnored private var input: CheckedContinuation<Input, Error>?
    @ObservationIgnored private var interrupt: Error?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var snapshot: RestoreSnapshot?
    @ObservationIgnored private var lastSnapshot: RestoreSnapshot?
    /// True once a test write reached (or may have reached) the mouse since the snapshot was taken. A snapshot read from
    /// disk after a crash counts as written. With no test write the restore only deletes the snapshot.
    @ObservationIgnored private var testWriteMade = true
    /// Number of `restoreAll()` calls in flight; `restoreIfInterrupted()` does not start another while one runs.
    @ObservationIgnored private var restoreDepth = 0
    /// A restore was asked for while another was in flight; retried when that one ends without finishing.
    @ObservationIgnored private var retryRestorePending = false

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool { runTask != nil }
    var needsRestore: Bool { snapshot != nil }
    private var isRestoring: Bool { restoreDepth > 0 }
    private var snapshotURL: URL { RestoreSnapshot.fileURL(in: model.settingsDirectory) }

    // MARK: Owner actions

    /// Welcome -> preflight. Prefills the owner's DPI presets and button remaps when MouseBar already stores them.
    func start() {
        guard runTask == nil, !isRestoring else { return }
        outcomes = [:]
        reportURL = nil
        reportMarkdown = nil
        stepIndex = 0
        Task {
            if let values = await model.activeSession?.currentValues {
                if case .dpiPresets(let presets, _)? = values["sensitivity"] { enteredPresets = presets }
                if case .buttons(let mapping)? = values["buttons_mapping"] { enteredButtons = mapping }
            }
            setPhase(.preflight)
        }
    }

    /// Back to a fresh welcome card (the window was closed or a new check starts). Does nothing while a check or a
    /// restore is in flight.
    func reset() {
        guard runTask == nil, !isRestoring else { return }
        outcomes = [:]
        reportURL = nil
        reportMarkdown = nil
        lastSnapshot = nil
        stepIndex = 0
        setPhase(.idle)
    }

    /// Preflight -> writes the restore snapshot, then runs every step.
    func beginTests() {
        guard runTask == nil, !isRestoring, let session = model.activeSession else { return }
        let useFactory = useFactoryDefaults
        var presets = enteredPresets
        var buttons = enteredButtons
        runTask = Task {
            let mouse = await session.mouse   // actor `let`s of another module are read with await
            if useFactory {
                if let spec = mouse.family.setting("sensitivity"),
                   case .dpiPresets(let factory, _)? = DefaultSettings.value(for: spec) {
                    presets = factory
                }
                buttons = ButtonMapping()
            }
            let stored = await session.currentValues
            let snap = RestoreSnapshot(
                mouse: mouse.model.mouse, stored: stored, dpiPresets: presets, buttons: buttons
            )
            do {
                try snap.write(to: snapshotURL)
            } catch {
                model.problem = "Could not save the restore snapshot: \(error)"
                setPhase(.idle)
                runTask = nil
                return
            }
            snapshot = snap
            lastSnapshot = snap
            testWriteMade = false
            outcomes = [.preflight: StepOutcome(step: .preflight, result: .pass, detail: "Settings snapshot saved")]
            model.setCheckRunning(true)
            await session.setPollInterval(.seconds(5))
            await runSteps(Array(CheckStepID.allCases.dropFirst()))
        }
    }

    /// Runs one step again (from the results screen), with the same snapshot and a full restore afterwards.
    func rerun(_ step: CheckStepID) {
        guard runTask == nil, !isRestoring, step != .preflight, let last = lastSnapshot, let session = model.activeSession else { return }
        runTask = Task {
            // Settings changed since the first run (DPI presets, button remaps, stored values) are what gets restored.
            var snap = last
            snap.stored = await session.currentValues
            if case .dpiPresets(let presets, _)? = snap.stored["sensitivity"] { snap.dpiPresets = presets }
            if case .buttons(let mapping)? = snap.stored["buttons_mapping"] { snap.buttons = mapping }
            lastSnapshot = snap
            do {
                try snap.write(to: snapshotURL)
            } catch {
                model.problem = "Could not save the restore snapshot: \(error)"
                runTask = nil
                return
            }
            snapshot = snap
            testWriteMade = false
            model.setCheckRunning(true)
            await session.setPollInterval(.seconds(5))
            await runSteps([step])
        }
    }

    func proceed() { resume(.success(.proceed)) }
    func answer(_ yes: Bool) { resume(.success(yes ? .yes : .no)) }
    func submit(timestamps: [Double]) { resume(.success(.timestamps(timestamps))) }
    func keyPressed() { resume(.success(.key)) }

    func skip() {
        if input != nil {
            resume(.failure(Skipped()))
        } else if runTask != nil {
            interrupt = Skipped()
        }
    }

    /// Stops the run (remaining steps are not run) and restores; before the run it just returns to the welcome card.
    func cancel() {
        if input != nil {
            resume(.failure(Cancelled()))
        } else if runTask != nil {
            interrupt = Cancelled()
        } else if phase == .preflight {
            setPhase(.idle)
        }
    }

    // MARK: Restore entry points

    /// At launch / connect / wake: a snapshot left by an interrupted check (crash, force quit) or kept by a restore that
    /// could not finish (mouse gone or asleep, a failed write) is restored. A snapshot already in memory is retried.
    func restoreIfInterrupted() async {
        guard runTask == nil else { return }
        guard !isRestoring else {
            retryRestorePending = true
            return
        }
        if snapshot == nil {
            guard let fromDisk = RestoreSnapshot.read(from: snapshotURL) else { return }
            snapshot = fromDisk
            testWriteMade = true   // left by an earlier process: assume the mouse was written
        }
        await restoreAll()
        if snapshot == nil {
            model.notice = "Restored your settings after an interrupted hardware check."
        }
        // A background restore never changes the card the owner is on (welcome, preflight, results).
        if phase == .restoring { setPhase(.idle) }
    }

    /// From the app delegate when quitting. A running check is cancelled and awaited: it undoes the step's test
    /// writes and restores in `runSteps`, so no later test write can land after the restore.
    func restoreForQuit() async {
        if runTask != nil {
            if input != nil { resume(.failure(Cancelled())) } else { interrupt = Cancelled() }
            await runTask?.value
        } else {
            await restoreAll()
        }
    }

    // MARK: Step sequencing

    private func runSteps(_ steps: [CheckStepID]) async {
        for step in steps {
            // A Cancel that arrived between steps stays pending until here; a late Skip belongs to no step.
            if interrupt is Cancelled { break }
            interrupt = nil
            stepIndex = CheckStepID.allCases.firstIndex(of: step) ?? 0
            var stop = false
            do {
                outcomes[step] = try await run(step)
            } catch is Skipped {
                outcomes[step] = StepOutcome(step: step, result: .skipped, detail: "Skipped")
            } catch is Cancelled {
                outcomes[step] = StepOutcome(step: step, result: .skipped, detail: "Cancelled")
                stop = true
            } catch let failure as StepFailure {
                outcomes[step] = StepOutcome(step: step, result: .fail, detail: failure.message)
            } catch {
                outcomes[step] = StepOutcome(step: step, result: .fail, detail: String(describing: error))
            }
            // Put this step's test values back even when it failed half-way.
            await undoTestWrites(of: step)
            if stop { break }
        }
        await restoreAll()
        writeReport()
        model.setCheckRunning(false)
        interrupt = nil   // a Cancel that arrived during the restore must not reach the next run
        runTask = nil
        setPhase(.results)
        // A restore kept because the mouse slept is retried now; a wake during the run could not trigger it.
        if snapshot != nil { Task { await restoreIfInterrupted() } }
    }

    private func run(_ step: CheckStepID) async throws -> StepOutcome {
        switch step {
        case .preflight: StepOutcome(step: .preflight, result: .pass, detail: "Settings snapshot saved")
        case .batteryCable: try await batteryStep(.batteryCable, wanted: .cable)
        case .batteryDongle: try await batteryStep(.batteryDongle, wanted: .dongle)
        case .ledColor: try await ledStep()
        case .pollingRate: try await pollingStep()
        case .buttons: try await buttonsStep()
        case .dpiPreset: try await dpiStep()
        case .savePersistence: try await saveStep()
        case .wakeReapply: try await wakeStep()
        }
    }

    // MARK: Steps

    private func batteryStep(_ id: CheckStepID, wanted: AppModel.ConnectionKind) async throws -> StepOutcome {
        let instruction = wanted == .cable
            ? "Connect the mouse with the USB cable."
            : "Plug in the 2.4 GHz dongle, then unplug the USB cable."
        guard try await waitFor(instruction, timeout: 120, { self.model.connection == wanted }) else {
            throw StepFailure(message: "The \(wanted.title) connection did not appear within 2 minutes.")
        }
        setPhase(.working("Reading the battery…"))
        try await Task.sleep(for: .seconds(1))   // let a freshly switched session finish re-applying settings
        let session = try activeSession()
        let family = await session.mouse.family
        guard let battery = family.battery, let command = battery.command.first.map(UInt8.init) else {
            throw StepFailure(message: "This mouse profile has no battery query.")
        }
        guard let reply = try await session.rawBatteryQuery() else {
            throw StepFailure(message: "No reply within 200 ms. Move the mouse to wake it, then run this step again.")
        }
        let hex = HexFormat.string(reply)
        let first = reply.first.map { String(format: "0x%02X", $0) } ?? "none"
        let echoes = reply.first == command
        let echoText = echoes
            ? "byte 0 = \(first) (echoes the command)"
            : "byte 0 = \(first), command was \(String(format: "0x%02X", command))"
        guard let reading = BatteryDecoder.decode(decoder: battery.decoder, reply: reply) else {
            return StepOutcome(step: id, result: .fail, detail: "Not a valid battery reading; \(echoText)", rawHex: hex)
        }
        let level = "\(reading.level)%\(reading.isCharging ? ", charging" : "")"
        // The cable must echo (verified behavior); the dongle's echo is recorded to decide the dongle filter later.
        let pass = wanted == .cable ? echoes : true
        return StepOutcome(step: id, result: pass ? .pass : .fail, detail: "\(level); \(echoText)", rawHex: hex)
    }

    private func ledStep() async throws -> StepOutcome {
        try await waitForProceed("The check turns the LED blue, then green.", actionTitle: "Turn LED blue")
        let session = try activeSession()
        try await testWrite(session, "color", .color(MouseCore.RGBColor(r: 0, g: 0, b: 255)))
        let blue = try await ask("Is the mouse LED blue?")
        try await testWrite(session, "color", .color(MouseCore.RGBColor(r: 0, g: 255, b: 0)))
        let green = try await ask("Is the mouse LED green now?")
        return StepOutcome(
            step: .ledColor, result: blue && green ? .pass : .fail,
            detail: "Blue: \(yesNo(blue)); green: \(yesNo(green))"
        )
    }

    private func pollingStep() async throws -> StepOutcome {
        try await waitForProceed("The check sets the polling rate to 125 Hz, then 1000 Hz.", actionTitle: "Start")
        let session = try activeSession()
        try await testWrite(session, "polling_rate", .choice("125"))
        let slow = try await measure("Polling rate is 125 Hz. Move the mouse in circles inside the box for 3 seconds.")
        try await testWrite(session, "polling_rate", .choice("1000"))
        let fast = try await measure("Polling rate is 1000 Hz. Move the mouse in circles inside the box again.")
        guard let slow, let fast else {
            throw StepFailure(message: "Not enough mouse movement was captured. Run this step again and keep moving the mouse.")
        }
        return StepOutcome(
            step: .pollingRate, result: fast >= slow * 3 ? .pass : .fail,
            detail: String(format: "125 Hz: %.0f events/s; 1000 Hz: %.0f events/s", slow, fast),
            measurements: ["rate125": slow, "rate1000": fast]
        )
    }

    private func buttonsStep() async throws -> StepOutcome {
        try await waitForProceed("The check maps side button 4 to F18.", actionTitle: "Map button")
        let session = try activeSession()
        guard let snap = snapshot else { throw StepFailure(message: "No restore snapshot.") }
        var assignments = snap.buttons.assignments
        assignments["button4"] = "f18"
        try await testWrite(session, "buttons_mapping", .buttons(ButtonMapping(assignments: assignments)))
        let pressed = try await waitKey(
            "Side button 4 now types F18. Keep the pointer inside the box and press side button 4.", timeout: 15
        )
        // Back to the owner's map before the rejection test.
        try await testWrite(session, "buttons_mapping", .buttons(snap.buttons))
        // Validation must refuse a map without a left click before anything is written.
        var rejected = false
        do {
            try await testWrite(
                session, "buttons_mapping", .buttons(ButtonMapping(assignments: ["button1": "disabled"]))
            )
        } catch MouseCoreError.noPrimaryClick {
            rejected = true
        }
        if !rejected {
            // The write went through: undo it at once.
            try await testWrite(session, "buttons_mapping", .buttons(snap.buttons))
        }
        try await waitForProceed(
            "Click Continue with the left mouse button to confirm left click still works.", actionTitle: "Continue"
        )
        return StepOutcome(
            step: .buttons, result: pressed && rejected ? .pass : .fail,
            detail: "F18 from side button 4: \(yesNo(pressed)); map without a left click refused: \(yesNo(rejected))"
        )
    }

    private func dpiStep() async throws -> StepOutcome {
        try await waitForProceed(
            "The check writes two DPI presets, 400 and 3200, and switches between them.", actionTitle: "Write presets"
        )
        let session = try activeSession()
        try await testWrite(session, "sensitivity", .dpiPresets(presets: [400, 3200], selected: 0))
        let slow = try await ask("Preset 1 (400 DPI) is active. Move the mouse: is the pointer slow?")
        try await testWrite(session, "sensitivity", .dpiPresets(presets: [400, 3200], selected: 1))
        let fast = try await ask("Preset 2 (3200 DPI) is active. Is the pointer much faster now?")
        let pass = slow && fast
        model.setActivePresetConfirmed(pass)
        return StepOutcome(
            step: .dpiPreset, result: pass ? .pass : .fail,
            detail: "Slow at preset 1: \(yesNo(slow)); fast at preset 2: \(yesNo(fast))"
        )
    }

    private func saveStep() async throws -> StepOutcome {
        try await waitForProceed(
            "The check turns the startup lighting off and saves it to the mouse.", actionTitle: "Save to mouse"
        )
        let session = try activeSession()
        try await testWrite(session, "default_lighting", .choice("off"))
        try await session.saveNow()
        let stayedOff = try await ask(
            "Unplug the USB cable if it is connected, switch the mouse off and on, and watch the LED as it starts. "
                + "Did the LED stay off at startup?"
        )
        return StepOutcome(
            step: .savePersistence, result: stayedOff ? .pass : .fail,
            detail: "LED stayed off after the power cycle: \(yesNo(stayedOff))"
        )
    }

    private func wakeStep() async throws -> StepOutcome {
        guard try await waitFor(
            "This step needs the dongle: unplug the USB cable and use the 2.4 GHz dongle.",
            timeout: 120, { self.model.connection == .dongle }
        ) else {
            throw StepFailure(message: "The dongle connection did not appear within 2 minutes.")
        }
        guard model.values["color"] != nil else {
            return StepOutcome(
                step: .wakeReapply, result: .skipped,
                detail: "No LED color is stored. Pick one in Settings → Lighting, then run this step again."
            )
        }
        guard try await waitFor(
            "Switch the mouse off and wait until this changes.", timeout: 120,
            { self.model.battery.freshness == .asleep }
        ) else {
            throw StepFailure(message: "The mouse was not seen asleep within 2 minutes.")
        }
        guard try await waitFor(
            "The mouse is asleep. Now switch it on and move it.", timeout: 120,
            { self.model.battery.freshness == .fresh }
        ) else {
            throw StepFailure(message: "The mouse did not answer again within 2 minutes.")
        }
        let back = try await ask("Is your LED color back?")
        return StepOutcome(step: .wakeReapply, result: back ? .pass : .fail, detail: "Color came back: \(yesNo(back))")
    }

    // MARK: Undo and restore

    private static let stepKeys: [CheckStepID: [String]] = [
        .ledColor: ["color"],
        .pollingRate: ["polling_rate"],
        .buttons: ["buttons_mapping"],
        .dpiPreset: ["sensitivity"],
        .savePersistence: ["default_lighting"],
    ]

    /// A transient test write. The flag is set before the write: a throw may still have reached the mouse.
    private func testWrite(_ session: MouseSession, _ key: String, _ value: SettingValue) async throws {
        testWriteMade = true
        try await session.applyTransient(key, value)
    }

    /// Best effort: re-sends the owner's value for every key the step tested (not stored; saved to the mouse only for the save step).
    private func undoTestWrites(of step: CheckStepID) async {
        guard testWriteMade, let keys = Self.stepKeys[step], let snap = snapshot, let session = model.activeSession else { return }
        let family = await session.mouse.family
        let writes = snap.restoreWrites(family: family).filter { keys.contains($0.key) }
        for write in writes {
            try? await session.applyTransient(write.key, write.value)
        }
        // The save step wrote the test value to the mouse's memory: put the owner's value there too.
        if step == .savePersistence { try? await session.saveNow() }
    }

    /// Writes (and stores) every restore value, saves to the mouse, resets the poll interval, then deletes the
    /// snapshot. Keeps the snapshot when anything failed or the mouse is gone, so a later connect retries.
    private func restoreAll() async {
        guard snapshot != nil else { return }
        restoreDepth += 1
        await restoreOnce()
        restoreDepth -= 1
        // Another restore was asked for meanwhile (for example a new connection) and this one did not finish.
        if retryRestorePending {
            retryRestorePending = false
            if snapshot != nil { await restoreIfInterrupted() }
        }
    }

    /// True when the mouse answers a battery query with a reply that decodes. A sleeping dongle mouse does not, and
    /// drops writes and saves; a stray report from another program does not decode either.
    private func mouseAnswers(_ session: MouseSession) async -> Bool {
        guard let battery = await session.mouse.family.battery else { return true }   // nothing to probe with
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(500)) }
            if let reply = try? await session.rawBatteryQuery(),
               BatteryDecoder.decode(decoder: battery.decoder, reply: reply) != nil {
                return true
            }
        }
        return false
    }

    private func restoreOnce() async {
        guard let snap = snapshot else { return }
        if !testWriteMade {
            // Nothing was written to the mouse: there is nothing to put back. Only the poll interval needs resetting.
            do {
                if FileManager.default.fileExists(atPath: snapshotURL.path) {
                    try FileManager.default.removeItem(at: snapshotURL)
                }
                snapshot = nil
            } catch {
                model.problem = "Some settings could not be restored: snapshot: \(error)"
            }
            await model.activeSession?.setPollInterval(.seconds(60))
            return
        }
        if runTask != nil { setPhase(.restoring) }   // only a running check shows the restoring card
        guard let session = model.activeSession, await session.mouse.model.mouse == snap.mouse else {
            model.notice = "Your settings will be restored when the mouse reconnects."
            return
        }
        // A sleeping dongle mouse drops writes and a save: keep the snapshot until it answers again. At launch the
        // battery state is still "connecting", so the state alone is not enough: probe the mouse before any write.
        guard model.battery.freshness != .asleep, await mouseAnswers(session) else {
            model.notice = "Your settings will be restored when the mouse wakes."
            return
        }
        var failures: [String] = []
        let family = await session.mouse.family
        for write in snap.restoreWrites(family: family) {
            do {
                // Only values MouseBar stored before (or the owner entered here) are remembered again; the rest
                // go to the mouse alone, so a setting never stored does not turn into a stored factory default.
                if snap.storesValue(for: write.key, family: family) {
                    try await session.set(write.key, write.value)
                } else {
                    try await session.applyTransient(write.key, write.value)
                }
            } catch {
                failures.append("\(write.key): \(error)")
            }
        }
        do {
            try await session.saveNow()
        } catch {
            failures.append("save: \(error)")
        }
        await session.setPollInterval(.seconds(60))
        await model.refreshValues()
        if failures.isEmpty, FileManager.default.fileExists(atPath: snapshotURL.path) {
            do {
                try FileManager.default.removeItem(at: snapshotURL)
            } catch {
                failures.append("snapshot: \(error)")
            }
        }
        if failures.isEmpty {
            snapshot = nil
        } else {
            model.problem = "Some settings could not be restored: \(failures.joined(separator: "; "))"
        }
    }

    private func writeReport() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let report = CheckReport(
            date: Date(), appVersion: version, mouseModel: model.displayName ?? "unknown",
            outcomes: CheckStepID.allCases.compactMap { outcomes[$0] }
        )
        let markdown = report.markdown()
        reportMarkdown = markdown
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = model.settingsDirectory.appendingPathComponent("reports", isDirectory: true)
        let url = directory.appendingPathComponent("hardware-check-\(formatter.string(from: Date())).md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            reportURL = url
        } catch {
            model.problem = "Could not write the report: \(error)"
        }
    }

    // MARK: Waiting primitives

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        phaseToken += 1
    }

    /// Throws a pending Skip/Cancel. A Cancel stays pending (only `runSteps` clears it) so nothing can swallow it.
    private func checkpoint() throws {
        guard let pending = interrupt else { return }
        if pending is Skipped { interrupt = nil }
        throw pending
    }

    /// The live session; a checkpoint first, so every step that writes stops on Cancel/Skip before its first write.
    /// Once the snapshot exists, only the checked mouse qualifies: its test writes must never reach a fallback mouse
    /// that became active after the checked one went away. (`activeMouseID` always belongs to `activeSession`.)
    private func activeSession() throws -> MouseSession {
        try checkpoint()
        guard let session = model.activeSession else { throw StepFailure(message: "No mouse connected.") }
        if let checked = snapshot?.mouse, model.activeMouseID != checked {
            throw StepFailure(message: "The checked mouse is not connected.")
        }
        return session
    }

    private func resume(_ result: Result<Input, Error>) {
        let pending = input
        input = nil
        pending?.resume(with: result)
    }

    private func waitForInput(_ phase: Phase) async throws -> Input {
        try checkpoint()
        setPhase(phase)
        return try await withCheckedThrowingContinuation { input = $0 }
    }

    private func waitForProceed(_ text: String, actionTitle: String) async throws {
        _ = try await waitForInput(.instructions(text, actionTitle: actionTitle))
    }

    private func ask(_ question: String) async throws -> Bool {
        try await waitForInput(.question(question)) == .yes
    }

    private func measure(_ text: String) async throws -> Double? {
        let timer = timeout(after: 30, resuming: .timestamps([]))   // no box capture at all: counts as no data
        defer { timer.cancel() }
        guard case .timestamps(let timestamps) = try await waitForInput(.measure(text, seconds: 3)) else { return nil }
        return PollingRateEstimator.rate(timestamps: timestamps)
    }

    private func waitKey(_ text: String, timeout seconds: Double) async throws -> Bool {
        let timer = timeout(after: seconds, resuming: .timeout)
        defer { timer.cancel() }
        return try await waitForInput(.keyPress(text)) == .key
    }

    /// Resumes the next wait with `input` after `seconds`, unless that wait already ended (the phase token moved on).
    /// Call it right before `waitForInput`, and cancel the returned task when the wait ends.
    private func timeout(after seconds: Double, resuming input: Input) -> Task<Void, Never> {
        let token = phaseToken + 1   // the token setPhase assigns for the wait
        return Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.phaseToken == token else { return }
            self.resume(.success(input))
        }
    }

    /// Polls `condition` every 0.5 s until it holds (true) or the timeout passes (false). Skip/Cancel interrupt it.
    private func waitFor(_ text: String, timeout: TimeInterval, _ condition: () -> Bool) async throws -> Bool {
        if condition() { return true }
        let deadline = Date().addingTimeInterval(timeout)
        setPhase(.waiting(text, until: deadline))
        while Date() < deadline {
            try checkpoint()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
