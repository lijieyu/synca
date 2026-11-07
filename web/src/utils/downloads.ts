// Downloads use the browser's configured destination and collision handling.
export async function saveDownload(blob: Blob, fileName: string): Promise<void> {
  const safeName = Array.from(fileName, character =>
    character.charCodeAt(0) < 32 || character === '/' || character === '\\' ? '_' : character
  ).join('') || 'attachment';
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url; anchor.download = safeName;
  document.body.appendChild(anchor); anchor.click(); anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
