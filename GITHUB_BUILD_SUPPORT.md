# GitHub 构建支持说明

## ⚠️ 当前状态：需要手动操作

**新文件尚未添加到 Xcode 项目**，因此 GitHub Actions 构建会失败。

## 📋 问题分析

1. **GitHub Actions 配置正常**
   - `.github/workflows/release.yml` 存在且配置完整
   - 使用 `xcodebuild` 直接构建项目
   - 运行在 `macos-26` 环境，使用 Xcode 26

2. **项目管理方式**
   - 项目使用 XcodeGen (`project.yml` 存在)
   - 但 **`Tinycast.xcodeproj` 是已提交的**（不是从 yml 生成的）
   - 这意味着新文件需要手动添加到项目

3. **当前新文件未包含在项目中**
   ```
   未追踪的文件：
   - Tinycast/Core/AIStore.swift
   - Tinycast/Core/AINotificationManager.swift
   - Tinycast/Features/AIChat/AIChatView.swift
   - Tinycast/Features/Settings/AIChatSettingsView.swift
   ```

## ✅ 解决方案

### 方案 1：手动在 Xcode 中添加文件（推荐）

1. 打开 `Tinycast.xcodeproj`
2. 右键点击 `Core` 组 → Add Files to "Tinycast"
   - 添加 `AIStore.swift`
   - 添加 `AINotificationManager.swift`
3. 创建新组 `Features/AIChat`
   - 添加 `AIChatView.swift`
4. 右键点击 `Features/Settings` 组
   - 添加 `AIChatSettingsView.swift`
5. 确保所有文件的 Target Membership 勾选了 `Tinycast`
6. 构建测试：`Cmd+B`
7. 提交 `Tinycast.xcodeproj/project.pbxproj` 的变更

### 方案 2：使用 XcodeGen 重新生成（如果安装了）

```bash
# 安装 XcodeGen（如果还没有）
brew install xcodegen

# 新文件已经在正确的目录，直接重新生成项目
xcodegen generate

# 构建测试
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build

# 提交生成的项目文件
git add Tinycast.xcodeproj/project.pbxproj
git commit -m "Add AI Chat files to Xcode project"
```

### 方案 3：修改 GitHub Actions 在构建前运行 XcodeGen

在 `.github/workflows/release.yml` 的 `Build app` 步骤之前添加：

```yaml
- name: Install XcodeGen
  run: brew install xcodegen

- name: Generate Xcode project
  run: xcodegen generate
```

这样 CI 会自动发现新文件。但这需要修改 workflow 文件。

## 🔍 验证构建是否成功

### 本地验证

```bash
# 清理
rm -rf ~/Library/Developer/Xcode/DerivedData/Tinycast-*

# 构建（模拟 CI 环境）
xcodebuild -project Tinycast.xcodeproj \
  -scheme Tinycast \
  -configuration Release \
  -derivedDataPath /tmp/TinycastBuild \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Tinycast Self-Signed" \
  build
```

### GitHub Actions 验证

提交代码后，在 GitHub 上：
1. 进入 Actions 标签页
2. 手动触发 `Release` workflow
3. 选择 `beta` 渠道，版本号 `0.1.1`（测试用）
4. 观察构建日志

## 📝 提交建议

```bash
# 添加所有新文件
git add Tinycast/Core/AIStore.swift
git add Tinycast/Core/AINotificationManager.swift
git add Tinycast/Features/AIChat/
git add Tinycast/Features/Settings/AIChatSettingsView.swift

# 添加修改的文件
git add Tinycast/Core/AppCore.swift
git add Tinycast/Core/CommandRegistry.swift
git add Tinycast/Core/PaletteWindowController.swift
git add Tinycast/Features/RootPaletteView.swift
git add Tinycast/Features/Settings/SettingsRootView.swift

# 添加文档
git add AI_CHAT_IMPLEMENTATION.md

# 如果已经在 Xcode 中添加了文件
git add Tinycast.xcodeproj/project.pbxproj

# 提交
git commit -m "Add AI Chat feature

- Add AIStore for network and state management
- Add AIChatView for chat UI
- Add AIChatSettingsView for configuration
- Add AINotificationManager for macOS notifications
- Integrate AI Chat into palette modes and settings
- Follow CurrencyRateStore pattern for consent-gated network access"
```

## ⚡ 快速检查清单

在推送到 GitHub 之前：

- [ ] 新的 `.swift` 文件在 Xcode 项目中可见
- [ ] 本地 `Cmd+B` 构建成功
- [ ] `git status` 显示 `project.pbxproj` 已修改
- [ ] 所有文件的 Target Membership 包含 `Tinycast`
- [ ] 没有编译错误或警告

## 🎯 结论

**当前无法直接在 GitHub 上构建**，因为新文件不在 Xcode 项目中。

**推荐操作**：
1. 在 Xcode 中手动添加 4 个新文件
2. 本地构建确认成功
3. 提交 `project.pbxproj` 变更
4. 推送到 GitHub

之后 GitHub Actions 就能正常构建了。
