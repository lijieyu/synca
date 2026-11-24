from pathlib import Path
import shutil, json, subprocess, sys
root=Path(__file__).resolve().parents[3]; dst=Path(sys.argv[1]).resolve(); src=root/'ios/Synca'
tests=Path(__file__).resolve().parent
integration='--integration' in sys.argv[2:]
shutil.copytree(src,dst,ignore=shutil.ignore_patterns('*.log','xcuserdata','.DS_Store'))
def edit(f,a,b):
 p=dst/f;s=p.read_text();assert a in s,(f,a[:80]);p.write_text(s.replace(a,b))
edit('Shared/App/SyncaApp.swift','    #if os(iOS)\n    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate','    #if os(iOS)\n    // Isolated visual fixture has no APNs registration.')
(dst/'Shared/Core/KeychainHelper.swift').write_text('import Foundation\nenum KeychainHelper { static func load(key: String) -> String? { nil }; static func save(key: String, value: String) {}; static func delete(key: String) {} }')
edit('Shared/Core/APIClient.swift','self.token = KeychainHelper.load(key: "authToken")','self.token = "visual-fixture"')
edit('Shared/Core/APIClient.swift','self.currentUserId = UserDefaults.standard.string(forKey: currentUserIdKey)','self.currentUserId = "visual-fixture"')
edit('Shared/Core/APIClient.swift','self.currentUserEmail = UserDefaults.standard.string(forKey: currentUserEmailKey)','self.currentUserEmail = "alex@example.com"')
edit('Shared/Core/APIClient.swift','self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://127.0.0.1:3000"','self.baseURL = "http://127.0.0.1:54671"')
edit('Shared/Core/PurchaseManager.swift','updatesTask = observeTransactionUpdates()','// No StoreKit observation in visual fixture')
edit('Shared/Core/PurchaseManager.swift','func loadProducts() async {','func loadProducts() async { if ProcessInfo.processInfo.arguments.contains("-qa-products-unavailable") { return };')
edit('Shared/Core/AccessManager.swift','func refresh() async -> Bool {','func refresh() async -> Bool { return true;')
edit('Shared/Core/AccessManager.swift','private init() {}','private init() { status = AccessStatus(storage: StorageAllowance(usedBytes: 25165824, limitBytes: 104857600, imageLimitBytes: 52428800, fileLimitBytes: 209715200, retentionDays: 3, canUploadFiles: false), plan: "free", isUnlimited: false, isTrial: false, unlimitedSource: nil, trialEndsAt: nil, daysLeft: nil, todayUsed: 7, todayLimit: 20, dailyResetAt: "2026-11-25T00:00:00Z", purchaseDate: nil, subscriptionExpiresAt: nil, storeProductId: nil, lifetimeUpgradeOffer: nil) }')
now='2026-11-24T05:30:00.000Z'
cats=[dict(id=str(i),userId='visual-fixture',name=n,color=c,isDefault=i==0,sortOrder=i,createdAt=now,updatedAt=now) for i,(n,c) in enumerate([('默认','slate'),('工作','sky'),('生活','mint'),('灵感','violet')])]
msgs=[dict(id=str(i),userId='visual-fixture',type='text',textContent=t,categoryId=str(c),categoryName=cats[c]['name'],categoryColor=cats[c]['color'],categoryIsDefault=c==0,isCleared=False,isDeleted=False,sourceDevice='iPhone',createdAt=now,updatedAt=now) for i,(t,c) in enumerate([('把零散的想法，留在一个地方。\nhttps://example.com',0),('周末去看新展览，记得提前预约。',2),('下一版：让记录和整理，都更轻松。',3)])]
# Optional image-heavy feed uses only deterministic loopback attachments.
if '--images' in sys.argv[2:]:
 msgs=[dict(id=str(i),userId='visual-fixture',type='image',imageUrl='http://127.0.0.1:54671/image/'+str(i)+'.png',categoryId='1',categoryName='工作',categoryColor='sky',categoryIsDefault=False,isCleared=False,isDeleted=False,sourceDevice='iPhone',createdAt=now,updatedAt=now) for i in range(6)]
seed='private init() { categories = try! JSONDecoder().decode([SyncaMessageCategory].self, from: Data(#"'+json.dumps(cats,ensure_ascii=False)+'"#.utf8)); messages = try! JSONDecoder().decode([SyncaMessage].self, from: Data(#"'+json.dumps(msgs,ensure_ascii=False)+'"#.utf8)); hasCompletedInitialLoad = true; unclearedCount = '+str(len(msgs))+'; selectedCategoryId = "__all__" }'
edit('Shared/Core/SyncManager.swift','private init() {}',seed)
edit('Shared/Core/SyncManager.swift','func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async -> Bool {','func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async -> Bool { return true;')
edit('Shared/Core/SyncManager.swift','func startPolling() {','func startPolling() { return;')
# Every HTTP path, including AI, points only at a loopback test service.
for p in dst.rglob('*.swift'):
 s=p.read_text().replace('https://synca.haerth.cn','http://127.0.0.1:54671');p.write_text(s)
p=dst/'project.yml';s=p.read_text().replace('org.haerth.synca','org.haerth.synca.iospolishqa');s=s.replace('schemes:\n','  PolishUITests:\n    type: bundle.ui-testing\n    platform: iOS\n    sources: [UITests]\n    dependencies:\n      - target: Synca\n    settings:\n      base:\n        TEST_TARGET_NAME: Synca\n        GENERATE_INFOPLIST_FILE: YES\nschemes:\n');s=s.replace('    test:\n      config: Production','    test:\n      config: Production\n      targets: [PolishUITests]',1);p.write_text(s)
(dst/'UITests').mkdir();shutil.copy(tests/'PolishTests.swift',dst/'UITests/PolishTests.swift')
shutil.copy(tests/'UpgradePreview.storekit',dst/'UITests/UpgradePreview.storekit')
if integration:
 for name in ['SyncManager.swift','AccessManager.swift']: shutil.copy(src/'Shared/Core'/name,dst/'Shared/Core'/name)
 (dst/'Shared/App/SyncaApp.swift').write_text('import SwiftUI\n@main struct SyncaApp: App { var body: some Scene { WindowGroup { Text("Isolated sync verification") } } }')
 shutil.rmtree(dst/'UITests'); (dst/'IntegrationTests').mkdir()
 shutil.copy(tests/'SyncIntegrationTests.swift',dst/'IntegrationTests/SyncIntegrationTests.swift')
 shutil.copy(tests/'EmailAuthTests.swift',dst/'IntegrationTests/EmailAuthTests.swift')
 # Force a session switch during the StoreKit await, without adding test hooks to product code.
 edit('Shared/Core/PurchaseManager.swift','await Transaction.latest(for: productID)','await PurchaseSessionFixture.latest(for: productID)')
 (dst/'Shared/Core/PurchaseSessionFixture.swift').write_text('import StoreKit\n@MainActor enum PurchaseSessionFixture { static var switchSession = false; static func latest(for productID: String) async -> VerificationResult<Transaction>? { if switchSession { switchSession = false; APIClient.shared.setToken("next-session", userId: "next-user") }; return nil } }')
 p=dst/'project.yml';s=p.read_text().replace('PolishUITests','SyncIntegrationTests').replace('type: bundle.ui-testing','type: bundle.unit-test').replace('sources: [UITests]','sources: [IntegrationTests]').replace('TEST_TARGET_NAME: Synca','SWIFT_VERSION: 5.0');p.write_text(s)
else:
 # Permit only the loopback fixture origin, never a real account or external HTTP.
 edit('Shared/Core/EmbeddedAISession.swift','url.scheme?.lowercased() == "https"','url.scheme?.lowercased() == "http"')
 edit('Shared/Core/EmbeddedAISession.swift','url.host?.lowercased() == "synca.haerth.cn"','url.host?.lowercased() == "127.0.0.1"')
 edit('Shared/Core/EmbeddedAISession.swift','(url.port == nil || url.port == 443)','url.port == 54671')
 edit('Shared/Views/AIConnectionView.swift','if scheme == "https", url.user == nil','if scheme == "http", url.host == "127.0.0.1", url.port == 54671, url.user == nil')
if '--email' in sys.argv[2:]:
 edit('Shared/Core/APIClient.swift','self.token = "visual-fixture"','self.token = ProcessInfo.processInfo.arguments.contains("-qa-signed-out") ? nil : "visual-fixture"')
 shutil.copy(tests/'EmailUITests.swift',dst/'UITests/EmailUITests.swift')
(dst/'fixture-records.json').write_text(json.dumps(msgs,ensure_ascii=False))
subprocess.run(['xcodegen','generate'],cwd=dst,check=True)
