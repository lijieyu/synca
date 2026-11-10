from pathlib import Path
import shutil,json
import sys
src=Path(__file__).resolve().parents[2]/'Synca'
dst=Path(sys.argv[1]).resolve()
if dst.exists(): raise SystemExit('Use a new temporary destination for the isolated fixture')
shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('xcuserdata','.DS_Store'))
def edit(file,old,new,count=-1):
 p=dst/file;s=p.read_text();assert old in s,file;p.write_text(s.replace(old,new,count))
edit('Shared/App/SyncaApp.swift','    #if os(iOS)\n    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate\n    #elseif os(macOS)\n    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate\n    #endif','')
(dst/'Shared/Core/KeychainHelper.swift').write_text('import Foundation\nenum KeychainHelper { static func load(key: String) -> String? { nil }; static func save(key: String, value: String) {}; static func delete(key: String) {} }')
edit('Shared/Core/APIClient.swift','self.token = KeychainHelper.load(key: "authToken")','self.token = "visual-fixture"')
edit('Shared/Core/APIClient.swift','self.currentUserId = UserDefaults.standard.string(forKey: currentUserIdKey)','self.currentUserId = "visual-fixture"')
edit('Shared/Core/APIClient.swift','self.currentUserEmail = UserDefaults.standard.string(forKey: currentUserEmailKey)','self.currentUserEmail = "alex@example.com"')
edit('Shared/Core/APIClient.swift','self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://127.0.0.1:3000"','self.baseURL = "http://127.0.0.1:54671"')
edit('Shared/Core/PurchaseManager.swift','updatesTask = observeTransactionUpdates()','// Visual fixture: no StoreKit observer')
p=dst/'Shared/Views/MessageListView.swift';s=p.read_text();start=s.index('        .task {');end=s.index('        }\n',s.index('self.updateBadge()', start))+len('        }\n');s=s[:start]+s[end:];p.write_text(s)
now='2026-11-07T09:30:00.000Z'
categories=[dict(id=str(i),userId='visual-fixture',name=n,color=c,isDefault=i==0,sortOrder=i,createdAt=now,updatedAt=now) for i,(n,c) in enumerate([('默认','slate'),('工作','sky'),('生活','mint'),('灵感','violet')])]
messages=[dict(id=str(i),userId='visual-fixture',type='text',textContent=t,categoryId=str(c),categoryName=categories[c]['name'],categoryColor=categories[c]['color'],categoryIsDefault=c==0,isCleared=False,isDeleted=False,sourceDevice=d,createdAt=now,updatedAt=now) for i,(t,c,d) in enumerate([('把零散的想法，留在一个地方。',0,'iPhone'),('周末去看新展览，记得提前预约。',2,'MacBook Pro'),('下一版：让记录和整理，都更轻松。',3,'Web')])]
# Batch QA fixtures: generated local data only.
messages.append(dict(messages[0], id='qa-image', type='image', textContent=None, imageUrl='http://127.0.0.1:54671/logo.png', attachmentExpired=False, attachmentExpiresAt='2027-12-01T00:00:00Z'))
messages.append(dict(messages[0], id='qa-image-2', type='image', textContent=None, imageUrl='http://127.0.0.1:54671/logo.png', attachmentExpired=False))
messages.append(dict(messages[0], id='qa-long', textContent=('一万字记录验收：中文、English、表情 👨‍👩‍👧‍👦。\n' * 120), categoryId='1', categoryName='工作', categoryColor='sky', categoryIsDefault=False))
seed='private init() {\n categories = try! JSONDecoder().decode([SyncaMessageCategory].self, from: Data(#"'+json.dumps(categories,ensure_ascii=False)+'"#.utf8))\n messages = try! JSONDecoder().decode([SyncaMessage].self, from: Data(#"'+json.dumps(messages,ensure_ascii=False)+'"#.utf8))\n if ProcessInfo.processInfo.arguments.contains("--qa-images") { messages.removeAll { $0.id == "qa-long" } }\n if ProcessInfo.processInfo.arguments.contains("--qa-penultimate") { messages.append(try! JSONDecoder().decode(SyncaMessage.self, from: Data(#"{"id": "qa-tail", "userId": "visual-fixture", "type": "text", "textContent": "长文本后面的最后一条记录", "categoryId": "0", "categoryName": "默认", "categoryColor": "slate", "categoryIsDefault": true, "isCleared": false, "isDeleted": false, "sourceDevice": "MacBook Pro", "createdAt": "2026-11-07T09:30:00.000Z", "updatedAt": "2026-11-07T09:30:00.000Z"}"#.utf8))) }\n hasCompletedInitialLoad = true\n unclearedCount = 3\n selectedCategoryId = "__all__"\n }'
markdown_sample = "面试前的准备\n\n1. **整理经历**\n   - 选出两个最有代表性的项目\n   - 补上结果和自己的贡献\n2. **准备问题**\n   - 了解团队目前的工作方式\n   - 确认岗位最看重的能力\n\n> 先讲清楚，再补细节。\n\n资料统一放在 `面试准备` 文件夹。"
markdown_record = dict(messages[0], id='qa-markdown', textContent=markdown_sample)
seed = seed[:-1] + '\n if ProcessInfo.processInfo.arguments.contains("--qa-markdown") { messages = try! JSONDecoder().decode([SyncaMessage].self, from: Data(#"' + json.dumps([markdown_record], ensure_ascii=False) + '"#.utf8)) }\n }'
# Search navigation uses the real feed and a larger account-local synthetic dataset.
search_messages = [dict(messages[0], id=f'search-{i:03}', textContent=f'工作记录 {i}：跟进日常事项。', categoryId='1', categoryName='工作', categoryIsDefault=False, createdAt=f'2026-11-07T10:{i:02}:00.000Z', updatedAt=f'2026-11-07T10:{i:02}:00.000Z') for i in range(35)]
search_messages += [dict(messages[0], id='search-completed', textContent='面试已完成记录', categoryId='2', categoryName='生活', categoryIsDefault=False, isCleared=True),
                    dict(messages[0], id='search-long', textContent='面试长文定位\n' + ('长文本滚动测试。\n' * 180), categoryId='1', categoryName='工作', categoryIsDefault=False, createdAt='2026-11-08T10:00:00.000Z'),
                    dict(messages[0], id='search-image', type='image', textContent=None, fileName='面试照片.png', imageUrl='http://127.0.0.1:54671/logo.png', categoryId='1', categoryName='工作', categoryIsDefault=False, createdAt='2026-11-08T09:00:00.000Z')]
seed = seed[:-1] + '\n if ProcessInfo.processInfo.arguments.contains("--qa-search") { messages = try! JSONDecoder().decode([SyncaMessage].self, from: Data(#"' + json.dumps(search_messages, ensure_ascii=False) + '"#.utf8)); selectedCategoryId = "2" }\n }'
edit('Shared/Core/SyncManager.swift','private init() {}',seed)
edit('Shared/Core/AccessManager.swift','private init() {}','private init() { status = AccessStatus(plan: "free", isUnlimited: false, isTrial: false, unlimitedSource: nil, trialEndsAt: nil, daysLeft: nil, todayUsed: 7, todayLimit: 20, dailyResetAt: "2026-11-08T00:00:00Z", purchaseDate: nil, subscriptionExpiresAt: nil, storeProductId: nil, lifetimeUpgradeOffer: nil) }')
# UserDefaults remains isolated by bundle identifier; no live credentials or cache used.
edit('Shared/Core/SyncManager.swift', 'private init() {', 'private init() { UserDefaults.standard.set(0, forKey: "qaImageResets");', )
edit('Shared/Views/CachedAsyncImage.swift', '        phase = .empty', '        if case .success = phase { UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "qaImageResets") + 1, forKey: "qaImageResets") }\n        phase = .empty')
edit('Shared/Views/MessageListView.swift', 'struct MessageListView: View {', 'struct MessageListView: View {\n    @AppStorage("qaImageResets") private var qaImageResets = 0')
edit('Shared/Views/MessageListView.swift', 'Text("Synca")\n                    .font(.system(size: 17, weight: .semibold))', 'Text("Synca")\n                    .font(.system(size: 17, weight: .semibold)).accessibilityIdentifier("qa-image-resets").accessibilityValue(String(qaImageResets))',1)


edit('Shared/Core/SyncManager.swift', 'func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async {', 'func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async { return;')


# Count scroll-container mounts while switching categories (fixture only).
edit('Shared/Views/MessageListView.swift', 'struct MessageListView: View {', 'struct MessageListView: View {\n    @AppStorage("qaListMounts") private var qaListMounts = 0')
edit('Shared/Core/SyncManager.swift', 'private init() {', 'private init() { UserDefaults.standard.set(0, forKey: "qaListMounts");')
edit('Shared/Views/MessageListView.swift', '                .onAppear {\n                    #if os(iOS)\n                    if let target = collapsedRowTarget', '                .onAppear {\n                    qaListMounts += 1\n                    #if os(iOS)\n                    if let target = collapsedRowTarget')
edit('Shared/Views/MessageListView.swift', '        .onChange(of: syncManager.unclearedCount)', '        .overlay(alignment: .topTrailing) { Text(String(qaListMounts)).font(.caption2).accessibilityIdentifier("qa-list-mounts").allowsHitTesting(false) }\n        .onChange(of: syncManager.unclearedCount)',1)

# This fixture never reads the user's Keychain or contacts production.
# A deterministic tall PNG exercises async image geometry without network timing.
import struct,zlib,subprocess
w,h=320,700
raw=b''.join(b'\x00'+bytes([90,110,170])*w for _ in range(h))
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
(dst/'Resources/scroll-fixture.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
# Replace only transport, preserving production decode/cache/session behavior.
edit('Shared/Core/ImageCacheManager.swift',
     '        let data = try await loadData(for: url, authorizationToken: authorizationToken)',
     '        if ProcessInfo.processInfo.arguments.contains("--qa-search") { try await Task.sleep(nanoseconds: 8_000_000_000) }\n        let data = try Data(contentsOf: Bundle.main.url(forResource: "scroll-fixture", withExtension: "png")!)')
p=dst/'Shared/Views/MessageListView.swift';s=p.read_text().replace('@State private var showCreateCategory = false','@State private var showCreateCategory = ProcessInfo.processInfo.arguments.contains("--qa-new-category")')
s=s.replace('.id(message.listRowID)','.id(message.listRowID)\n        .accessibilityElement(children: .contain)\n        .accessibilityIdentifier("record-" + message.id)')
s=s.replace('.accessibilityLabel(Text(verbatim: AppLocalization.string(colorNameKey)))','.accessibilityLabel(Text(verbatim: AppLocalization.string(colorNameKey)))\n                    .accessibilityIdentifier("palette-" + preset.name)');p.write_text(s)
(dst/'UITests').mkdir();shutil.copy(Path(__file__).with_name('ScrollTests.swift'),dst/'UITests/ScrollTests.swift')
p=dst/'project.yml';s=p.read_text().replace('org.haerth.synca','org.haerth.synca.scrollqa')
s=s.replace('schemes:\n','  ScrollUITests:\n    type: bundle.ui-testing\n    platform: iOS\n    sources: [UITests]\n    dependencies:\n      - target: Synca\n    settings:\n      base:\n        TEST_TARGET_NAME: Synca\n        GENERATE_INFOPLIST_FILE: YES\nschemes:\n')
s=s.replace('    test:\n      config: Production','    test:\n      config: Production\n      targets: [ScrollUITests]',1);p.write_text(s)
subprocess.run(['xcodegen','generate'],cwd=dst,check=True)
print('Fixture ready:',dst)
