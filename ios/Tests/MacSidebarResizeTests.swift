import AppKit
@main struct ResizeTests {
 @MainActor static func main() {
  _ = NSApplication.shared
  var begins = 0, ends = 0, resets = 0
  var delta: CGFloat = 0
  var hovering = false
  let view = MacSidebarResizeHandle.HandleView(callbacks: .init(onBegin: { begins += 1 }, onDrag: { delta = $0 }, onEnd: { ends += 1 }, onReset: { resets += 1 }, onHover: { hovering = $0 }))
  func event(_ x: CGFloat, _ clicks: Int = 1) -> NSEvent {
   NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: 100), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
  }
  view.mouseEntered(with: event(220)); assert(hovering)
  for _ in 0..<20 { view.cursorUpdate(with: event(220)); assert(NSCursor.current == NSCursor.resizeLeftRight) }
  view.mouseDown(with: event(220)); view.mouseDragged(with: event(300)); assert(begins == 1 && delta == 80)
  view.mouseExited(with: event(300)); assert(!hovering)
  view.mouseDragged(with: event(350)); assert(delta == 130)
  view.mouseUp(with: event(350)); assert(ends == 1)
  view.mouseDown(with: event(350, 2)); view.mouseUp(with: event(350, 2)); assert(resets == 1 && ends == 1)
  print("PASS: repeated native cursor updates, enter/exit, window-relative drag, release and double-click reset")
 }
}
