import Foundation
@main struct AppVersionTests {
 static func main() {
  precondition(AppVersion.isNewer("1.10.0",than:"1.2.1"))
  precondition(!AppVersion.isNewer("1.2.0",than:"1.2.1"))
  precondition(!AppVersion.isNewer("1.2.1",than:"1.2.1"))
  for invalid in ["1.2.1-beta","01.2.2","1..2","-1.3.0","１２.３.４","999999999999999999999.0.0"] { precondition(!AppVersion.isNewer(invalid,than:"1.2.1")) }
  print("PASS: numeric release comparison rejects malformed and prerelease versions")
 }
}
