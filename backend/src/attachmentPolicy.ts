import path from 'node:path';
export const allowedImageMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'image/gif'];
export const supportedDocumentMimeTypeByExtension: Record<string, string> = {
    pdf: 'application/pdf',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ppt: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    txt: 'text/plain',
    md: 'text/markdown',
    csv: 'text/csv',
    zip: 'application/zip',
};
const supportedDocumentExtensions = new Set(['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv', 'zip']);
const supportedDocumentMimeTypes = new Set([
    ...Object.values(supportedDocumentMimeTypeByExtension),
    'application/x-zip-compressed',
]);

export function imageExtensionForMimeType(mimeType: string): string {
    switch (mimeType) {
        case 'image/jpeg': return '.jpg';
        case 'image/webp': return '.webp';
        case 'image/heic': return '.heic';
        case 'image/heif': return '.heif';
        case 'image/gif': return '.gif';
        default: return '.png';
    }
}

export function supportedFileExtension(file: Express.Multer.File | Pick<Express.Multer.File, 'mimetype' | 'originalname'>): string {
    const originalExt = path.extname(file.originalname ?? '').replace('.', '').toLowerCase();
    if (supportedDocumentExtensions.has(originalExt)) {
        return originalExt;
    }

    for (const [ext, mimeType] of Object.entries(supportedDocumentMimeTypeByExtension)) {
        if (file.mimetype === mimeType) {
            return ext;
        }
    }

    if (file.mimetype === 'application/x-zip-compressed') {
        return 'zip';
    }

    return 'bin';
}

export function isSupportedDocument(file: Pick<Express.Multer.File, 'mimetype' | 'originalname'>): boolean {
    const ext = supportedFileExtension(file);
    return supportedDocumentExtensions.has(ext) || supportedDocumentMimeTypes.has(file.mimetype ?? '');
}

