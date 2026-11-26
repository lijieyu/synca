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
  let blocks = ScratchBlock.parse("Before\n![](synca-image:01234567-0123-0123-0123-012345678901)\nAfter")
  precondition(blocks.count == 3 && blocks[1].imageID != nil && blocks[2].text.contains("After"))
  precondition(ScratchBlock.parse("![](https://example.com/tracker.png)").allSatisfy { $0.imageID == nil })
  print("PASS: in-flight typing, offline preservation, cache roundtrip and owned image parsing")
 }
}
