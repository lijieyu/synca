#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dwmapi.h>
#include <cstdio>

// Visible rectangles in native front-to-back order; no window titles or content.
static BOOL CALLBACK collect(HWND window, LPARAM context) {
    if (window == GetShellWindow() || !IsWindowVisible(window) || IsIconic(window)) return TRUE;
    DWORD cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) && cloaked) return TRUE;
    RECT bounds{};
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &bounds, sizeof(bounds)))) return TRUE;
    const LONG width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
    if (width <= 20 || height <= 20) return TRUE;
    auto& first = *reinterpret_cast<bool*>(context);
    std::printf("%s{\"x\":%ld,\"y\":%ld,\"width\":%ld,\"height\":%ld}", first ? "" : ",", bounds.left, bounds.top, width, height);
    first = false;
    return TRUE;
}

int main() {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    bool first = true;
    std::fputs("[", stdout);
    if (!EnumWindows(collect, reinterpret_cast<LPARAM>(&first))) return 1;
    std::puts("]");
    return std::ferror(stdout) ? 1 : 0;
}
