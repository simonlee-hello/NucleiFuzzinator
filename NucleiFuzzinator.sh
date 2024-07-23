#!/bin/bash
# -*- coding: utf-8 -*-

# 测试
# set -xeuo pipefail

# ANSI颜色代码
RED='\033[91m'
GREEN='\033[92m'
RESET='\033[0m'

# 显示帮助菜单的函数
display_help() {
    echo -e "NucleiFuzzinator是一个自动化工具,用于收集指定域名或域名文件,并通过Nuclei进行全面的Web应用漏洞扫描。\n"
    echo -e "使用方法: $0 [选项]\n\n"
    echo "选项:"
    echo "  -h, --help                      显示帮助信息"
    echo "  -d, --domain <domain>           用于扫描 XSS、SQLi、SSRF、Open-Redirect 等漏洞的单个域名"
    echo "  -f, --file <filename>           包含多个域名的文件"
    echo "  -p, --proxy <proxy>             请求代理，例如 http://127.0.0.1:8080"
    echo "  -P, --project <projectName>     项目名称，输出目录名，默认为output"
    exit 0
}
# 显示 ASCII Logo
display_logo(){
    # ASCII art
    echo -e "${RED}[-] "
    cat << "EOF"
   _  __         __    _ ____            _           __
  / |/ /_ ______/ /__ (_) __/_ ________ (_)__  ___ _/ /____  ____
 /    / // / __/ / -_) / _// // /_ /_ // / _ \/ _ `/ __/ _ \/ __/
/_/|_/\_,_/\__/_/\__/_/_/  \_,_//__/__/_/_//_/\_,_/\__/\___/_/

                               Made by leeissonba (simonlee-hello)
EOF
    echo -e "${RESET}"
}
# 检查 Go 环境
check_go_env(){
    if ! command -v go &> /dev/null; then
        echo "未找到 Go，请先安装 Go 并设置相应的环境变量。"
        echo "安装完成后请手动设置以下环境变量："
        echo "  - GOROOT: 指向 Go 的安装目录 export GOROOT=\$HOME/go export PATH=\$GOROOT/bin:\$PATH"
        echo "  - GOPATH: 指向您的 Go 工作目录 export GOPATH=\$HOME/gopath/go export PATH=\$GOPATH/bin:\$PATH"
        echo "  - GOMODCACHE: 指向您的 Go 工作目录 export GOMODCACHE=\$HOME/go/pkg/mod"
        exit 1
    fi
}
# 检查 pip3 环境
check_pip3_env(){
    if ! command -v pip3 &> /dev/null; then
        echo "未找到 pip3，请先安装 pip3"
        echo "  - curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py"
        echo "  - python3 get-pip.py"
        exit 1
    fi
}
# 检查并安装命令
check_and_install() {
    local cmd="$1"
    local install_cmd="$2"
    if ! command -v "$cmd" &> /dev/null; then
        echo "正在安装 $cmd..."
        if ! $install_cmd; then
            echo -e "${RED}[-] 安装 $cmd 失败，请手动安装。${RESET}"
            exit 1
        fi
    fi
}
# 运行 httpx
run_httpx() {
    local input_file="$1"
    local output_file="$2"
    echo "正在对收集到的 URL 进行 httpx 探活..."
    httpx $proxy_arg $httpx_args -l "$input_file" -o "$output_file" > /dev/null || exit 1
    local line_count
    line_count=$(wc -l < "$output_file" | awk '{print $1}')
    echo -e "${GREEN}[+] httpx 执行完成。找到 $line_count 个活跃的 URL。${RESET}"
}
# 运行 subfinder
run_subfinder() {
    local output_file="$1"
    echo "正在使用 Subfinder 查找子域..."
    subfinder $subfinder_args -o "$output_file" > /dev/null || exit 1
    local line_count
    line_count=$(wc -l < "$output_file" | awk '{print $1}')
    echo -e "${GREEN}[+] subfinder 执行完成。找到 $line_count 个子域。${RESET}"
}
# 运行 katana
run_katana() {
    local input_file="$1"
    local output_file="$2"
    if [ ! -s "$input_file" ]; then
        echo -e "${RED}[-] 警告：$input_file 文件为空。跳过执行 katana 命令。${RESET}"
        return 1
    fi
    echo "正在运行 katana..."
    katana -silent $proxy_arg -list "$input_file" -headless -no-incognito -xhr -d 5 -jc -aff -ef $excluded_extentions -o "$output_file" > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}[-] katana 在 headless 模式下报错。尝试在非 headless 模式下运行。${RESET}"
        katana -silent $proxy_arg -list "$input_file" -no-incognito -xhr -d 5 -jc -aff -ef $excluded_extentions -o "$output_file" > /dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}[-] katana 在非 headless 模式下仍然报错。请检查依赖和配置。${RESET}"
            return 1
        fi
    fi
    local line_count
    line_count=$(wc -l < "$output_file" | awk '{print $1}')
    echo -e "${GREEN}[+] katana 执行完成。总共找到 $line_count 个活跃的 URL。${RESET}"
}
# 运行nuclei的函数
run_nuclei() {
    local url_file="$1"
    local output_file="$2"
    echo "更新Nuclei templates"
    nuclei -ut -up -silent
    echo "正在对收集到的 URL 运行Nuclei"
    nuclei $proxy_arg $nuclei_fuzzing_args -l "$url_file" -o "$output_file" || exit 1
}

# 检查 gau、nuclei、httpx 和 uro 是否已安装
check_go_env
check_pip3_env
check_and_install gau "go install github.com/lc/gau/v2/cmd/gau@latest"
check_and_install subfinder "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
check_and_install nuclei "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
check_and_install httpx "go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
check_and_install anew "go install github.com/tomnomnom/anew@latest"
check_and_install katana "go install github.com/projectdiscovery/katana/cmd/katana@latest"
check_and_install uro "pip3 install uro"

# 命令行参数默认值
proxy=""
domain=""
filename=""
project=""
proxy_arg=""

# 解析命令行参数
while getopts ":hd:f:p:P:" opt; do
    case $opt in
        h) display_help ;;
        d) domain="$OPTARG" ;;
        f) filename="$OPTARG" ;;
        p) proxy="$OPTARG" ;;
        P) project="$OPTARG" ;;
        \?) echo -e "${RED}[-] 无效选项: -$OPTARG${RESET}" >&2; display_help ;;
    esac
done
# 检查并设置代理参数
if [ -n "$proxy" ]; then
    proxy_arg="-proxy $proxy"
fi
# 检查是否提供了域名或文件名
if [ -z "$domain" ] && [ -z "$filename" ]; then
    echo -e "${RED}[-] 请使用 -d 提供域名，或使用 -f 提供包含多个域/URL 的文件。${RESET}"
    display_help
fi

# 默认变量值
excluded_extentions="png,jpg,gif,jpeg,swf,woff,svg,pdf,json,css,js,webp,woff,woff2,eot,ttf,otf,mp4"
gau_args="--blacklist $excluded_extentions --subs --threads 10"
[ -n "$proxy" ] && gau_args+=" --proxy $proxy"
httpx_args="-silent -mc 200 -threads 200"
nuclei_fuzzing_args="-dast -nh -rl 10"

display_logo


# 设置项目名称和输出文件
project=${project:-output}
url_file="$project/$( [ -n "$domain" ] && echo "$domain.txt" || echo "allurls.txt" )"
gau_result="$project/gau_result.txt"
gau_alive_result="$project/gau_alive_result.txt"
katana_result="$project/katana_result.txt"
nuclei_fuzzing_output_file="$project/nuclei_fuzzing_results_$(date +%Y%m%d%H%M%S).txt"
subfinder_domains_file="$project/subfinder_urls.txt"
subfinder_alive_urls_file="$project/subfinder_alive_urls.txt"


# 检查输出目录是否存在，不存在则创建
mkdir -p "$project"

# 检查是否已运行gau 并创建了输出文件
if [ ! -f "$gau_result" ]; then
    if [ -n "$domain" ]; then
        echo "正在对 $domain 运行 gau"
        gau $gau_args "$domain" --o "$gau_result" || exit 1
    elif [ -n "$filename" ]; then
        echo "正在对文件 $filename 运行 gau"
        cat "$filename" | gau $gau_args --o "$gau_result" || exit 1
    fi
fi
line_count=$(wc -l < "$gau_result" | awk '{print $1}')
echo -e "${GREEN}[+] gau 执行完成。找到 $line_count 个活跃的 URL。${RESET}"

# 运行httpx 函数

if [ ! -f "$gau_alive_result" ]; then
    run_httpx "$gau_result" "$gau_alive_result"
else
    echo "$gau_alive_result 已存在,跳过httpx探活"
fi

# 运行 subfinder
subfinder_args=$( [ -n "$domain" ] && echo "-d $domain -all -silent" || echo "-dL $filename -all -silent" )
if [ ! -f "$subfinder_domains_file" ]; then
    run_subfinder "$subfinder_domains_file"
else
    echo "$subfinder_domains_file 已存在,跳过subfinder子域名收集"
fi

# 运行httpx 在收集到的子域上
if [ ! -f "$subfinder_domains_file" ]; then
    echo -e "${RED}[-]  警告：$subfinder_domains_file 文件不存在。跳过运行httpx 命令。${RESET}"
else
    if [ ! -f "$subfinder_alive_urls_file" ]; then
        echo "正在对收集到的子域运行 httpx"
        httpx -l "$subfinder_domains_file" -ports=80,https:443,8080,https:8443,8000,8888 $httpx_args -o "$subfinder_alive_urls_file" > /dev/null || exit 1
        line_count=$(wc -l < "$subfinder_alive_urls_file" | awk '{print $1}')
        echo -e "${GREEN}[+] Httpx 探活子域执行完成。找到 $line_count 个活跃的 URL。${RESET}"
    else
        echo "$subfinder_alive_urls_file 已存在,跳过子域名httpx探活。"
    fi
fi

# 运行katana 函数
if [ ! -f "$katana_result" ]; then
    run_katana "$subfinder_alive_urls_file" "$katana_result"
else
    echo "$katana_result 已存在,跳过katana爬虫。"
fi

# 去重URL
if [ -f "$katana_result" ] && [ -f "$gau_alive_result" ]; then
    cat "$katana_result" "$gau_alive_result" | uro | anew "$url_file" > /dev/null
elif [ -f "$katana_result" ]; then
    cat "$katana_result" | uro | anew "$url_file" > /dev/null
elif [ -f "$gau_alive_result" ]; then
    cat "$gau_alive_result" | uro | anew "$url_file" > /dev/null
else
    echo "Neither $katana_result nor $gau_alive_result exists."
    exit 1
fi
line_count=$(wc -l < "$url_file" | awk '{print $1}')
echo -e "${GREEN}[+] URL去重完成。总共找到 $line_count 个活跃的 URL。${RESET}"

# 提取所有URL，方便做其他扫描
if [ ! -f "$project/websites.txt" ]; then
    sed -E 's#^(https?://[^/]+).*#\1#' "$url_file" | sort -u | tee "$project/websites.txt" > /dev/null
    line_count=$(wc -l < "$project/websites.txt" | awk '{print $1}')
    echo -e "${GREEN}[+] 所有存活websites已提取成功。共 $line_count 个website。\nnuclei完整扫描命令：${RED}[-] nuclei -l $project/websites.txt -nh -es info -et ssl,dns -p $proxy -o $project/nuclei_full_results_$(date +%Y%m%d%H%M%S).txt ${RESET} ${RESET}"
fi
# 运行nuclei 函数
[ -f "$url_file" ] && run_nuclei "$url_file" "$nuclei_fuzzing_output_file"
echo -e "${GREEN}[+] Nuclei 执行完成，结果保存在 $nuclei_fuzzing_output_file。${RESET}"
# 结束时显示一般消息
echo "扫描完成 - Happy Fuzzing"
