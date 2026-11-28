import Foundation
@main struct ScratchpadTests {
 static func main() throws {
  var draft = ScratchDraft(content:"typing",revision:1,dirty:true)
  draft.accept(sent:"sent",remote:ScratchDocument(content:"sent",revision:2))
  precondition(draft.content == "typing" && draft.dirty && draft.revision == 2)
  draft.receive(ScratchDocument(content:"remote",revision:3))
  precondition(draft.content == "typing" && draft.revision == 2)
  draft.accept(sent:"typing",remote:ScratchDocument(content:"typing",revision:3))
  precondition(!draft.dirty)
  let restored = try JSONDecoder().decode(ScratchDraft.self,from:JSONEncoder().encode(draft))
  precondition(restored.content == "typing" && restored.revision == 3)
  print("PASS: in-flight typing, offline preservation, cache roundtrip")
 }
}
