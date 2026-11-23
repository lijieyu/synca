// Finder/LaunchServices maintains one GUI instance on macOS. Do not create
// Chromium's fragile process-singleton socket in a sandboxed MAS app:
// a preceding crash can leave it stale and make the replacement quit silently.
function requestInstance(runtime, mode, requestChromiumLock) {
  if (runtime.platform === 'darwin' && runtime.mas === true &&
      (mode === 'mas-testflight' || mode === 'mas-preflight' || mode === 'mas-production')) return true;
  return requestChromiumLock();
}
module.exports = {requestInstance};
