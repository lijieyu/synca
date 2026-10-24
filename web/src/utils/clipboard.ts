import { api } from '../api/client';

async function imageAsPNG(url: string, expiresAt?: string | null): Promise<Blob> {
  const blob = await api.getProtectedFileBlob(url, { expiresAt, cacheImage: true });
  if (blob.type === 'image/png') return blob;
  const objectURL = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.src = objectURL;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const context = canvas.getContext('2d');
    if (!context || !canvas.width || !canvas.height) throw new Error('Unsupported image');
    context.drawImage(image, 0, 0);
    return await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Image conversion failed')), 'image/png'));
  } finally { URL.revokeObjectURL(objectURL); }
}

export async function copyProtectedImage(url: string, expiresAt?: string | null): Promise<void> {
  if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') throw new Error('Image clipboard is not supported');
  // Start clipboard.write during the user gesture, including on Safari; resolve the authenticated image asynchronously.
  const image = imageAsPNG(url, expiresAt);
  void image.catch(() => {}); // A denied clipboard request can finish before the image request.
  await navigator.clipboard.write([new ClipboardItem({ 'image/png': image })]);
}
