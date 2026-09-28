import Foundation

@MainActor enum BrainRuntimeTests {
    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("conductor-runtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        func fixture(_ name: String, _ body: String) throws -> URL {
            let path = folder.appendingPathComponent(name + ".py")
            try ("#!/usr/bin/python3\nimport json,sys,time\n" + body).write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            return path
        }
        func configure(_ key: String, _ file: URL) {
            UserDefaults.standard.setVolatileDomain([key: file.path, "diagnosticsEnabled": false, "brainModel": "astra"], forName: UserDefaults.argumentDomain)
        }
        let active = try fixture("active", """
        def emit(x): print(json.dumps(x),flush=True)
        emit({'type':'thread.started','thread_id':'fixture-active'})
        for i in range(8):
            time.sleep(.25)
            emit({'type':'item.started','item':{'type':'reasoning','id':str(i)}})
        emit({'type':'item.completed','item':{'type':'agent_message','text':'{"say":"Fixture finished."}'}})
        emit({'type':'turn.completed','usage':{'input_tokens':12,'output_tokens':4}})
        """)
        configure("codexCLIPath", active)
        let busy = CodexBrain(choice: .astra)
        let answer = try await busy.plan("Fixture", image: nil, timeout: 1)
        precondition(answer.say == "Fixture finished.")
        print("PASS: active Codex work survives more than twice the old total deadline.")

        let continuity = try fixture("continuity", """
        def emit(x): print(json.dumps(x),flush=True)
        if 'resume' not in sys.argv:
            emit({'type':'thread.started','thread_id':'fixture-continuity'})
            time.sleep(5)
        else:
            assert 'fixture-continuity' in sys.argv
            emit({'type':'item.completed','item':{'type':'agent_message','text':'{"say":"Context retained."}'}})
        """)
        configure("codexCLIPath", continuity)
        let stalled = CodexBrain(choice: .astra)
        do { _ = try await stalled.plan("First", image: nil, timeout: 0.5); preconditionFailure("Silent fixture must time out") }
        catch { precondition(error.localizedDescription.contains("no activity")) }
        let resumed = try await stalled.plan("Second", image: nil, timeout: 1)
        precondition(resumed.say == "Context retained.")
        print("PASS: true inactivity fails honestly and the failed turn's conversation can resume.")

        let claude = try fixture("claude", """
        for line in sys.stdin:
            for i in range(8):
                time.sleep(.25)
                print(json.dumps({'type':'assistant','message':{'content':[{'type':'text','text':'Fixture activity'}]}}),flush=True)
            print(json.dumps({'type':'result','is_error':False,'result':'{"say":"Claude fixture finished."}'}),flush=True)
        """)
        configure("claudeCLIPath", claude)
        let claudeBrain = ClaudeBrain(choice: .opus)
        defer { claudeBrain.stop() }
        let claudeAnswer = try await claudeBrain.plan("Fixture", image: nil, timeout: 1)
        precondition(claudeAnswer.say == "Claude fixture finished.")
        print("PASS: active Claude work also survives the old total deadline.")

        let quota = try fixture("quota", """
        for line in sys.stdin:
            q=json.loads(line)
            if q.get('id')==1:
                print(json.dumps({'id':1,'result':{}}),flush=True)
            elif q.get('id')==2:
                assert q['method']=='account/rateLimits/read'
                print(json.dumps({'id':2,'result':{'rateLimits':{'primary':{'usedPercent':60,'windowDurationMins':300},'secondary':{'usedPercent':25,'windowDurationMins':10080}}}}),flush=True)
        """)
        let quotaResult = try await CodexAccount.read(binary: quota, timeout: 1)
        let summary = try CodexAccount.summary(quotaResult)
        precondition(summary.contains("40%") && summary.contains("75%"))
        do { _ = try CodexAccount.summary([:]); preconditionFailure("Missing usage cannot become zero") } catch { }
        print("PASS: direct account read computes remaining usage and preserves unavailable values.")

        configure("codexCLIPath", continuity)
        let cancelled = CodexBrain(choice: .astra)
        let start = Date()
        Task { try? await Task.sleep(nanoseconds: 500_000_000); cancelled.interrupt() }
        do { _ = try await cancelled.plan("Stop fixture", image: nil, timeout: 5); preconditionFailure("Stop must cancel") }
        catch { precondition(error is CancellationError) }
        precondition(Date().timeIntervalSince(start) < 2)
        print("PASS: Stop cancels the owned model process promptly. No model or paid API was called.")
    }
}
