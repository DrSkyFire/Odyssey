# 清理GitHub仓库根目录脚本
# 功能：移动文档和脚本到合适的目录，删除临时文件

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  清理GitHub仓库根目录" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# 创建必要的子目录
Write-Host "[1/4] 创建目标目录..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path "docs\技术文档\核心技术" -Force | Out-Null
New-Item -ItemType Directory -Path "docs\技术文档\时序优化" -Force | Out-Null
New-Item -ItemType Directory -Path "docs\技术文档\问题修复" -Force | Out-Null
New-Item -ItemType Directory -Path "docs\技术文档\功能设计" -Force | Out-Null
New-Item -ItemType Directory -Path "docs\技术文档\HDMI显示" -Force | Out-Null
New-Item -ItemType Directory -Path "scripts" -Force | Out-Null
New-Item -ItemType Directory -Path "temp" -Force | Out-Null
Write-Host "  ✓ 目录创建完成" -ForegroundColor Green

# 移动技术文档到 docs/技术文档/
Write-Host ""
Write-Host "[2/4] 移动技术文档..." -ForegroundColor Yellow

# 核心技术文档
$coreDocs = @(
    "高精度双通道相位差测量-实现总结.md",
    "高精度相位差测量实现报告.md",
    "时域相位差测量方案.md",
    "相位差测量快速使用指南.md",
    "微弱信号锁相放大功能展示视频拍摄步骤.md",
    "微弱信号锁相放大功能检查报告.md",
    "信号测量时间效应分析报告.md",
    "噪声抑制与响应速度折中方案.md",
    "signal_measure_optimization_summary.md"
)

foreach ($doc in $coreDocs) {
    if (Test-Path $doc) {
        Move-Item -Path $doc -Destination "docs\技术文档\核心技术\" -Force
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
}

# 时序优化文档
$timingDocs = @(
    "ADC时序违例修复报告.md",
    "ADC时钟域时序违例修复报告.md",
    "时序优化总结.md",
    "时序优化方案B+D实施报告.md",
    "BCD优化后时序分析报告.md",
    "BCD方案实现进度.md",
    "BCD直接存储优化完成报告.md",
    "BCD直接存储方案.md"
)

foreach ($doc in $timingDocs) {
    if (Test-Path $doc) {
        Move-Item -Path $doc -Destination "docs\技术文档\时序优化\" -Force
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
}

# 问题修复文档
$fixDocs = @(
    "相位差模块问题检查报告.md",
    "相位差模块修复对比.md",
    "自动测试模块问题检查报告.md",
    "按键冲突修复报告.md",
    "按键冲突修复总结.md",
    "AI自动识别模块检查报告.md"
)

foreach ($doc in $fixDocs) {
    if (Test-Path $doc) {
        Move-Item -Path $doc -Destination "docs\技术文档\问题修复\" -Force
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
}

# 功能设计文档
$designDocs = @(
    "自动检测功能层级设计方案.md",
    "自动检测功能使用手册.md",
    "自动测试功能使用指南.md",
    "按键功能分配表.md"
)

foreach ($doc in $designDocs) {
    if (Test-Path $doc) {
        Move-Item -Path $doc -Destination "docs\技术文档\功能设计\" -Force
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
}

# HDMI显示文档
$hdmiDocs = @(
    "锁相放大HDMI显示完成报告.md",
    "锁相放大HDMI显示实施总结.md",
    "锁相放大HDMI显示实施指南.md",
    "锁相放大HDMI显示补丁.md",
    "自动测试HDMI显示格式优化报告.md",
    "自动测试HDMI显示检查报告.md"
)

foreach ($doc in $hdmiDocs) {
    if (Test-Path $doc) {
        Move-Item -Path $doc -Destination "docs\技术文档\HDMI显示\" -Force
        Write-Host "  ✓ $doc" -ForegroundColor Green
    }
}

# 移动Python脚本到 scripts/
Write-Host ""
Write-Host "[3/4] 移动脚本文件..." -ForegroundColor Yellow

$scripts = @(
    "generate_hann_window.py",
    "generate_ascii_font.py",
    "generate_bcd_lut.py",
    "generate_bcd_rom.py",
    "refactor_table_display.py",
    "add_lia_display.py",
    "fix_color.ps1",
    "fix2.ps1"
)

foreach ($script in $scripts) {
    if (Test-Path $script) {
        Move-Item -Path $script -Destination "scripts\" -Force
        Write-Host "  ✓ $script" -ForegroundColor Green
    }
}

# 移动临时文件到 temp/
Write-Host ""
Write-Host "[4/4] 移动临时文件..." -ForegroundColor Yellow

$tempFiles = @(
    "param_table_template.v",
    "table_display_new.v",
    "bcd_lut_generated.v",
    "bcd_rom_data.v",
    "test_compile.txt",
    "msg_level.txt",
    "source.zip",
    "cfg_verify_result.sbit",
    "rdfile_2025_11_6_22_46_58",
    "multiseed_summary.csv"
)

foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        Move-Item -Path $file -Destination "temp\" -Force
        Write-Host "  ✓ $file" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "==================================" -ForegroundColor Green
Write-Host "  清理完成！" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host ""
Write-Host "目录结构：" -ForegroundColor Cyan
Write-Host "  docs/技术文档/" -ForegroundColor White
Write-Host "    ├─ 核心技术/        (9个文档)" -ForegroundColor Gray
Write-Host "    ├─ 时序优化/        (8个文档)" -ForegroundColor Gray
Write-Host "    ├─ 问题修复/        (6个文档)" -ForegroundColor Gray
Write-Host "    ├─ 功能设计/        (4个文档)" -ForegroundColor Gray
Write-Host "    └─ HDMI显示/        (6个文档)" -ForegroundColor Gray
Write-Host "  scripts/              (8个脚本)" -ForegroundColor White
Write-Host "  temp/                 (10个临时文件)" -ForegroundColor White
Write-Host ""
Write-Host "下一步：" -ForegroundColor Yellow
Write-Host "1. 检查移动后的文件是否正确" -ForegroundColor White
Write-Host "2. 更新 docs/文档索引.md 中的链接" -ForegroundColor White
Write-Host "3. 运行 git status 查看更改" -ForegroundColor White
Write-Host "4. 提交更改并推送到远程仓库" -ForegroundColor White
Write-Host ""
