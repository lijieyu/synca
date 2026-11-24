import Foundation
@main struct Tests {
 @MainActor static func main() async throws {
  let value = try JSONDecoder().decode(SyncServerState.self, from: Data(#"{"messages":"a","categories":"b","access":"c","latestMessage":null,"count":0}"#.utf8))
  precondition(value.count == 0)
  precondition(SyncServerState.overlap("2026-11-24T00:00:00.500Z") == "2026-11-23T23:59:59.500Z")
  var calls = 0
  let scheduler = SyncNotifications(request: URLRequest(url: URL(string:"https://example.invalid/sync/events")!), connect: false, retrySeconds: 0.01) {
   calls += 1
   return calls > 1
  }
  scheduler.start(); scheduler.hint(); scheduler.hint()
  try await Task.sleep(nanoseconds:100_000_000)
  precondition(calls == 2, "failed sync must retry; repeated hints coalesce")
  scheduler.stop();scheduler.hint()
  try await Task.sleep(nanoseconds:30_000_000)
  precondition(calls == 2, "stopped account cannot receive changes")
  print("PASS native sync scheduler, cancellation and cursor overlap")
 }
}
