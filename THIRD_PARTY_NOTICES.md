# 代码许可与素材来源说明

## MIT 的适用范围

OmniVibe 自有源代码、脚本及项目自有文档采用根目录的 [MIT License](LICENSE)，已有单独许可声明的内容除外。MIT 允许商业使用、修改和再分发，也允许闭源再分发，需保留版权与许可声明。项目作者目前不计划商业化，不构成对下游使用者的“禁止商用”限制。

第三方图片、游戏角色、Logo、商标、音频及其中包含的第三方权利，不因收录在仓库中、被 AI 加工或与程序打包而获得 MIT 授权。各素材应按自身来源、许可或权利人的适用条款处理；本文件不授予项目无权授予的权利。其他项目的代码或文档若带有独立声明，应保留其声明。

The root MIT license covers OmniVibe's own source code, scripts and original documentation, except where separately licensed. It does not relicense third-party artwork, audio, characters, logos, trademarks or other third-party rights embodied in an asset. Attribution and AI-processing labels are not evidence of redistribution permission.

## AI 生成与加工的标注

本项目同时包含 AI 辅助生成、参考第三方美术加工、直接使用官方素材，以及由代码绘制的资源，不能将所有素材统称为“AI 原创”。“AI 生成”描述制作方式，不是许可证，也不能单独证明素材可自由分发或用于商业用途。

每项素材应如实记录：制作方式、原始来源或参考、生成工具/提示词（如有）、后续处理、文件哈希，以及已知的许可依据或待核查状态。对素材不具有的权利，不作授权承诺。能够识别特定游戏角色、器物或标志的生成图，仍需考虑相关第三方权利。

可使用的说明模板（仅在事实相符时）：

> 本素材由 AI 辅助生成，制作工具、提示词及处理记录见对应清单。若使用了第三方角色、标志或参考图，来源另列；涉及的第三方权利不属于本项目的 MIT 许可范围。AI 生成标注不代表已取得第三方授权。

## 当前资源分类

| 资源 | 已记录的制作方式与来源 | 许可边界 |
| --- | --- | --- |
| [`skins/loadouts/suites-v1/`](skins/loadouts/suites-v1/README.md) 中的 11 套新器物/棋灵包 | 清单记载为 imagegen 生成图集，再提取透明实体 | 保留生成与参考记录；“AI 辅助风格演绎”不等于取得相关游戏 IP 的许可 |
| `skins/loadouts/suites-v1/protocol/` | Riot 游戏角色原图，经社区 API 镜像取得 | 属于第三方素材，不能标为 AI 原创或按本项目 MIT 再授权 |
| `skins/loadouts/naraka/characters-v2/` 及复用它的套装 | 参考网易官方角色美术，经 imagegen 加工为透明持械图 | 标为参考图基础上的 AI 辅助加工；不将角色权利声明为项目自有 |
| `skins/loadouts/naraka/assets/` | 原官方武器图，来源见该目录清单 | 保留原权利人与来源，不授予 MIT 素材许可 |
| [`skins/identities/`](skins/identities/README.md) 当前集合 | 13 张无参考图生成的原创透明伙伴，清单、哈希和提示词随目录保留 | 已退役的官方封面、字标及参考封面加工图已从工作树移除；其历史来源与权利声明见 [预览版档案](https://github.com/Xiobio/OmniVibe/tree/v0.1.1-preview/skins/identities)，不因此改变其他在用素材的许可边界 |
| 主题插画、终端背景、品牌宣传图与截图 | 制作方式随文件而异，包含生成绘制、代码绘制、合成与截图 | 按对应清单和输入素材区分，不能仅凭所在目录或文件名套用同一授权结论 |
| [`skins/audio/`](skins/audio/LICENSE.txt) 中的原程序合成 WAV | 旧实验音效，由项目生成脚本合成 | 保持该目录既有 CC0 声明，仅覆盖其中声明的原合成音效 |
| [`skins/signature-audio/`](skins/signature-audio/README.md) | 游戏标志音来源清单；游戏音频另行安装到用户本地目录 | 游戏音频不属于前述 CC0；单独下载安装也不等于取得使用或再分发授权 |

具体文件来源、哈希与加工方式以各目录的 `catalog.json`、`manifest.json`、提示词和 README 为准。来源记录与权属说明用于追溯，不代表完成了对每项素材使用条件的核查。未明确提供素材许可的条目，不应被理解为自动采用 MIT。

## 第三方规则与发布范围

游戏名称、角色与商标归相应权利人所有，OmniVibe 不声明官方合作或赞助。非官方声明不能替代适用条款或授权。

例如 [Riot Games 的公开 IP 政策](https://www.riotgames.com/en/legal) 对应用内使用其 IP、Logo 和商标有明确限制。不能仅依据“个人项目”“免费”“开源”或“AI 生成”推定符合要求。其他游戏应分别核查其权利人规则，不能套用同一政策。

代码已采用 MIT，不代表当前仓库中的所有媒体素材已具备随公开发行包分发的许可。对许可依据尚未核实的第三方素材，应在公开发布前完成核查、取得授权，或替换/排除；涉及第三方美术的图册、宣传图与截图也应一并检查。
