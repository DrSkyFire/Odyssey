# Git快速提交脚本
# 使用方法：.\git_push.ps1 "提交说明"

param(
    [string]$message = "Update: 更新项目文件"
)

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "  Odyssey项目 Git推送脚本" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# 1. 检查Git状态
Write-Host "[1/5] 检查Git状态..." -ForegroundColor Yellow
git status

Write-Host ""
$continue = Read-Host "是否继续提交？(Y/N)"
if ($continue -ne "Y" -and $continue -ne "y") {
    Write-Host "取消操作。" -ForegroundColor Red
    exit
}

# 2. 添加所有更改
Write-Host ""
Write-Host "[2/5] 添加更改到暂存区..." -ForegroundColor Yellow
git add .

# 3. 查看将要提交的内容
Write-Host ""
Write-Host "[3/5] 将要提交的文件:" -ForegroundColor Yellow
git status --short

# 4. 提交到本地仓库
Write-Host ""
Write-Host "[4/5] 提交到本地仓库..." -ForegroundColor Yellow
Write-Host "提交说明: $message" -ForegroundColor Green
git commit -m "$message"

if ($LASTEXITCODE -ne 0) {
    Write-Host "提交失败！请检查错误信息。" -ForegroundColor Red
    exit
}

# 5. 推送到远程仓库
Write-Host ""
Write-Host "[5/5] 推送到GitHub远程仓库..." -ForegroundColor Yellow
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Green
    Write-Host "  ✅ 推送成功！" -ForegroundColor Green
    Write-Host "==================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "GitHub仓库: https://github.com/DrSkyFire/Odyssey" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Red
    Write-Host "  ❌ 推送失败！" -ForegroundColor Red
    Write-Host "==================================" -ForegroundColor Red
}

Write-Host ""
Write-Host "按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
