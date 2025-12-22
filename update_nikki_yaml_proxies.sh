#!/bin/sh

# 脚本功能：
# 1. 从机场官方订阅中获取节点，并将其添加到 Clash.Meta (nikki) 配置文件中。
# 2. 将用户自定义的节点从 my_proxies.yaml 文件中读取，并添加到配置文件中。
# 3. 生成最终可用的 Clash.Meta 配置文件。
# 4. 支持自定义配置 proxy-providers.Airport_01 的相关参数。

# -----------------------------------------------------------------------------
# 配置区
# -----------------------------------------------------------------------------

# 机场官方订阅链接
url="" # 请在这里填入你的机场订阅链接

# 模板地址 (Clash.Meta 配置文件模板)
template_url="https://gh-proxy.com/https://raw.githubusercontent.com/ZhuDe123/clash_rule/refs/heads/main/nikkiConfig_all.yaml"

# 自定义节点文件路径
# 假设 my_proxies.yaml 和脚本在同一目录下，如果不在，请提供完整路径，例如：/etc/nikki/my_proxies.yaml
my_proxies_file="/etc/nikki/profiles/my_proxies.yaml"

# 新增：可配置的 proxy-providers.Airport_01 参数
airport_url="www.baidu.com" # proxy-providers.Airport_01.url 配置项
additional_prefix="cf节点" # proxy-providers.Airport_01.override.additional-prefix 配置项

# -----------------------------------------------------------------------------
# 文件路径定义 (通常无需修改)
# -----------------------------------------------------------------------------

# 官方订阅下载保存路径
online_yaml="/etc/nikki/profiles/yifenjichang_online.yaml"
# 模板文件下载保存路径
template_yaml="/etc/nikki/profiles/yifenjichang-template.yaml"
# 最终生成的目标配置文件路径
target_yaml="/etc/nikki/profiles/yifenjichang.yaml"
# 临时工作文件路径
temp_yaml="/tmp/yifenjichang_temp.yaml"

# 临时代理内容文件
temp_online_proxies="/tmp/online_proxies.tmp"
temp_my_proxies="/tmp/my_proxies.tmp"
temp_all_proxies="/tmp/all_proxies.tmp" # 新增：合并所有代理的临时文件

# -----------------------------------------------------------------------------
# 脚本执行
# -----------------------------------------------------------------------------

echo "--- 开始更新 Clash.Meta 配置文件 ---"

# 启用错误检查，任何命令失败都会导致脚本退出
set -e

# 1. 下载机场官方订阅
echo "1. 正在下载机场官方订阅..."
rm -f "$online_yaml" # 使用 -f 避免不存在时报错
curl -o "$online_yaml" --location --request GET "$url" --header 'User-Agent: Clash.meta'
echo "   机场订阅下载完成：$online_yaml"

# 2. 下载配置文件模板
echo "2. 正在下载配置文件模板..."
rm -f "$template_yaml"
curl -o "$template_yaml" --location --request GET "$template_url"
echo "   配置文件模板下载完成：$template_yaml"

# 3. 复制模板文件作为临时工作文件
cp -f "$template_yaml" "$temp_yaml"
echo "   已复制模板到临时文件：$temp_yaml"

# 4. 从 online.yaml 提取 proxies 块内容
echo "4. 正在从机场订阅中提取节点信息..."
proxies_content=$(awk '
  /^proxies:/ { in_proxies=1; next }
  /^[^ ]/ { if (in_proxies) in_proxies=0 }
  in_proxies { print }
' "$online_yaml")

if [ -z "$proxies_content" ]; then
  echo "   警告: $online_yaml 中未找到 proxies 内容。请检查订阅链接或文件内容。"
fi

# 5. 从 my_proxies.yaml 提取自定义 proxies 块内容
echo "5. 正在从自定义节点文件 $my_proxies_file 中提取节点信息..."
my_proxies_content=""
if [ -f "$my_proxies_file" ]; then
  my_proxies_content=$(awk '
    /^proxies:/ { in_proxies=1; next }
    /^[^ ]/ { if (in_proxies) in_proxies=0 }
    in_proxies { print }
  ' "$my_proxies_file")

  if [ -z "$my_proxies_content" ]; then
    echo "   警告: $my_proxies_file 中未找到 proxies 内容，将跳过添加自定义节点。"
  else
    echo "   已成功提取自定义节点。"
  fi
else
  echo "   警告: 自定义节点文件 $my_proxies_file 不存在，将跳过添加自定义节点。"
fi


# 6. 识别模板文件中 proxies 块的缩进
echo "6. 正在识别配置文件模板的缩进..."
indent=$(awk '
  /^proxies:/ {
    getline; # 读取下一行
    while (match($0, /^[ ]+/)) { # 匹配行首的空格
      print RLENGTH; # 打印匹配到的空格长度
      exit # 找到后退出
    }
  }
' "$temp_yaml")

# 如果没有找到缩进，默认为2
indent=${indent:-2}
echo "   识别到的缩进为：$indent 个空格。"

# 7. 生成缩进空格字符串
spaces=$(printf "%${indent}s" "")

# 8. 调整 online_yaml 提取内容的缩进并保存到临时文件
rm -f "$temp_online_proxies"
if [ -n "$proxies_content" ]; then
  echo "7.1 正在调整机场节点内容的缩进..."
  echo "$proxies_content" | awk -v spaces="$spaces" '
    { sub(/^ +/, spaces); print }
  ' > "$temp_online_proxies"

  if [ ! -s "$temp_online_proxies" ]; then
    echo "   错误: 机场节点临时文件生成失败。"
    exit 1
  fi
fi

# 9. 调整 my_proxies.yaml 提取内容的缩进并保存到临时文件
rm -f "$temp_my_proxies"
if [ -n "$my_proxies_content" ]; then
  echo "7.2 正在调整自定义节点内容的缩进..."
  echo "$my_proxies_content" | awk -v spaces="$spaces" '
    { sub(/^ +/, spaces); print }
  ' > "$temp_my_proxies"

  if [ ! -s "$temp_my_proxies" ]; then
    echo "   错误: 自定义节点临时文件生成失败。"
    exit 1
  fi
fi

# 10. 合并自定义节点和机场节点到同一个临时文件
echo "8. 正在合并自定义节点和机场节点..."
rm -f "$temp_all_proxies"
if [ -s "$temp_my_proxies" ]; then
  cat "$temp_my_proxies" >> "$temp_all_proxies"
  echo "   自定义节点已添加到合并文件。"
fi
if [ -s "$temp_online_proxies" ]; then
  cat "$temp_online_proxies" >> "$temp_all_proxies"
  echo "   机场节点已添加到合并文件。"
fi

if [ ! -s "$temp_all_proxies" ]; then
  echo "   警告: 没有可用的节点（自定义或机场）来添加到配置文件中。"
fi

# 11. 将合并后的所有节点插入到 temp_yaml 中 (在 proxies: 行之后)
if [ -s "$temp_all_proxies" ]; then
  echo "9. 正在将所有节点插入到配置文件中..."
  # 使用 sed 的 'r' 命令在 /^proxies:/ 行之后插入合并后的所有节点
  sed -i -e "/^proxies:/r $temp_all_proxies" "$temp_yaml"
  echo "   所有节点已成功插入。"
else
  echo "   跳过节点插入，因为没有可用的节点。"
fi

# 12. 更新 proxy-providers.Airport_01 相关配置
echo "10. 正在更新 proxy-providers.Airport_01 相关配置..."

# 更新 proxy-providers.Airport_01.url
sed -i "s|^\( *\)url:.*$|\1url: $airport_url|" "$temp_yaml"
echo "   已更新 proxy-providers.Airport_01.url 为: $airport_url"

# 更新 proxy-providers.Airport_01.override.additional-prefix
sed -i "s|^\( *\)additional-prefix:.*$|\1additional-prefix: '$additional_prefix'|" "$temp_yaml"
echo "   已更新 proxy-providers.Airport_01.override.additional-prefix 为: $additional_prefix"

# 13. 清理临时文件
echo "11. 清理临时文件..."
rm -f "$temp_online_proxies"
rm -f "$temp_my_proxies"
rm -f "$temp_all_proxies"
rm -f "$template_yaml"
echo "    临时文件清理完成。"

# 14. 将临时文件转为目标文件
echo "12. 移动临时文件到目标位置：$target_yaml"
rm -f "$target_yaml" # 确保目标文件不存在，避免 mv 报错
mv "$temp_yaml" "$target_yaml"
echo "    配置文件生成成功！"

# 15. 更新geo数据库 (如果需要，取消注释)
# echo "13. 正在更新 Geo 数据库..."
# rm -f /etc/nikki/run/geoip.dat
# curl -o /etc/nikki/run/geoip.dat https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat
# rm -f /etc/nikki/run/geosite.dat
# curl -o /etc/nikki/run/geosite.dat https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat
# rm -f /etc/nikki/run/country.mmdb
# curl -o /etc/nikki/run/country.mmdb https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb
# rm -f /etc/nikki/run/GeoLite2-ASN.mmdb
# curl -o /etc/nikki/run/GeoLite2-ASN.mmdb https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb
# echo "    Geo 数据库更新完成。"

# 16. 重启nikki服务
echo "13. 正在重启 nikki 服务..."
/etc/init.d/nikki restart
echo "    nikki 服务重启完成。"

echo "--- Clash.Meta 配置文件更新成功！ ---"