import Foundation

@main
struct EmbeddedAISessionTests {
    static func main() throws {
        precondition(EmbeddedAISession.isTrusted(URL(string: "https://synca.haerth.cn/ai?lng=en")!))
        for raw in ["http://synca.haerth.cn/ai", "https://synca.haerth.cn.evil.test/ai", "https://synca.haerth.cn:444/ai", "https://user:pass@synca.haerth.cn/ai", "file:///ai"] {
            precondition(!EmbeddedAISession.isTrusted(URL(string: raw)!))
        }
        let token = "test-token-\"'\\\n</script>"
        let script = EmbeddedAISession.bootstrap(token: token, email: "qa@example.invalid")
        let result: [String: String] = ["script": script, "token": token]
        print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    }
}
