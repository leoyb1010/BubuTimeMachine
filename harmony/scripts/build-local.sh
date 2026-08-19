#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root="$project_root"
staging_root=
deveco_contents=${DEVECO_STUDIO_CONTENTS:-/Applications/DevEco-Studio.app/Contents}
node_bin="$deveco_contents/tools/node/bin/node"
hvigor_bin="$deveco_contents/tools/hvigor/hvigor/bin/hvigor.js"
hvigor_package="$deveco_contents/tools/hvigor/hvigor"
ohos_plugin="$deveco_contents/tools/hvigor/hvigor-ohos-plugin"

for required_path in "$node_bin" "$hvigor_bin" "$hvigor_package" "$ohos_plugin" "$deveco_contents/sdk" "$deveco_contents/jbr/Contents/Home"; do
  if [ ! -e "$required_path" ]; then
    echo "缺少 DevEco 构建依赖：$required_path" >&2
    echo "可通过 DEVECO_STUDIO_CONTENTS 指定 DevEco Studio Contents 目录。" >&2
    exit 2
  fi
done

cleanup_staging() {
  case "$staging_root" in
    /tmp/bubu-harmony-build.*) rm -rf -- "$staging_root" ;;
  esac
}

if LC_ALL=C printf '%s' "$project_root" | grep -q '[^A-Za-z0-9_@.() /-]'; then
  staging_root=$(mktemp -d /tmp/bubu-harmony-build.XXXXXX)
  trap cleanup_staging EXIT HUP INT TERM
  rsync -a \
    --exclude '/.hvigor' \
    --exclude '/.idea' \
    --exclude '/build' \
    --exclude '/*/build' \
    --exclude '/oh_modules' \
    --exclude '/*/oh_modules' \
    "$project_root/" "$staging_root/"
  build_root="$staging_root"
  echo "工程路径含 DevEco 不支持的字符，已在临时 ASCII 路径构建：$build_root"
fi

wrapper_modules="$build_root/.hvigor/local-wrapper/node_modules/@ohos"
mkdir -p "$wrapper_modules"
ln -sfn "$hvigor_package" "$wrapper_modules/hvigor"
ln -sfn "$ohos_plugin" "$wrapper_modules/hvigor-ohos-plugin"

export NODE_HOME="$deveco_contents/tools/node"
export DEVECO_SDK_HOME="$deveco_contents/sdk"
export JAVA_HOME="$deveco_contents/jbr/Contents/Home"
export NODE_PATH="$build_root/.hvigor/local-wrapper/node_modules"
export PATH="$NODE_HOME/bin:$JAVA_HOME/bin:$PATH"

if [ "$#" -eq 0 ]; then
  set -- assembleHap --mode module -p product=default --no-daemon
fi

cd "$build_root"
"$node_bin" "$hvigor_bin" "$@"

if [ -n "$staging_root" ] && [ -d "$build_root/entry/build/default/outputs" ]; then
  mkdir -p "$project_root/entry/build/default/outputs"
  rsync -a "$build_root/entry/build/default/outputs/" "$project_root/entry/build/default/outputs/"
fi
