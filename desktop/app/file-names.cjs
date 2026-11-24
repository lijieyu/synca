// Portable attachment names: Windows also rejects DOS devices and trailing dots/spaces.
function safeFileName(value) {
  let name = typeof value === 'string' ? value.split(/[\\/]/).pop().replace(/[\u0000-\u001f\u007f<>:"|?*]/g, '_').replace(/[ .]+$/g, '') : ''
  if (!name || name.startsWith('.')) return 'attachment'
  if (/^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)/i.test(name)) name = '_' + name
  // NTFS counts UTF-16 units; retain the extension and never split a surrogate pair.
  const extension = /\.[^.]{1,20}$/.exec(name)?.[0] || ''
  const stem = extension ? name.slice(0, -extension.length) : name
  let short = ''
  for (const character of stem) {
    if (short.length + character.length > 150 - extension.length) break
    short += character
  }
  return (short + extension).replace(/[ .]+$/g, '') || 'attachment'
}
module.exports = { safeFileName }
