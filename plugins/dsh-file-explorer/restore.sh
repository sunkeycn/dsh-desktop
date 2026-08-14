#!/usr/bin/env bash
# dsh-file-explorer 插件安装 / 恢复脚本
#
# 用途：把本目录（插件源码）安装到 ~/.dsh/profiles/node_modules/，并把 insert 补丁写回
#       cordis.patch.yml。DSH 升级后用户插件可能被覆盖，重跑一次本脚本即可恢复，然后重启 DSH。
#
# 用法：bash restore.sh   （在本目录下执行）
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.dsh/profiles/node_modules/dsh-file-explorer"
PATCH="$HOME/.dsh/profiles/web/cordis.patch.yml"

# 1) 安装插件包（只复制 package.json + lib/，不含本脚本）
rm -rf "$DEST"
mkdir -p "$DEST/lib"
cp "$SRC/package.json" "$DEST/package.json"
cp "$SRC/lib/index.js" "$DEST/lib/index.js"
cp "$SRC/lib/client.js" "$DEST/lib/client.js"

# 2) 幂等地在 cordis.patch.yml 追加 insert 行（只认未注释的活跃行）
if ! grep -qE '^[[:space:]]*- id: file-explorer[[:space:]]*$' "$PATCH" 2>/dev/null; then
  {
    echo ""
    echo "# 右侧「文件树 + 文件预览」侧边栏（dsh-file-explorer）"
    echo "- insert:"
    echo "    - id: file-explorer"
    echo "      name: 'dsh-file-explorer'"
  } >> "$PATCH"
  echo "✅ 已向 cordis.patch.yml 追加 insert 补丁"
else
  echo "ℹ️  cordis.patch.yml 已包含 dsh-file-explorer，跳过"
fi

echo ""
echo "✅ dsh-file-explorer 已安装。重启 DSH 后生效："
echo "   ① 会话头部最右侧出现「右侧面板」图标按钮"
echo "   ② 点击打开右栏文件树，点文件即应用内预览"
