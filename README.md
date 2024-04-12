# NucleiFuzzinator

NucleiFuzzinator是一个自动化工具,用于收集指定域名或域名文件,并通过Nuclei进行全面的Web应用漏洞扫描。

## 工作流

1. gau收集Wayback Machine的urls
2. subfinder收集子域名
3. katana爬取子域名的所有urls
4. uro去重
5. nuclei fuzzing