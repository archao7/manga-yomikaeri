#!/bin/zsh
# 双击会显示文件选择器，也可在终端传入一个 PDF、PNG 或 JPG 路径。
set -eu

project_dir=${0:A:h}
from_finder=0
if (( $# == 0 )); then
  from_finder=1
elif (( $# != 1 )) || [[ "$1" == '--help' || "$1" == '-h' ]]; then
  print '用法：双击本文件，或在终端传入一本 PDF / 一张 JPG、PNG 图片。'
  (( $# == 1 )) && exit 0
  exit 2
fi

fail() {
  print -u2 -r -- "$1"
  if (( from_finder )); then
    /usr/bin/osascript - "$1" <<'ALERT' || true
on run args
    display alert "漫画导入未完成" message (item 1 of args) buttons {"知道了"} default button 1
end run
ALERT
  fi
  exit 1
}

[[ -f "$project_dir/index.html" && -f "$project_dir/tools/ocr-pdf.swift" && -f "$project_dir/tools/ocr-page.swift" ]] ||
  fail '请先解压整个作品包，并将此文件保留在 index.html 旁边。'

if (( from_finder )); then
  input=$(/usr/bin/osascript <<'PICKER'
try
    return POSIX path of (choose file with prompt "选择一本 PDF，或一张 JPG、PNG 漫画图片" of type {"com.adobe.pdf", "public.jpeg", "public.png"})
on error number -128
    return ""
end try
PICKER
  ) || fail '无法打开文件选择器。也可从终端运行此脚本并传入漫画路径。'
  [[ -n "$input" ]] || exit 0
else
  input=${1:A}
fi
[[ -f "$input" && -r "$input" ]] || fail '漫画不存在或无法读取，请检查文件路径。'
kind=${input:e:l}

case "$kind" in
  pdf)
    book_dir="${input:r}-点读"
    marker="$book_dir/volume.mokuro"
    instructions='在阅读器展开「导入自己的漫画」，选择结果目录里的 volume.mokuro，再一次选中要读的页面 PNG。'
    ;;
  png|jpg|jpeg)
    book_dir=${input:h}
    marker="${input:r}.mokuro"
    instructions="在阅读器展开「导入自己的漫画」，选择「${marker:t}」和原图「${input:t}」。"
    ;;
  *) fail '支持直接转换 PDF、PNG 和 JPG/JPEG 文件。' ;;
esac

if [[ -f "$marker" ]]; then
  print -r -- '已找到对应路径的标注文件，这次直接使用已有结果，保留你的复习记录。'
else
  if [[ "$kind" == pdf && -e "$book_dir" ]]; then
    fail "目标目录已经存在，但里面没有 volume.mokuro。请先将已有目录改名，再重新运行：$book_dir"
  fi
  [[ -w "${input:h}" ]] || fail '漫画所在文件夹不可写。请将原文件复制到可以写入的文件夹后再试。'
  /usr/bin/xcode-select --print-path >/dev/null 2>&1 && /usr/bin/xcrun --find swift >/dev/null 2>&1 ||
    fail '首次识别需要 Apple 命令行工具。打开「终端」执行 xcode-select --install，在系统窗口完成安装后重新双击。只看样章可直接打开 index.html。'
  print -r -- '开始在 Mac 上识别横排日文。首次运行 Swift 可能需要等待片刻。'
  if [[ "$kind" == pdf ]]; then
    /usr/bin/xcrun swift "$project_dir/tools/ocr-pdf.swift" "$input" "$book_dir" ||
      fail '未能转换 PDF。请确认文件能够直接打开，并检查上方系统提示。'
  else
    /usr/bin/xcrun swift "$project_dir/tools/ocr-page.swift" "$input" "$marker" ||
      fail '未能识别这张图片。请尝试文字较清晰的横排日语图像，并检查上方系统提示。'
  fi
fi
print -r -- "标注：$marker"
print -r -- "$instructions"

if (( from_finder )); then
  /usr/bin/open -R "$marker" || true
  /usr/bin/open "$project_dir/index.html" || fail '无法打开浏览器。请双击作品包中的 index.html。'
fi
