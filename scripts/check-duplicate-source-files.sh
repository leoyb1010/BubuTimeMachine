#!/bin/bash
set -euo pipefail

# Finder/网盘复制冲突常生成 "Foo 2.swift"、"test_x 2.py"。这类文件会被
# xcodegen 或 pytest 自动收进构建，曾造成重复编译和测试数量虚增。
pattern='(^|/).+ [0-9]+\.(swift|m|mm|h|py|js|jsx|ts|tsx|json|ya?ml|plist)$'

duplicates=()
while IFS= read -r path; do
  # `git ls-files` 在文件已删除但尚未提交时仍会列出路径；只检查当前工作树。
  [[ -e "$path" ]] || continue
  if [[ "$path" =~ $pattern ]]; then
    duplicates+=("$path")
  fi
done < <(git ls-files)

if ((${#duplicates[@]} > 0)); then
  echo "发现疑似复制冲突的源码/配置文件：" >&2
  printf '  %s\n' "${duplicates[@]}" >&2
  echo "请比较内容并保留唯一的规范文件名。" >&2
  exit 1
fi

echo "未发现带数字副本后缀的源码/配置文件。"
