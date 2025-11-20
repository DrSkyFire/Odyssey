# GitHub远程仓库整理操作指南

本指南提供GitHub仓库的详细优化步骤。

---

## 📋 当前仓库状态

- **仓库地址**：https://github.com/DrSkyFire/Odyssey
- **分支**：main
- **最新提交**：6c423e8 (docs: 添加文档整理完成总结)
- **同步状态**：✅ 本地与远程已同步

---

## 🎯 立即操作（推荐，5分钟）

### 步骤1：设置仓库描述和主题

1. 访问：https://github.com/DrSkyFire/Odyssey

2. 点击页面右上角的 **⚙️ Settings**

3. 在"General"页面找到"About"部分，点击右侧的 **齿轮图标**

4. 填写以下内容：

**Description（描述）**：
```
基于FPGA的高性能双通道信号分析与自动测试系统 | 35MSPS双通道采样 | 8192点FFT频谱分析 | 数字锁相放大微弱信号检测 | 自动测试 | HDMI 720p实时显示
```

**Website（可选）**：
```
如果有演示视频，填写链接
```

**Topics（主题标签，至少添加10个）**：
```
fpga
verilog
signal-analysis
spectrum-analyzer
fft
lock-in-amplifier
hdmi
adc
embedded-systems
digital-signal-processing
oscilloscope
competition-project
pango-fpga
ms9280
```

5. **勾选以下选项**：
   - ✅ Include in the home page

6. 点击 **Save changes**

---

### 步骤2：优化README徽章

在README.md文件开头添加项目徽章（可选，增强视觉效果）：

访问仓库，点击README.md，点击编辑（铅笔图标），在第一行下方添加：

```markdown
<div align="center">

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)
![FPGA](https://img.shields.io/badge/FPGA-Pango%20PGL50H-orange.svg)
![HDL](https://img.shields.io/badge/HDL-Verilog-green.svg)
![Status](https://img.shields.io/badge/Status-Competition%20Project-red.svg)
![Version](https://img.shields.io/badge/Version-v2.0-brightgreen.svg)
![Stars](https://img.shields.io/github/stars/DrSkyFire/Odyssey?style=social)

**基于FPGA的高性能双通道信号分析与自动测试系统**

[📖 文档](docs/文档索引.md) | [🚀 快速开始](#-快速使用指南) | [💡 创新点](#-创新点) | [📊 性能对比](#-性能指标与对比)

</div>

---
```

然后提交更改。

---

### 步骤3：创建Release版本

1. 访问：https://github.com/DrSkyFire/Odyssey/releases

2. 点击 **Create a new release**

3. 填写以下内容：

**Choose a tag（标签）**：
```
v2.0
```

**Release title（标题）**：
```
v2.0 - 时序优化版 ⚡
```

**Description（描述）**：
```markdown
## 🎉 v2.0 重大更新

### ⚡ 时序优化突破

- **ADC时钟域**：WNS -11.889ns → +2.5ns（改善14.4ns）
- **HDMI时钟域**：WNS -5.114ns → +0.8ns（改善5.9ns）
- **系统时钟域**：WNS -3.489ns → +1.2ns（改善4.7ns）
- **所有时钟域WNS全部转正** ✅

### 🚀 性能提升

- FFT吞吐率：9 FFT/s → 12.2 FFT/s（**+35%**）
- 参数更新率：5Hz → 10Hz（**+100%**）
- 系统稳定性：连续运行48小时无错误

### ✨ 新增功能

- 锁相放大HDMI实时显示窗口（左上角浮窗）
- 自动测试HDMI显示格式优化（单位显示+前导零抑制）
- SNR估算显示（0-60dB实时显示）

### 🔧 核心优化技术

1. **查找表（LUT）替代除法**
   - SNR计算：7档查找表
   - 延迟：>40ns → <5ns
   - 节省：约1500 LUT

2. **BCD场消隐期预计算**
   - 在HDMI场消隐期间完成所有BCD转换
   - 避免HDMI像素时钟域除法运算
   - 时序改善：5.9ns

3. **流水线设计**
   - FFT控制器3级流水线
   - 参数测量2级流水线
   - 提升吞吐率35%

### 🐛 Bug修复

- 修复`weak_signal_detector.v` SNR除法时序违例
- 修复`signal_analyzer_top.v` auto_test输入信号未定义
- 修复`hdmi_display_ctrl.v` 频率/幅度单位显示缺失
- 修复占空比/THD前导零未抑制问题

### 📦 下载文件

- **signal_analyzer_top.sbit**：FPGA比特流文件（直接下载到开发板）
- **源代码**：完整Verilog源代码（含IP核配置）

### 📚 文档

- [README.md](README.md) - 项目主文档（比赛展示版）
- [文档索引](docs/文档索引.md) - 56篇技术文档分类索引
- [ADC时序优化报告](ADC时序违例修复报告.md) - 详细优化过程

---

**完整更新日志**：[CHANGELOG.md](docs/CHANGELOG.md)

**比赛项目** | **Apache License 2.0** | **© 2025 DrSkyFire**
```

4. **Attach binaries（上传文件，可选）**：
   - 上传 `generate_bitstream/signal_analyzer_top.sbit`（如果有）
   - 或在Description中说明："比特流文件请编译源代码生成"

5. 勾选 **Set as the latest release**

6. 点击 **Publish release**

---

## 📸 中期操作（1小时，强烈推荐）

### 步骤4：上传HDMI显示截图

1. 连接HDMI显示器，拍摄或截图以下界面：
   - `hdmi_main_interface.jpg` - 主界面（参数表格+频谱图）
   - `auto_test_interface.jpg` - 自动测试界面
   - `lock_in_amplifier.jpg` - 锁相放大窗口特写
   - `led_indicator.jpg` - LED指示灯效果（用手机拍摄开发板）

2. 创建目录并上传：
   ```powershell
   mkdir docs\images
   # 将图片复制到docs\images\目录
   git add docs/images/
   git commit -m "docs: 添加HDMI显示界面截图"
   git push origin main
   ```

3. 在README.md的"功能演示"章节添加图片引用：
   ```markdown
   ### HDMI显示界面
   
   <div align="center">
   <img src="docs/images/hdmi_main_interface.jpg" width="700" alt="主界面">
   <p><i>主界面：双通道参数测量 + FFT频谱分析 + 锁相放大窗口</i></p>
   </div>
   ```

---

## 🔧 长期优化（可选）

### 步骤5：启用GitHub Pages

1. 访问：https://github.com/DrSkyFire/Odyssey/settings/pages

2. 在"Build and deployment"部分：
   - Source: **Deploy from a branch**
   - Branch: **main** / **docs** folder
   - 点击 **Save**

3. 等待几分钟后，访问：
   ```
   https://drSkyFire.github.io/Odyssey/
   ```

4. 将`docs/文档索引.md`重命名为`docs/index.md`作为首页

### 步骤6：整理根目录Markdown文档

将根目录的技术文档移动到`docs/`子目录：

```powershell
# 创建子目录
mkdir docs\核心技术
mkdir docs\时序优化  
mkdir docs\问题修复
mkdir docs\用户指南

# 移动文档（示例）
Move-Item "高精度*.md" docs\核心技术\
Move-Item "时序*.md" docs\时序优化\
Move-Item "*问题*.md" docs\问题修复\
Move-Item "*修复*.md" docs\问题修复\

# 提交更改
git add .
git commit -m "refactor: 整理文档目录结构"
git push origin main
```

然后更新`docs/文档索引.md`中的链接。

### 步骤7：添加CONTRIBUTING.md

创建贡献指南（如果希望开源社区参与）：

```markdown
# 贡献指南

感谢您对Odyssey项目的关注！

## 报告问题

请使用[GitHub Issues](https://github.com/DrSkyFire/Odyssey/issues)报告Bug或提出建议。

## 贡献代码

1. Fork本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add: 添加某某功能'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交Pull Request

## 代码规范

- 遵循Verilog HDL编码规范
- 添加必要的注释
- 确保时序满足要求（WNS≥0）

## 联系方式

- GitHub: [@DrSkyFire](https://github.com/DrSkyFire)
- Issues: https://github.com/DrSkyFire/Odyssey/issues
```

---

## ✅ 完成检查清单

请按顺序完成以下项目：

### 立即操作（必做）✅
- [ ] 设置仓库描述（Description）
- [ ] 添加Topics标签（至少10个）
- [ ] 创建v2.0 Release版本

### 短期操作（强烈推荐）⭐
- [ ] 在README添加项目徽章
- [ ] 上传HDMI显示截图（4张）
- [ ] 在README中引用截图

### 长期优化（可选）
- [ ] 启用GitHub Pages
- [ ] 整理文档目录结构
- [ ] 添加CONTRIBUTING.md
- [ ] 创建项目Wiki

---

## 📊 整理效果预期

完成以上操作后，您的GitHub仓库将具备：

| 项目 | 当前 | 优化后 |
|------|------|--------|
| 仓库描述 | ❌ 无 | ✅ 清晰的功能介绍 |
| Topics标签 | ❌ 0个 | ✅ 10+个 |
| 视觉效果 | ⭐⭐ | ⭐⭐⭐⭐⭐ 徽章+截图 |
| Release版本 | ❌ 无 | ✅ v2.0正式版 |
| 文档组织 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ Pages+Wiki |
| 专业度评分 | 70分 | 95分 |
| GitHub搜索可见性 | 低 | 高（Tags+Description） |

---

## 🔗 快速链接

- **仓库主页**：https://github.com/DrSkyFire/Odyssey
- **设置页面**：https://github.com/DrSkyFire/Odyssey/settings
- **创建Release**：https://github.com/DrSkyFire/Odyssey/releases/new
- **GitHub Pages设置**：https://github.com/DrSkyFire/Odyssey/settings/pages

---

## 💡 额外建议

### 提升GitHub Star数量

1. **在README中添加"Star"号召**（已添加）
2. **分享到社交媒体**：
   - Twitter/X
   - Reddit (r/FPGA, r/embedded)
   - FPGA论坛
   - 知乎/CSDN博客

3. **添加到Awesome列表**：
   - [awesome-fpga](https://github.com/Vitorian/awesome-fpga)
   - [awesome-verilog](https://github.com/m-labs/awesome-verilog)

### 提升项目可见性

1. **写技术博客**：详细介绍时序优化技术
2. **录制演示视频**：上传到B站/YouTube
3. **参与FPGA社区讨论**：带上项目链接

---

<div align="center">

**按照本指南操作后，您的GitHub仓库将展现出专业水准！**

**预计完成时间：立即操作5分钟 + 短期操作1小时 = 约1小时**

**© 2025 DrSkyFire**

</div>
