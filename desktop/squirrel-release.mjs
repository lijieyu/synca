// Squirrel writes UTF-8 with BOM and uppercase SHA-1. Match actual package bytes,
// ignoring only encoding/newline decoration, never arbitrary filenames or URLs.
export function verifySquirrelRelease(text,info){
 const expected=`${info.sha1} ${info.name} ${info.bytes}`.toLowerCase();
 if(!text.replace(/^\uFEFF/,'').split(/\r?\n/).some(line=>line.toLowerCase()===expected))throw Error('Squirrel feed does not match generated package');
}
