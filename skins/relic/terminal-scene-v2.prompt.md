# 灵蕴法宝匣 · 完整洞窟场景

生成方式：内置 imagegen 编辑现有 `illustration.png`；保留原插画，输出独立的 `terminal-scene-v2.png`，只供 Terminal 使用。

新增内容：顶部洞窟与石梁、左侧石柱与岩壁、底部贯通的台阶地面；右侧玉璧、香炉与石龛延续原构图。终端构建阶段保留文字阅读遮光与 ANSI 对比度校准。

## 实际生成提示词

```text
Use case: precise-object-edit.
Asset type: production landscape background illustration for OmniVibe Windows Terminal.
Input image 1 is the EDIT TARGET, not a mood reference.
Primary request: turn the existing right-hand ancient Chinese stone shrine scene into ONE complete, coherent environmental painting by extending the actual architecture and landscape across the top, left edge, and bottom. The user likes the existing right-side shrine, hanging jade bi disk, bronze incense vessel, steps, red leaves, stone texture and warm light; preserve their design, approximate size, position, perspective, and lighting.
Keep the landscape canvas and the existing right third almost unchanged. In the TOP 8 percent, continue the broken carved stone lintel and cave ceiling naturally to the left, with restrained hanging roots and aged rock. Along the LEFT 6 percent, paint a partial weathered stone column / cave wall, shallow relief, a few cracks and moss, disappearing softly into the central shadows. Along the BOTTOM 10 percent, extend the existing right-hand stone steps into connected uneven flagstone ground across the width, with small rubble, sparse dry red leaves and a little ground mist. These three areas must be real illustrated scene content with convincing depth, shared perspective and materials, NOT repeated small geometric icons, flat trim, a rectangular decorative border, or tiles.
The central left and middle 75 percent is a quiet reading area: atmospheric shadow, subtle distant cave shapes and soft mist, subdued contrast, low-frequency detail. It should still feel like a complete painting when viewed without text, with no large featureless solid-black rectangle. Concentrate crisp detail in the outer environment and on the existing right focal subject. Match the original charcoal, aged bronze, muted warm gold and restrained jade palette; dark painterly realistic game environment concept art.
Constraints: no UI, no terminal text, no letters, no watermark, no logo, no border/frame, no people, no new focal object, no glowing effects over the reading area. Preserve the right-side existing scene as closely as possible. Opaque background. Landscape approximately 16:10, matching input framing.
```
