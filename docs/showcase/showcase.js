"use strict";
(() => {
  const theme = document.querySelector("#theme");
  const preview = document.querySelector("#preview");
  const selection = document.querySelector("#selection");
  const original = document.querySelector("#original");
  const caption = document.querySelector("#caption");
  const buttons = [...document.querySelectorAll("[data-mode]")];
  const modes = {
    deck: {label: "展开圆盘", path: slug => `../game-suite-refinement/screens/deck-${slug}-decorated.png`, description: "原生圆盘组件测试截图；这是展开状态，不代表入口的常驻占地。"},
    inventory: {label: "任务总览", path: slug => `../game-suite-refinement/screens/inventory-${slug}.png`, description: "原生总览组件测试截图，使用示例任务与状态；实际状态需要接入事件。"},
    loadout: {label: "配装界面", path: slug => `../game-suite-refinement/screens/loadout-${slug}.png`, description: "原生配装界面测试截图；主题实体与任务窗口分别管理。"},
    terminal: {label: "终端外观", path: slug => `../terminal-frame-refinement/${slug}-regular.png`, description: "终端外观测试示例；保留原生标题栏，以配色、插画和边饰统一氛围。"}
  };
  theme.value = "relic";
  let mode = "terminal";
  function render() {
    const config = modes[mode];
    const name = theme.options[theme.selectedIndex].text;
    const path = config.path(theme.value);
    preview.dataset.mode = mode;
    preview.alt = `${name} / ${config.label}开发测试示例`;
    preview.src = path;
    original.href = path;
    selection.textContent = `${name} / ${config.label}`;
    caption.textContent = config.description;
    buttons.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.mode === mode)));
  }
  theme.addEventListener("change", render);
  buttons.forEach(button => button.addEventListener("click", () => {mode = button.dataset.mode; render();}));
  preview.addEventListener("error", () => {caption.textContent = "图片未能载入，请保留完整仓库目录，或点击「查看原图」检查资源路径。";});
  render();
})();
