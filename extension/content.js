// ラクコ 利用者一覧（/users）の「削除する」を非表示にし、クリックも止める。
// ラクコは画面遷移でページを再読み込みしない（SPA）ため、DOM の変化を監視して毎回処理する。
(() => {
  const TARGET_PATH = /^\/users\/?$/;   // 利用者一覧のみ
  const LABEL = '削除する';
  const MARK = 'data-rakuco-delete-hidden';

  const onTargetPage = () => TARGET_PATH.test(location.pathname);

  // 「削除する」の文字だけを直接持つ要素か
  const isDeleteLabel = (el) =>
    [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim() === LABEL);

  // 文字とゴミ箱アイコンをまとめて包む要素（無ければ文字の要素そのもの）
  const deleteGroupOf = (label) => {
    const parent = label.parentElement;
    if (parent && parent.querySelector(':scope > svg') && parent.closest('td')) return parent;
    return label;
  };

  const hideAll = () => {
    if (!onTargetPage()) return;
    document.querySelectorAll('tbody td div, tbody td span').forEach((el) => {
      if (el.hasAttribute(MARK) || !isDeleteLabel(el)) return;
      const group = deleteGroupOf(el);
      group.setAttribute(MARK, '');
      group.style.setProperty('display', 'none', 'important');
      group.style.setProperty('pointer-events', 'none', 'important');
    });
  };

  // 万一表示が残っても、削除の部分へのクリックは捕まえて止める
  document.addEventListener(
    'click',
    (e) => {
      if (!onTargetPage()) return;
      const t = e.target instanceof Element ? e.target : null;
      if (t && t.closest(`[${MARK}]`)) {
        e.stopImmediatePropagation();
        e.preventDefault();
      }
    },
    true
  );

  let scheduled = false;
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      hideAll();
    });
  };

  const start = () => {
    hideAll();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
