# Python脚本归档说明

本目录存放已使用、未使用或过时的Python脚本。

## 📜 归档脚本分类

### 🔤 字符ROM生成脚本（未使用）
- `generate_ascii_font.py` - ASCII字体生成
- `generate_char_map_rom.py` - 字符映射ROM生成
- `generate_compact_char_rom.py` - 紧凑型字符ROM生成
- `generate_minimal_char_rom.py` - 最小字符ROM生成

**状态**: 已创建但未集成到项目
**原因**: 时序优化方案未实施，当前使用硬编码字符生成逻辑

### 🔍 分析和验证脚本（已完成）
- `analyze_char_usage.py` - 字符使用频率分析
- `verify_char_rom_integration.py` - 字符ROM集成验证

**用途**: 临时分析脚本，已完成验证工作

### 🔄 重构脚本（未实施）
- `refactor_char_pipeline.py` - 字符管道重构脚本

**状态**: 计划但未实施
**原因**: ROM重构方案风险较大，用户选择延迟处理

### ✅ 已集成脚本
- `generate_hann_window.py` - Hann窗系数生成脚本

**状态**: ✅ 已完成并集成
**成果**: 生成的 `hann_window_8192.coe` 已成功集成到FFT IP核
**时间**: 2025-10-30

## 🗂️ 归档时间
- 2025-10-31: 项目清理，移除已完成和未使用的脚本

## 💡 脚本使用说明

### 如需重新生成Hann窗系数：
```bash
python generate_hann_window.py
```
输出: `hann_window_8192.coe` (用于紫光同创ROM IP核)

### 如需实施字符ROM优化：
1. 选择合适的生成脚本（compact/minimal）
2. 生成COE文件
3. 在紫光同创IP核中配置ROM
4. 修改 `hdmi_display_ctrl.v` 替换字符生成逻辑
5. 重新综合并验证时序

**警告**: ROM重构需要完整的测试流程，建议先在仿真中验证！
