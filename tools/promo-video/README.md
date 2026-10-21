# Promo video pipeline

60 s, 1920×1080, 30 fps, EN + ZH. Run from the repo root. `W` is the work directory (`artifacts/promo-video`).

1. UI frames from the real app:
   build `render-ui/PromoRender.csproj` alongside CodeManager, then run `PromoRender.exe <W>/ui en` and `PromoRender.exe <W>/ui zh-CN`.
2. Music:
   `python -I tools/promo-video/music.py tools/promo-video/timeline.json . <W>/audio/music.wav`
3. Stage:
   `python -I tools/promo-video/build.py . <W>`
4. Preview frames:
   `python -I tools/promo-video/render.py <W> en --preview 10,25,40`
5. Full render:
   `python -I tools/promo-video/render.py <W> en` (then `zh`; run them one at a time because they share `stage/config.js`).
6. Mux and convert to BT.709 limited range:

   ```
   ffmpeg -i <W>/out/video-en.mp4 -i <W>/audio/music.wav -map 0:v -map 1:a \
     -vf "scale=in_range=pc:out_range=tv:in_color_matrix=bt601:out_color_matrix=bt709,format=yuv420p" \
     -c:v libx264 -preset slow -crf 17 -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -g 60 \
     -af "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000" -c:a aac -b:a 256k -shortest -movflags +faststart \
     <W>/out/OmniVibe-promo-en.mp4
   ```

`timeline.json` drives both the visuals and the music, so shift beats there and both stay in sync.

The montage deliberately leaves out the theme packs that are built from official game art, and it names no game titles.
