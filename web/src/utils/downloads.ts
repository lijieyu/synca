// Directory handles stay in memory: a reload honestly returns to browser-managed downloads.
interface DownloadDirectory {
  name: string;
  getFileHandle(name: string, options: { create: boolean }): Promise<{ createWritable(): Promise<{ write(blob: Blob): Promise<void>; close(): Promise<void>; abort(): Promise<void> }> }>;
}
type DirectoryWindow = Window & { showDirectoryPicker?: (options: { mode: 'readwrite' }) => Promise<DownloadDirectory> };
let directory: DownloadDirectory | null = null;
export const supportsDownloadDirectory = () => typeof (window as DirectoryWindow).showDirectoryPicker === 'function';
export const downloadDirectoryName = () => directory?.name ?? null;
export const resetDownloadDirectory = () => { directory = null; };
export async function chooseDownloadDirectory() {
  const picker = (window as DirectoryWindow).showDirectoryPicker;
  if (!picker) return;
  directory = await picker.call(window, { mode: 'readwrite' });
}
// Serialize the existence check through close, so two attachment rows cannot claim the same name.
let downloadQueue: Promise<void> = Promise.resolve();
export function saveDownload(blob: Blob, fileName: string): Promise<void> {
  const selectedDirectory = directory;
  const operation = downloadQueue.then(() => performDownload(blob, fileName, selectedDirectory));
  downloadQueue = operation.catch(() => undefined);
  return operation;
}
async function performDownload(blob: Blob, fileName: string, target: DownloadDirectory | null) {
  const safeName = Array.from(fileName, character =>
    character.charCodeAt(0) < 32 || character === '/' || character === '\\' ? '_' : character
  ).join('') || 'attachment';
  if (target) {
    try {
      // Avoid silently replacing an existing attachment.
      const dot = safeName.lastIndexOf('.');
      const stem = dot > 0 ? safeName.slice(0, dot) : safeName;
      const extension = dot > 0 ? safeName.slice(dot) : '';
      let candidate = safeName;
      for (let index = 1; ; index++) {
        try { await target.getFileHandle(candidate, { create: false }); candidate = `${stem} (${index})${extension}`; }
        catch (error) { if (error instanceof DOMException && error.name === 'NotFoundError') break; throw error; }
      }
      const handle = await target.getFileHandle(candidate, { create: true });
      const writable = await handle.createWritable();
      try { await writable.write(blob); await writable.close(); }
      catch (error) { await writable.abort().catch(() => undefined); throw error; }
      return;
    } catch { if (directory === target) directory = null; /* Permissions/storage failures use the browser's normal download. */ }
  }
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url; anchor.download = safeName;
  document.body.appendChild(anchor); anchor.click(); anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
