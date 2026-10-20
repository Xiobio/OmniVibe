# Empty theme identity

When no window is bound, the dock core and overview's empty card show the theme's identity artwork. This is separate from all nine saved equipment assignments. Binding a task restores its chosen weapon or character; removing the last task restores the game identity. Empty wheel targets retain their quiet plus marks and fixed numbers.

`catalog.json` maps each game theme slug to one local image, its original URL, source page, dimensions and SHA-256. Images are downloaded from the official websites or publisher's Steam store assets, unchanged. Game art and trademarks remain the property of their respective rights holders; these assets are not covered by OmniVibe's source code license. This is not an official game product.

For custom theme packs, provide one PNG/JPEG and a `file` entry with a filename in this directory. The app fits the whole image without cropping it, freezes a decoded copy with longest edge capped at 512, and never reads files during dock drawing. No slideshow, timer or background animation is started for an empty dock. Prefer a clear square icon or a cover with one recognizable subject; narrow logos are kept intact.

If an identity image is unavailable, the app uses the theme illustration, then the existing native core art. The three original ink themes use that fallback deliberately. Missing identity artwork never changes task bindings or the capture hit targets.

Overview size is available at **设置 → 窗口与布局 → 任务总览大小**. Five saved presets are provided: 紧凑、标准、宽敞、超大、近全屏. The default is 超大. Size is constrained in logical pixels to the current work area, keeping visible desktop margins; short screens retain scrolling and keyboard navigation.
