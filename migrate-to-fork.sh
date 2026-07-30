#!/bin/bash

# Tinycast AI Chat - 迁移到自己仓库的自动化脚本
# 使用方法：
#   1. 先在 GitHub 上 fork https://github.com/abue-ammar/tinycast
#   2. 修改下面的 YOUR_GITHUB_USERNAME
#   3. 运行: bash migrate-to-fork.sh

set -e  # 遇到错误立即退出

# ====== 配置区域 ======
YOUR_GITHUB_USERNAME="yourname"  # 修改为你的 GitHub 用户名
BRANCH_NAME="feature/ai-chat"
# =====================

echo "🚀 开始迁移 Tinycast AI Chat 功能到你的仓库..."

# 检查是否已经 fork
echo ""
echo "⚠️  请确认你已经在 GitHub 上 fork 了 https://github.com/abue-ammar/tinycast"
echo "   你的 fork 地址应该是: https://github.com/${YOUR_GITHUB_USERNAME}/tinycast"
echo ""
read -p "是否已完成 fork？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ 请先完成 fork，然后重新运行此脚本"
    exit 1
fi

# 检查当前目录
if [ ! -d "Tinycast" ] || [ ! -f "project.yml" ]; then
    echo "❌ 错误：请在 tinycast 项目根目录运行此脚本"
    exit 1
fi

echo ""
echo "📦 步骤 1/5: 配置 Git Remote"
echo "----------------------------------------"

# 备份原 remote 为 upstream
if git remote get-url origin | grep -q "abue-ammar/tinycast"; then
    echo "重命名 origin -> upstream（保留上游引用）"
    git remote rename origin upstream
fi

# 添加你的 fork
if ! git remote get-url origin 2>/dev/null; then
    echo "添加你的 fork 为 origin"
    git remote add origin "https://github.com/${YOUR_GITHUB_USERNAME}/tinycast.git"
else
    echo "更新 origin 地址"
    git remote set-url origin "https://github.com/${YOUR_GITHUB_USERNAME}/tinycast.git"
fi

echo ""
echo "Git Remote 配置："
git remote -v

echo ""
echo "📝 步骤 2/5: 创建功能分支"
echo "----------------------------------------"

# 检查是否有未提交的更改
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "⚠️  检测到未提交的更改"
fi

# 确保在 main 分支
git checkout main 2>/dev/null || git checkout -b main

# 创建新分支
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    echo "分支 ${BRANCH_NAME} 已存在，切换到该分支"
    git checkout "${BRANCH_NAME}"
else
    echo "创建新分支: ${BRANCH_NAME}"
    git checkout -b "${BRANCH_NAME}"
fi

echo ""
echo "✅ 步骤 3/5: 暂存所有 AI Chat 代码"
echo "----------------------------------------"

# 添加新文件
echo "添加新文件..."
git add Tinycast/Core/AIStore.swift
git add Tinycast/Core/AINotificationManager.swift
git add Tinycast/Features/AIChat/
git add Tinycast/Features/Settings/AIChatSettingsView.swift

# 添加修改的文件
echo "添加修改的文件..."
git add Tinycast/Core/AppCore.swift
git add Tinycast/Core/CommandRegistry.swift
git add Tinycast/Core/PaletteWindowController.swift
git add Tinycast/Features/RootPaletteView.swift
git add Tinycast/Features/Settings/SettingsRootView.swift

# 添加文档
echo "添加文档..."
git add AI_CHAT_IMPLEMENTATION.md
git add GITHUB_BUILD_SUPPORT.md
git add MIGRATION_GUIDE.md
git add migrate-to-fork.sh

# 添加修改的 GitHub Actions
git add .github/workflows/release.yml

echo ""
echo "暂存的文件列表："
git status --short

echo ""
echo "💾 步骤 4/5: 提交更改"
echo "----------------------------------------"

git commit -m "Add AI Chat feature with CI auto-generation

Features:
- AI Chat mode in command palette (Cmd+Space)
- Claude API integration with streaming responses
- Secure API key storage in macOS Keychain
- Conversation history with local persistence
- Settings pane for configuration
- macOS notification support for background responses

Technical:
- AIStore: Network layer following CurrencyRateStore pattern
- AIChatView: Chat UI with real-time streaming
- AIChatSettingsView: Configuration interface
- AINotificationManager: User notification support
- Modified GitHub Actions to use XcodeGen for auto project generation

Implementation follows Tinycast architecture:
- Consent-gated network access (off by default)
- Swift 6 strict concurrency
- Theme design system compliance
- Single-owner AppCore pattern

Allows building without local Xcode by generating project on CI."

echo ""
echo "✅ 提交完成！"

echo ""
echo "🚀 步骤 5/5: 推送到你的 Fork"
echo "----------------------------------------"
echo ""
echo "即将推送到: https://github.com/${YOUR_GITHUB_USERNAME}/tinycast"
echo "分支: ${BRANCH_NAME}"
echo ""
read -p "确认推送？(y/N): " push_confirm

if [[ "$push_confirm" =~ ^[Yy]$ ]]; then
    echo "推送中..."
    git push -u origin "${BRANCH_NAME}"

    echo ""
    echo "✅ 推送成功！"
    echo ""
    echo "🎉 迁移完成！"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 接下来的步骤："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1️⃣  测试 GitHub Actions 构建："
    echo "    访问: https://github.com/${YOUR_GITHUB_USERNAME}/tinycast/actions"
    echo "    点击 'Release' workflow → 'Run workflow'"
    echo "    选择分支: ${BRANCH_NAME}"
    echo "    Channel: beta"
    echo "    Version: 0.1.1-test"
    echo ""
    echo "2️⃣  观察构建日志，应该看到："
    echo "    ✅ Install XcodeGen"
    echo "    ✅ Generate Xcode project"
    echo "    ✅ Build app"
    echo "    ✅ Package DMG"
    echo ""
    echo "3️⃣  如果构建成功，创建 Pull Request："
    echo "    访问: https://github.com/${YOUR_GITHUB_USERNAME}/tinycast/compare/${BRANCH_NAME}"
    echo ""
    echo "4️⃣  或者直接合并到 main："
    echo "    git checkout main"
    echo "    git merge ${BRANCH_NAME}"
    echo "    git push origin main"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📚 参考文档："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "• AI_CHAT_IMPLEMENTATION.md - 功能实现说明"
    echo "• GITHUB_BUILD_SUPPORT.md - 构建支持详情"
    echo "• MIGRATION_GUIDE.md - 完整迁移指南"
    echo ""
else
    echo ""
    echo "❌ 取消推送"
    echo ""
    echo "你可以稍后手动推送："
    echo "  git push -u origin ${BRANCH_NAME}"
    echo ""
fi
