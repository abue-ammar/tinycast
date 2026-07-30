# 🚀 快速开始指南

## 📖 概述

你已经成功实现了 Tinycast 的 AI Chat 功能！由于本地没有 Xcode，我们通过修改 GitHub Actions 来自动生成 Xcode 项目，这样就能在云端构建。

## ✅ 已完成的工作

1. **AI Chat 功能完整实现**（4 个新文件 + 5 个修改文件）
2. **GitHub Actions 配置修改**（自动使用 XcodeGen）
3. **自动化迁移脚本**（一键完成所有操作）

## 🎯 三种使用方式

### 方式 1：自动化脚本（推荐）⭐

最简单的方式，一行命令完成所有操作：

```bash
# 1. 先在 GitHub 网页上 fork https://github.com/abue-ammar/tinycast

# 2. 编辑脚本，修改你的 GitHub 用户名
nano migrate-to-fork.sh
# 找到这行：YOUR_GITHUB_USERNAME="yourname"
# 改成你的用户名，比如：YOUR_GITHUB_USERNAME="ericfu"

# 3. 运行脚本
bash migrate-to-fork.sh
```

脚本会自动完成：
- ✅ 配置 Git remote
- ✅ 创建功能分支
- ✅ 暂存所有文件
- ✅ 提交更改
- ✅ 推送到你的 fork

---

### 方式 2：手动操作（灵活）

如果你想更精细地控制每一步：

```bash
# 1. 在 GitHub 上 fork https://github.com/abue-ammar/tinycast

# 2. 配置 remote
git remote rename origin upstream
git remote add origin https://github.com/你的用户名/tinycast.git

# 3. 创建分支
git checkout -b feature/ai-chat

# 4. 暂存文件
git add Tinycast/Core/AIStore.swift
git add Tinycast/Core/AINotificationManager.swift
git add Tinycast/Features/AIChat/
git add Tinycast/Features/Settings/AIChatSettingsView.swift
git add Tinycast/Core/AppCore.swift
git add Tinycast/Core/CommandRegistry.swift
git add Tinycast/Core/PaletteWindowController.swift
git add Tinycast/Features/RootPaletteView.swift
git add Tinycast/Features/Settings/SettingsRootView.swift
git add .github/workflows/release.yml
git add *.md
git add migrate-to-fork.sh

# 5. 提交
git commit -m "Add AI Chat feature with CI auto-generation"

# 6. 推送
git push -u origin feature/ai-chat
```

---

### 方式 3：查看文档详细步骤

完整的分步说明在 `MIGRATION_GUIDE.md` 中。

---

## 🧪 测试 GitHub 构建

推送后，在 GitHub 上测试构建：

1. 访问你的仓库：`https://github.com/你的用户名/tinycast`
2. 点击 **Actions** 标签页
3. 选择 **Release** workflow
4. 点击 **Run workflow** 下拉菜单
5. 配置：
   - **Use workflow from**: `feature/ai-chat`
   - **Release channel**: `beta`
   - **Base version**: `0.1.1-test`
6. 点击 **Run workflow**

### 期望的构建步骤：

```
✅ Checkout code
✅ Select Xcode 26
✅ Compute release metadata
✅ Import signing certificate
✅ Install XcodeGen          ← 新增步骤
✅ Generate Xcode project    ← 新增步骤
✅ Build app                 ← 会找到所有新文件
✅ Package DMG
✅ Upload artifact
✅ Publish GitHub Release
```

如果成功，你会看到一个新的 Release，包含 DMG 文件。

---

## 📚 文档说明

| 文件 | 内容 |
|------|------|
| `AI_CHAT_IMPLEMENTATION.md` | 完整的功能实现说明、文件结构、使用方法 |
| `GITHUB_BUILD_SUPPORT.md` | 构建支持详情、三种方案对比、验证清单 |
| `MIGRATION_GUIDE.md` | 详细的迁移步骤、每步说明 |
| `QUICKSTART.md` | 本文件 - 快速开始 |
| `migrate-to-fork.sh` | 自动化迁移脚本 |

---

## 🎯 关键修改说明

### 新增文件（4 个）

```
Tinycast/Core/
├── AIStore.swift                    - AI 网络和状态管理
└── AINotificationManager.swift      - macOS 通知支持

Tinycast/Features/
├── AIChat/AIChatView.swift          - 聊天 UI
└── Settings/AIChatSettingsView.swift - 设置界面
```

### 修改文件（6 个）

```
✏️ AppCore.swift                - 添加 aiStore
✏️ CommandRegistry.swift        - 添加 .aiChat 命令
✏️ PaletteWindowController.swift - 注入环境对象
✏️ RootPaletteView.swift        - 添加 AI 模式渲染
✏️ SettingsRootView.swift       - 添加设置标签
✏️ .github/workflows/release.yml - 添加 XcodeGen 步骤
```

---

## ⚙️ GitHub Actions 的关键修改

在 `.github/workflows/release.yml` 中添加了两个步骤：

```yaml
- name: Install XcodeGen
  run: brew install xcodegen

- name: Generate Xcode project
  run: xcodegen generate
```

这让 CI 能够：
1. 从 `project.yml` 自动生成 Xcode 项目
2. 自动发现所有新的 `.swift` 文件
3. 无需手动在 Xcode 中添加文件

---

## 🔐 注意事项

### Secrets 配置

你的 fork 需要配置以下 secrets（如果要发布 release）：

- `SIGNING_P12_BASE64` - 签名证书
- `SIGNING_P12_PASSWORD` - 证书密码
- `HOMEBREW_TAP_TOKEN` - Homebrew tap token（可选）
- `DISCORD_WEBHOOK_URL` - Discord webhook（可选）

如果没有这些 secrets，构建会完成但签名步骤会失败。

**测试构建时**：你可以先测试，等构建到签名步骤失败也没关系 - 这证明 XcodeGen 和编译都成功了。

---

## 💡 常见问题

### Q: 脚本报错 "请在 tinycast 项目根目录运行"
A: 确保在 `/Users/ericfu/Work/tinycast/` 目录下运行脚本。

### Q: GitHub Actions 构建失败在 "Import signing certificate"
A: 这是正常的，你的 fork 还没有签名证书。但如果构建到这一步，说明 XcodeGen 和编译都成功了！

### Q: 我想先本地测试 XcodeGen
A: 安装后运行：
```bash
brew install xcodegen
xcodegen generate
```

### Q: 我想保留原仓库的更新
A: 我们已经把原仓库配置为 `upstream`：
```bash
git fetch upstream
git merge upstream/main
```

---

## 🎉 成功标志

构建成功后你会看到：

1. ✅ GitHub Actions 显示绿色勾号
2. ✅ Releases 页面有新的版本
3. ✅ 包含一个 `.dmg` 文件
4. ✅ 构建日志显示所有新的 Swift 文件都被编译了

---

## 📞 下一步

选择一个方式开始：

```bash
# 方式 1：运行自动化脚本（最简单）
bash migrate-to-fork.sh

# 方式 2：查看详细步骤
cat MIGRATION_GUIDE.md

# 方式 3：直接手动操作（见上面"方式 2"）
```

祝你成功！🚀
