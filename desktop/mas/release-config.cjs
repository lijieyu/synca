function validateRelease(release, mode) {
  const production = mode === 'mas-production'
  if (!production && mode !== 'mas-testflight') throw Error('Unknown verified MAS mode')
  const origin = production ? 'https://synca.haerth.cn' : 'https://synca-preview.haerth.cn'
  if (release.origin !== origin || !/^[a-f0-9]{40}$/.test(release.backendCommit || '') || !/^[a-f0-9]{64}$/.test(release.backendReleaseSha256 || ''))
    throw Error('Missing exact backend release identity')
  const evidence = production
    ? ['productionMigrationVerified', 'safeRollbackVerified', 'realEmailLoginAndSyncVerified', 'webEmailHidden']
    : ['realEmailDeliveryVerified', 'verificationAndSyncVerifiedWithSyntheticCode']
  if (evidence.some(key => release[key] !== true)) throw Error('Missing release verification evidence')
  return production ? 'verified-tf-production' : 'verified-tf-remote'
}
module.exports = {validateRelease}
