// Public tutorial only: no authentication, connection-state requests or app navigation.
const guide = document.querySelector('#connection-guide');
const trigger = document.querySelector('.guide-trigger');
const closeButton = guide.querySelector('.guide-close');
const copyButton = guide.querySelector('.guide-copy');
const status = guide.querySelector('.guide-status');
trigger.addEventListener('click', () => {
  status.textContent = '';
  guide.showModal();
});
closeButton.addEventListener('click', () => guide.close());
guide.addEventListener('close', () => trigger.focus({ preventScroll: true }));
copyButton.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(guide.querySelector('.guide-prompt').textContent);
    status.textContent = copyButton.dataset.copied;
  } catch {
    guide.querySelector('details').open = true;
    status.textContent = copyButton.dataset.failed;
  }
});
