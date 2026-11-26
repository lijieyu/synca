Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class SyncaWindows {
 public struct Rect { public int Left,Top,Right,Bottom; }
 public delegate bool Callback(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback c,IntPtr p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int a,out Rect r,int s);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int a,out int r,int s);
 public class Window { public int x,y,width,height; public uint pid; }
 public static List<Window> Read() {
  var result=new List<Window>();
  EnumWindows((h,p)=>{
   if(h==GetShellWindow()||!IsWindowVisible(h)||IsIconic(h))return true;
   int cloaked; if(DwmGetWindowAttribute(h,14,out cloaked,4)==0&&cloaked!=0)return true;
   Rect r; if(DwmGetWindowAttribute(h,9,out r,Marshal.SizeOf(typeof(Rect)))!=0)return true;
   uint pid; GetWindowThreadProcessId(h,out pid);
   if(r.Right-r.Left>20&&r.Bottom-r.Top>20)result.Add(new Window{x=r.Left,y=r.Top,width=r.Right-r.Left,height=r.Bottom-r.Top,pid=pid});
   return true;
  },IntPtr.Zero);
  return result;
 }
}
'@
ConvertTo-Json -InputObject @([SyncaWindows]::Read()) -Compress
