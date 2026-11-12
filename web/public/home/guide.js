// Public tutorial only: no authentication, connection-state requests or app navigation.
const guide = document.querySelector('#connection-guide');
const trigger = document.querySelector('.guide-trigger');
const closeButton = guide.querySelector('.guide-close');
const copyButton = guide.querySelector('.guide-copy');
const status = guide.querySelector('.guide-status');
let toastTimer;
function showToast(message) {
  clearTimeout(toastTimer);
  status.textContent = message;
  toastTimer = setTimeout(() => { status.textContent = ''; }, 2600);
}
trigger.addEventListener('click', () => {
  status.textContent = '';
  guide.showModal();
});
closeButton.addEventListener('click', () => guide.close());
guide.addEventListener('close', () => trigger.focus({ preventScroll: true }));
copyButton.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(guide.querySelector('.guide-prompt').textContent);
    showToast(copyButton.dataset.copied);
  } catch {
    showToast(copyButton.dataset.failed);
  }
});
