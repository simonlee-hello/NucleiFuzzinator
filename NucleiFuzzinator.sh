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

display_logo(){
    # ASCII art
    echo -e "${RED}"
    cat << "EOF"
   _  __         __    _ ____            _           __
  / |/ /_ ______/ /__ (_) __/_ ________ (_)__  ___ _/ /____  ____
 /    / // / __/ / -_) / _// // /_ /_ // / _ \/ _ `/ __/ _ \/ __/
/_/|_/\_,_/\__/_/\__/_/_/  \_,_//__/__/_/_//_/\_,_/\__/\___/_/

                               Made by leeissonba (simonlee-hello)
EOF
    echo -e "${RESET}"
}

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

# 检查命令是否存在的函数
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "正在安装 $1..."
        $2 || exit 1
    fi
}

# 运行httpx的函数
run_httpx() {
    local gau_result="$1"
    local url_file="$2"
    local line_count
    local httpx_command="httpx $proxy_arg $httpx_args"
    echo "正在对收集到的 URL 进行 httpx 探活..."
    cat "$gau_result" | $httpx_command -o "$url_file" || exit 1
    line_count=$(wc -l < "$url_file" | awk '{print $1}')
    echo -e "${GREEN}httpx 执行完成。找到 $line_count 个活跃的 URL。${RESET}"
}

# 运行subfinder的函数
run_subfinder() {
    local line_count
    echo "正在使用 Subfinder 查找子域..."
    $subfinder_command || exit 1
    line_count=$(wc -l < "$subfinder_domains_file" | awk '{print $1}')
    echo -e "${GREEN}subfinder 执行完成。找到 $line_count 个子域。${RESET}"
}

# 运行katana的函数
run_katana() {
    local subfinder_alive_urls_file="$1"
    local url_file="$2"
    local line_count
    # 检查 $subfinder_alive_urls_file 是否包含 URL
    if [ ! -s "$subfinder_alive_urls_file" ]; then
        echo -e "${RED}警告：$subfinder_alive_urls_file 文件为空。跳过执行 katana 命令。${RESET}"
        return 1
    fi
    katana -silent -list "$subfinder_alive_urls_file" -headless -no-incognito -xhr -d 5 -jc -aff -ef $excluded_extentions -o "$katana_result"
    cat "$katana_result" | uro | anew "$url_file"
    line_count=$(wc -l < "$url_file" | awk '{print $1}')
    echo -e "${GREEN}katana 执行完成。总共找到 $line_count 个活跃的 URL。${RESET}"
}

# 运行nuclei的函数
run_nuclei() {
    local url_file="$1"
    echo "更新Nuclei templates"
    nuclei -ut -up -silent
    echo "正在对收集到的 URL 运行Nuclei"
    echo -e "Nuclei_command : ${GREEN}cat $url_file | $nuclei_command ${RESET}"
    cat "$url_file" | $nuclei_command || exit 1
}

# 命令行参数默认值
proxy=""
domain=""
filename=""
project=""

# 默认变量值
output_domain_file=""
output_all_file=""
excluded_extentions="png,jpg,gif,jpeg,swf,woff,svg,pdf,json,css,js,webp,woff,woff2,eot,ttf,otf,mp4"
httpx_args="-silent -mc 200,301,302 -threads 200"
nuclei_fuzzing_args="-silent -dast -nh -rl 10"
proxy_arg=""



# 检查 gau、nuclei、httpx 和 uro 是否已安装
check_go_env
check_command gau "go install github.com/lc/gau/v2/cmd/gau@latest"
check_command subfinder "go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
check_command nuclei "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
check_command httpx "go install github.com/projectdiscovery/httpx/cmd/httpx@latest"
check_command anew "go install github.com/tomnomnom/anew@latest"
check_command katana "go install github.com/projectdiscovery/katana/cmd/katana@latest"
check_command uro "pip3 install uro"


display_logo


# 解析命令行参数
while getopts ":hd:f:p:P:" opt; do
    case $opt in
        h) display_help ;;
        d) domain="$OPTARG" ;;
        f) filename="$OPTARG" ;;
        p) proxy="$OPTARG" ;;
        P) project="$OPTARG" ;;
        \?) echo -e "${RED}无效选项: -$OPTARG${RESET}" >&2; display_help ;;
    esac
done

if [ -n "$proxy" ]; then
    proxy_arg="-proxy $proxy"
fi

# 检查是否提供了域名或文件名
if [ -z "$domain" ] && [ -z "$filename" ]; then
    echo -e "${RED}请使用 -d 提供域名，或使用 -f 提供包含多个域/URL 的文件。${RESET}"
    display_help
fi



# 根据域名或文件名设置输出文件
if [ -n "$domain" ]; then
    # 检查是否提供了项目名称
    if [ -z "$project" ]; then
        project=$domain
    fi
    output_domain_file="$project/$domain.txt"
else
    # 检查是否提供了项目名称
    if [ -z "$project" ]; then
        project="output"
    fi
    output_all_file="$project/allurls.txt"


fi

gau_result="$project/gau_result.txt"
katana_result="$project/katana_result.txt"
nuclei_fuzzing_output_file="$project/nuclei_fuzzing_results_$(date +%Y%m%d%H%M%S).txt"
subfinder_domains_file="$project/subfinder_urls.txt"
subfinder_alive_urls_file="$project/subfinder_alive_urls.txt"


# 检查输出目录是否存在，不存在则创建
if [ ! -d "$project" ]; then
    mkdir "$project"
fi

# 检查是否已运行gau 并创建了输出文件
if [ -n "$domain" ]; then
    if [ ! -f "$gau_result" ]; then
        echo "正在对 $domain 运行gau"
        gau_args="--blacklist $excluded_extentions --subs"
        [ -n "$proxy" ] && gau_args+=" --proxy $proxy"
        gau $gau_args $domain | uro > "$gau_result" || exit 1
    fi
else
    if [ ! -f "$gau_result" ]; then
        echo "正在对 $filename 中的 URL 运行gau"
        gau_args="--blacklist $excluded_extentions --subs"
        [ -n "$proxy" ] && gau_args+=" --proxy $proxy"
        cat "$filename" | gau $gau_args | uro > "$gau_result" || exit 1
    fi
fi

# 运行httpx 函数
if [ -n "$domain" ]; then
    url_file="$output_domain_file"
else
    url_file="$output_all_file"
fi

if [ ! -f "$url_file" ]; then
    run_httpx "$gau_result" "$url_file"
else
    echo "$gau_result 已存在,跳过httpx探活"
fi

# 运行subfinder 函数
# 定义 subfinder_command 变量，根据提供的域名或文件进行选择
if [ -n "$domain" ]; then
    subfinder_command="subfinder -d $domain -all -silent -o $subfinder_domains_file"
elif [ -n "$filename" ]; then
    subfinder_command="subfinder -dL $filename -all -silent -o $subfinder_domains_file"
fi

if [ ! -f "$subfinder_domains_file" ]; then
    run_subfinder
else
    echo "$subfinder_domains_file 已存在,跳过subfinder子域名收集"
fi

# 运行httpx 在收集到的子域上
if [ ! -f "$subfinder_domains_file" ]; then
    echo -e "${RED} 警告：$subfinder_domains_file 文件不存在。跳过运行httpx 命令。${RESET}"
else
    if [ ! -f "$subfinder_alive_urls_file" ]; then
        echo "正在对收集到的子域运行httpx"
        httpx -l "$subfinder_domains_file" -ports=80,443,8080,8443,8000,8888 $httpx_args -o "$subfinder_alive_urls_file" || exit 1
        line_count=$(wc -l < "$subfinder_alive_urls_file" | awk '{print $1}')
        echo -e "${GREEN}Httpx 探活子域执行完成。找到 $line_count 个活跃的 URL。${RESET}"
    else
        echo "$subfinder_alive_urls_file 已存在,跳过子域名httpx探活。"
    fi
fi

# 运行katana 函数
if [ ! -f "$katana_result" ]; then
    run_katana "$subfinder_alive_urls_file" "$url_file"
else
    echo "$katana_result 已存在,跳过katana爬虫。"
fi
# 提取所有URL，方便做其他扫描
if [ ! -f "$project/websites.txt" ]; then
    sed -E 's#^(https?://[^/]+).*#\1#' "$url_file" | sort -u | tee "$project/websites.txt"
    line_count=$(wc -l < "$project/websites.txt" | awk '{print $1}')
    echo -e "${GREEN}所有存活websites已提取成功。共 $line_count 个website。\nnuclei完整扫描命令：${RED}nuclei -l $project/websites.txt -nh -es info -et ssl,dns -p $proxy -o $project/nuclei_full_results_$(date +%Y%m%d%H%M%S).txt ${RESET} ${RESET}"
fi
# 运行nuclei 函数
# 定义 nuclei_command 变量
nuclei_command="nuclei $proxy_arg $nuclei_fuzzing_args -o $nuclei_fuzzing_output_file"
run_nuclei "$url_file"

# 结束时显示一般消息
echo "扫描完成 - Happy Fuzzing"