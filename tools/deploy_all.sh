#!/usr/bin/env bash
# 一键部署到所有已连接设备（平板实物 + 手机模拟器 可同时）
#
# 用法：bash tools/deploy_all.sh
# 说明：编译一次 → 对 hdc 列出的每台设备安装签名包并启动
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="/c/Users/Baoru Lee/.workbuddy/binaries/node/workspace/node_modules/.bin/devecocli"
HDC="/d/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
BUNDLE="com.timestamp.recorder"
ABILITY="EntryAbility"

# ⚠️ 必须清掉代理：ohpm 源是国内域名，挂代理会 ECONNREFUSED
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY

# ⚠️ 必须显式指定 SDK 根目录：Bash 环境里 DEVECO_SDK_HOME 可能为空/被污染，
# 否则 hvigor sync 会报 "Invalid value of 'DEVECO_SDK_HOME'" 直接失败（之前反复掉坑点）。
export DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk"

echo "== 1/3 编译（含签名）=="
# 注意：绝不能加 `| tail`，否则管道退出码永远是 tail 的 0，
# 编译失败时 `||` 不触发，会误装上次残留的旧 hap（假成功）。
(cd "$ROOT" && "$CLI" build 2>&1) || { echo "编译失败，中止部署（不装旧包）"; exit 1; }

HAP_DIR="$ROOT/entry/build/default/outputs/default"
HAP="entry-default-signed.hap"
if [ ! -f "$HAP_DIR/$HAP" ]; then
  echo "找不到签名产物：$HAP_DIR/$HAP"
  exit 1
fi

echo
echo "== 2/3 已连接设备 =="
"$HDC" list targets

echo
echo "== 3/3 逐台安装并启动 =="
cd "$HAP_DIR" || exit 1
for dev in $("$HDC" list targets 2>/dev/null | tr -d '\r' | grep -vE '^\[|^$|Empty'); do
  echo "--- 设备：$dev"
  "$HDC" -t "$dev" install -r "$HAP" 2>&1 | tail -2
  "$HDC" -t "$dev" shell aa start -a "$ABILITY" -b "$BUNDLE" 2>&1 | tail -1
done

echo
echo "== 全部完成 =="
