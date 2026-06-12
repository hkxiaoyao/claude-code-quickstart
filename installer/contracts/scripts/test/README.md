# claude-config-drift.js 测试样例

本目录包含 `claude-config-drift.js` 的测试样例。

## 测试样例

### 1. 空 settings.json (全新安装)

**输入**: 不存在的 settings.json  
**预期 analyze 输出**:
```json
{
  "hasDrift": true,
  "needsInstallCompletion": true,
  "needsUpdateAlignment": false,
  "details": {
    "missingEnvKeys": ["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "CLAUDE_CODE_ATTRIBUTION_HEADER", ...],
    "missingPermissions": ["Bash", "Edit", "Read", ...],
    "missingLanguage": true,
    "missingAlwaysThinkingEnabled": true,
    "missingPlansDirectory": true
  }
}
```

### 2. 部分缺失 (Install 未完成)

**输入**:
```json
{
  "language": "简体中文",
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "90"
  }
}
```

**预期 analyze 输出**:
```json
{
  "hasDrift": true,
  "needsInstallCompletion": true,
  "details": {
    "missingEnvKeys": ["CLAUDE_CODE_ATTRIBUTION_HEADER", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", ...],
    "missingPermissions": ["Bash", "Edit", ...],
    "missingAlwaysThinkingEnabled": true,
    "missingPlansDirectory": true
  }
}
```

### 3. 值偏移 (Update 对齐)

**输入**:
```json
{
  "language": "简体中文",
  "alwaysThinkingEnabled": true,
  "plansDirectory": ".claude/plan",
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "85",
    "MAX_THINKING_TOKENS": "31999"
  },
  "permissions": {
    "allow": ["Bash", "Read", "Write"]
  }
}
```

**预期 analyze 输出**:
```json
{
  "hasDrift": true,
  "needsInstallCompletion": false,
  "needsUpdateAlignment": true,
  "details": {
    "driftedEnvKeys": [
      {"key": "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "expected": "90", "actual": "85"}
    ],
    "missingEnvKeys": ["CLAUDE_CODE_ATTRIBUTION_HEADER", ...]
  }
}
```

### 4. 废弃键检测

**输入**:
```json
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "90",
    "DEPRECATED_OLD_KEY": "value"
  }
}
```

**预期 analyze 输出**:
```json
{
  "hasDrift": true,
  "needsUpdateAlignment": true,
  "details": {
    "deprecatedEnvKeys": ["DEPRECATED_OLD_KEY"]
  }
}
```

### 5. 完整配置 (无漂移)

**输入**: 包含所有必需字段且值正确的 settings.json  
**预期 analyze 输出**:
```json
{
  "hasDrift": false,
  "needsInstallCompletion": false,
  "needsUpdateAlignment": false,
  "details": {
    "missingEnvKeys": [],
    "driftedEnvKeys": [],
    "missingPermissions": [],
    "deprecatedEnvKeys": []
  }
}
```

## 运行测试

```bash
# analyze 模式
node ../claude-config-drift.js \
  --contract-path ../../claude-config.json \
  --settings-path ./sample-settings.json \
  --mode analyze

# install 模式
node ../claude-config-drift.js \
  --contract-path ../../claude-config.json \
  --settings-path ./sample-settings.json \
  --mode install

# update 模式
node ../claude-config-drift.js \
  --contract-path ../../claude-config.json \
  --settings-path ./sample-settings.json \
  --mode update
```

## 验收标准

- [ ] analyze 模式正确识别所有漂移项
- [ ] install 模式只补缺失，不覆盖已有值
- [ ] update 模式声明式对齐，更新偏移值并删除废弃键
- [ ] 禁区键 (`ANTHROPIC_AUTH_TOKEN`, `*_API_KEY`) 永不被修改
- [ ] 输出 JSON 格式正确，可被 PowerShell/zsh 解析
