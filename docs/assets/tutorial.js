(() => {
  const root = document.querySelector('[data-demo]');
  if (!root) return;
  const pictures = [...root.querySelectorAll('.demo-stage img')];
  const steps = [...root.querySelectorAll('[data-step]')];
  const toggle = root.querySelector('[data-play]');
  const caption = root.querySelector('[data-caption]');
  const descriptions = [
    '首次设置：选择维护者提供的连接配置。私人分享包可直接点击“使用随包配置”；公开版请选择文件。',
    '准备完成：完成。此时尚未更改系统代理，点击“开启”才会开始连接。',
    '连接开启：按 macOS 提示授权后，可以打开日常应用。外网测试结果会显示在卡片下方。',
    '用完关闭：点击“关闭”，恢复开启前的设置。正常退出G-Link也会先恢复网络。'
  ];
  let current = 0, timer = null;
  function select(index) {
    current = index;
    pictures.forEach((p, i) => p.classList.toggle('active', i === index));
    steps.forEach((p, i) => { p.classList.toggle('active', i === index); p.setAttribute('aria-pressed', String(i === index)); });
    caption.textContent = descriptions[index];
  }
  function pause() { clearInterval(timer); timer = null; toggle.textContent = '播放演示 ▷'; toggle.setAttribute('aria-pressed', 'false'); }
  function play() { pause(); timer = setInterval(() => select((current + 1) % pictures.length), 4200); toggle.textContent = '暂停演示 Ⅱ'; toggle.setAttribute('aria-pressed', 'true'); }
  toggle.addEventListener('click', () => timer ? pause() : play());
  steps.forEach((step, index) => step.addEventListener('click', () => { pause(); select(index); }));
  document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });
  select(0);
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) play();
})();
