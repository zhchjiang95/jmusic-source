# JMusic 官网

一个静态单页着陆页，介绍 [JMusic](https://github.com/zhchjiang95/jmusic-source) 这个跨平台本地音乐播放器。

## 文件结构

```
website/
├── index.html        # 主页面（HTML + Tailwind via CDN）
├── styles.css        # 自定义组件样式 + 动画
├── script.js         # 滚动出现 / 导航高亮 / 复制按钮
├── assets/
│   └── icon.png      # 应用图标
└── screenshots/      # 应用截图
    ├── home.png
    ├── player.png
    ├── fullscreen-lyrics.png
    └── desktop-lyrics.png
```

## 本地预览

任何静态服务器都能跑，例如：

```bash
# Python（项目已自带）
cd website
python -m http.server 8080
# 浏览器打开 http://localhost:8080
```

或直接用 VS Code 的 Live Server 扩展打开 `index.html`。

## 部署

可直接托管到任意静态站平台：

- **GitHub Pages** — 把 `website/` 内容推送到 `gh-pages` 分支或仓库 `docs/` 目录即可
- **Vercel / Netlify / Cloudflare Pages** — 把整个 `website/` 设为 publish directory，无需构建命令
- **对象存储（OSS/S3/COS）** — 上传后开启静态网站托管

## 设计系统

设计依据保存在仓库的 `design-system/jmusic/MASTER.md`，由 `ui-ux-pro-max` 工具生成。
主要参数：

- **风格**：App Store 式着陆页 + 深色音乐主题
- **主色**：`#4338CA → #6366F1` 渐变（紫色 / 靛色）
- **CTA 色**：`#22C55E`（播放按钮联想绿）
- **字体**：Righteous（标题）/ Poppins（正文）/ Noto Sans SC（中文）
- **效果**：Aurora 渐变背景、Glow shadow、Reveal-on-scroll、`prefers-reduced-motion` 兼容

## 还可以补充什么？（建议）

当前页面已覆盖：Hero、特性、截图、技术架构、下载、FAQ、Footer。如果后续想丰富，可以考虑：

1. **更新日志 / Changelog** —— 通过 GitHub API 拉取最新 release 自动展示版本号
2. **快捷键速查表** —— 播放、上一首、悬浮歌词显隐等热键
3. **Roadmap** —— 计划中的功能（如 Linux 打包、网易云 / 酷狗匹配源）
4. **隐私声明** —— 强调 100% 离线优先、无遥测、无账号
5. **第三方致谢** —— Flutter、Rust、rodio、reqwest、Riverpod 等
6. **构建状态徽章** —— GitHub Actions / Codecov 徽章
7. **赞助 / Star** —— GitHub Sponsors 链接、Star History 图表
8. **社区** —— Issues / Discussions / Telegram / QQ 群入口
9. **多语言切换** —— 中 / 英文双语
10. **演示视频或 GIF** —— 展示沉浸歌词与桌面悬浮歌词的动态效果，比静态截图更直观
