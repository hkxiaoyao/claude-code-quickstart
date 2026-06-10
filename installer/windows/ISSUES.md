# Windows 安装器已知问题清单

> **生成时间**: 2026-06-10  
> **状态**: 待后续优化（当前变更范围仅限 macOS 对齐，不修改 Windows）  
> **来源**: macOS 核心模块重写过程中对比发现

---

## 1. 核心模块与步骤边界不清

### 问题描述
- `windows/core/Provider.ps1` (~810 行) 和 `windows/steps/ApiKey.ps1` 存在职责重叠
- `windows/core/McpManager.ps1` (~890 行) 和 `windows/steps/Mcp.ps1` 存在职责重叠
- 部分业务逻辑散落在步骤文件中，未充分抽取到 core

### 影响
- 代码重复，维护成本高
- 步骤文件过于臃肿（非薄包装）
- 违反 DRY 原则

### 建议方案
参考 macOS 重写后的结构：
- **core/Provider.ps1**: 承载全部供应商 CRUD + 切换 + Sync + 交互菜单逻辑
- **steps/ApiKey.ps1**: 仅保留 `Test-ApiKeyInstalled` / `Install-ApiKey` / `Verify-ApiKey` 契约函数，内部委托 core
- **core/McpManager.ps1**: 承载 MCP 状态查看、禁用/启用/删除、批量切换、Rules 渲染
- **steps/Mcp.ps1**: 仅保留安装契约，管理逻辑交给 core

---

## 2. UI 函数命名与调用一致性

### 问题描述（待核实）
- macOS 重写时发现 `ccq_ui_*` 系列函数（假函数名）与实际 `ccq_show_*` 不匹配
- Windows 是否存在类似的 UI 函数别名、包装层或命名不一致问题，待核实

### 验证方法
```powershell
# 检查 core 模块调用的 UI 函数是否在 Ui.ps1 中定义
Select-String -Path "windows/core/*.ps1" -Pattern "Write-Ui|Show-" | Select-String -NotMatch "^#"
Get-Content "windows/core/Ui.ps1" | Select-String "^function (Write-Ui|Show-)"
```

---

## 3. 加载顺序与依赖声明

### 问题描述（待核实）
- macOS 需要在 `Install.ps1` 和 `Manage.ps1` 的 core 加载列表中显式登记新模块
- Windows 的 `Install.ps1` 和 `Manage.ps1` 是否也需要类似的显式加载顺序声明？
- 当前 Windows 加载机制是否支持动态发现，还是需要手动维护列表？

### 验证方法
```powershell
# 检查 Install.ps1 和 Manage.ps1 的 core 加载逻辑
Select-String -Path "windows/Install.ps1","windows/Manage.ps1" -Pattern "core.*ps1|dot.*source|\. \$"
```

---

## 4. 构建清单完整性

### 问题描述（待核实）
- macOS 需要在 `installer/contracts/build.json` 的 `MacOS.CoreFiles` 中登记新模块，否则构建产物不包含
- Windows 的 `build.ps1` 是否依赖 `build.json` 中的 `Windows.CoreFiles` 列表？
- 若 Windows 新增 core 模块，是否需要同步更新 `build.json`？

### 验证方法
检查 `installer/build.ps1` 中是否读取 `build.json` 的 `Windows.CoreFiles` 来决定打包哪些文件。

---

## 5. 函数命名风格不一致（低优先级）

### 问题描述
- macOS 使用 `ccq_<module>_<action>` 命名（如 `ccq_provider_show_status`）
- Windows 使用 `Verb-Noun` PowerShell 风格（如 `Show-ProviderStatus`）或 `<Module><Action>` 风格
- 两边风格差异较大，跨平台对齐时需要翻译

### 影响
- 跨平台代码审查时需要人工对应函数名
- 文档和错误信息中的函数名不统一

### 建议方案
- 保持 PowerShell 原生风格（`Verb-Noun`），不强制统一
- 在文档中提供命名映射表

---

## 6. 测试覆盖

### 问题描述
- macOS 和 Windows 核心模块都缺少单元测试或可重复的 shell 测试
- 重构风险高，依赖人工验证

### 建议方案
- 为 Provider 和 McpManager 核心模块编写 Pester 测试（Windows）
- 覆盖关键路径：CRUD、切换、Sync、状态查看

---

## 优先级建议

| 优先级 | 问题编号 | 预计收益 |
|--------|---------|---------|
| **P0** | 1 | 消除重复代码，降低维护成本 |
| **P1** | 2, 3, 4 | 确保加载正确性，避免运行时错误 |
| **P2** | 6 | 提升重构安全性 |
| **P3** | 5 | 改善跨平台一致性（体验优化）|

---

## 参考：macOS 重写后的文件大小对比

| 文件 | 重写前 | 重写后 | 变化 |
|------|--------|--------|------|
| `core/Provider.zsh` | 1005 行（假 UI 版） | 547 行（真实逻辑版） | -458 行 (-46%) |
| `steps/ApiKey.zsh` | 519 行 | 64 行 | -455 行 (-88%) |
| `core/McpManager.zsh` | 550 行（假 UI 版） | 135 行（真实逻辑版） | -415 行 (-75%) |
| `steps/Mcp.zsh` | 420 行 | 318 行 | -102 行 (-24%) |

**净减少代码**: ~1000 行  
**消除重复**: ApiKey 和 Mcp 步骤文件从"自包含全部逻辑"变为"薄包装委托 core"

Windows 若按同样模式重构，预计可消除类似规模的重复代码。
