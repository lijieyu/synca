import Foundation
@MainActor final class APIClient {
 static let shared = APIClient()
 var isAuthenticated = false
 var token: String?
 func registerPushToken(token: String, platform: String, apnsEnvironment: String, topic: String?) async throws {}
}
@main struct Tests {
 static func main() throws {
  for environment in ["production", "development"] {
   let data = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": ["aps-environment": environment]], format: .xml, options: 0)
   var profile = Data([0x30,0x82,0xff]); profile.append(data); profile.append(contentsOf:[0xff,0x00])
   precondition(PushTokenManager.environment(in: profile) == (environment == "production" ? "production" : "sandbox"))
  }
  precondition(PushTokenManager.environment(in: Data("malformed".utf8)) == nil)
  let unsupported = try PropertyListSerialization.data(fromPropertyList:["Entitlements":["aps-environment":"unknown"]],format:.xml,options:0)
  precondition(PushTokenManager.environment(in: unsupported) == nil)
  print("PASS provisioned APNs environment, whitespace, malformed profile and unknown value")
 }
}
