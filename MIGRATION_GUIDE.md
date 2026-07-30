# 迁移到自己仓库的完整方案

## 🎯 目标

从 `abue-ammar/tinycast` fork 项目到你自己的 GitHub 账号，添加 AI Chat 功能，并在 GitHub Actions 上构建。

## 📋 当前情况

- ✅ 本地已实现所有 AI Chat 代码
- ✅ 代码在正确的目录结构中
- ❌ 新文件未添加到 Xcode 项目
- ❌ 本地没有 Xcode（无法手动添加文件）
- ⚠️ 远端是别人的仓库（不能推送）

## 🚀 完整迁移方案

### 步骤 1：在 GitHub 上 Fork 原仓库

1. 访问 https://github.com/abue-ammar/tinycast
2. 点击右上角 **Fork** 按钮
3. 选择你的 GitHub 账号
4. 等待 fork 完成（假设你的账号是 `yourname`，新仓库地址是 `https://github.com/yourname/tinycast`）

### 步骤 2：修改本地 Git 配置

```bash
cd /Users/ericfu/Work/tinycast

# 备份原 remote 为 upstream（保留上游引用）
git remote rename origin upstream

# 添加你自己的 fork 作为 origin
git remote add origin https://github.com/yourname/tinycast.git

# 验证配置
git remote -v
# 应该看到：
# origin    https://github.com/yourname/tinycast.git (fetch)
# origin    https://github.com/yourname/tinycast.git (push)
# upstream  https://github.com/abue-ammar/tinycast.git (fetch)
# upstream  https://github.com/abue-ammar/tinycast.git (push)
```

### 步骤 3：创建修改 GitHub Actions 的分支

由于没有 Xcode，我们让 CI 自动用 XcodeGen 生成项目。

```bash
# 创建新分支
git checkout -b feature/ai-chat

# 暂存所有 AI Chat 代码
git add Tinycast/Core/AIStore.swift
git add Tinycast/Core/AINotificationManager.swift
git add Tinycast/Features/AIChat/
git add Tinycast/Features/Settings/AIChatSettingsView.swift
git add Tinycast/Core/AppCore.swift
git add Tinycast/Core/CommandRegistry.swift
git add Tinycast/Core/PaletteWindowController.swift
git add Tinycast/Features/RootPaletteView.swift
git add Tinycast/Features/Settings/SettingsRootView.swift
git add AI_CHAT_IMPLEMENTATION.md
git add GITHUB_BUILD_SUPPORT.md
```

### 步骤 4：修改 GitHub Actions 使用 XcodeGen

编辑 `.github/workflows/release.yml`，在 "Build app" 之前添加 XcodeGen 步骤：

```yaml
# 在第 85 行 "Build app" 之前插入
- name: Install XcodeGen
  run: brew install xcodegen

- name: Generate Xcode project from yml
  run: xcodegen generate
```

这样 CI 会自动发现新文件并添加到项目中。

### 步骤 5：提交并推送

```bash
# 提交所有更改
git commit -m "Add AI Chat feature with CI auto-generation

- Add AIStore for Claude API integration
- Add AIChatView for chat UI
- Add AIChatSettingsView for configuration
- Add AINotificationManager for macOS notifications
- Modify GitHub Actions to use XcodeGen
- Auto-generate Xcode project on CI build

This allows building without local Xcode."

# 推送到你自己的 fork
git push -u origin feature/ai-chat
```

### 步骤 6：在 GitHub 上测试构建

1. 访问你的仓库 `https://github.com/yourname/tinycast`
2. 进入 **Actions** 标签页
3. 点击 **Release** workflow
4. 点击 **Run workflow** 下拉菜单
5. 选择分支 `feature/ai-chat`
6. 选择 channel: `beta`
7. 输入 version: `0.1.1-test`
8. 点击 **Run workflow**

### 步骤 7：验证构建成功

观察 Actions 日志，应该看到：
1. ✅ Checkout 代码
2. ✅ 选择 Xcode 26
3. ✅ 安装 XcodeGen
4. ✅ 生成 Xcode 项目（自动包含新文件）
5. ✅ 构建签名的 .app
6. ✅ 打包 DMG
7. ✅ 发布 Release

如果成功，你会看到：
- GitHub Release 页面有新的 `v0.1.1-test-beta.XX`
- 包含 `Tinycast-0.1.1-test-beta.XX.dmg` 文件

### 步骤 8：合并到主分支（可选）

```bash
# 如果构建成功，合并到 main
git checkout main
git merge feature/ai-chat
git push origin main
```

---

## 🔧 需要修改的文件

我现在帮你修改 GitHub Actions workflow：

