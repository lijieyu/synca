/** Track deliberate navigation, so Escape and programmatic restoration do not
 * turn pointer-opened dialogs into keyboard focus rings. Applies to portals too. */
export function installFocusModality() {
  const root = document.documentElement;
  root.dataset.focusModality = 'keyboard';
  document.addEventListener('pointerdown', () => { root.dataset.focusModality = 'pointer'; }, true);
  document.addEventListener('keydown', event => {
    if (event.isComposing || event.keyCode === 229 || event.key === 'Escape') return;
    const target = event.target;
    const editing = target instanceof HTMLElement &&
      (target.matches('input, textarea') || target.isContentEditable);
    if (event.key === 'Tab' || (!editing && ['Enter', ' ', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key))) {
      root.dataset.focusModality = 'keyboard';
    }
  }, true);
}
