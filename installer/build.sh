#!/bin/sh
# build.sh - macOS / Unix 本地单文件构建入口
# 功能: 从共享构建清单生成 Windows PowerShell 与 macOS zsh 短 artifact

set -eu

usage() {
  cat <<'EOF'
Usage: sh installer/build.sh [OPTIONS]

Options:
  --platform <windows|macos|all>  构建平台，默认 all
  --output <dir>                  输出目录，默认 repo 根目录 dist/
  --check                         只检查 build.sh 语法/结构，不生成 artifact
  --help                          显示帮助
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "${script_dir}/.." && pwd)
platform="all"
output_dir="${repo_root}/dist"
check_only=0

check_build_script() {
  script_path="${script_dir}/build.sh"
  [ -f "${script_path}" ] || { printf '%s\n' "[FAIL] build.sh 不存在: ${script_path}" >&2; exit 1; }
  grep -q "^#!/bin/sh" "${script_path}" || { printf '%s\n' '[FAIL] build.sh 缺少 #!/bin/sh shebang' >&2; exit 1; }
  grep -q "readJson('contracts/build.json')" "${script_path}" || { printf '%s\n' '[FAIL] build.sh 未读取共享构建清单 contracts/build.json' >&2; exit 1; }
  grep -q "validatePowerShellArtifact" "${script_path}" || { printf '%s\n' '[FAIL] build.sh 缺少 PowerShell artifact 结构检查' >&2; exit 1; }
  grep -q "validateMacOSArtifact" "${script_path}" || { printf '%s\n' '[FAIL] build.sh 缺少 macOS artifact 结构检查' >&2; exit 1; }

  if command -v zsh >/dev/null 2>&1; then
    zsh -n "${script_path}"
    printf '%s\n' '[PASS] build.sh zsh 语法检查通过'
  else
    printf '%s\n' '[INFO] 未检测到 zsh，已完成 build.sh 文本结构检查'
  fi
  printf '%s\n' '[PASS] build.sh 检查通过'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      [ "$#" -ge 2 ] || { printf '%s\n' '缺少 --platform 参数值' >&2; exit 2; }
      platform=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || { printf '%s\n' '缺少 --output 参数值' >&2; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    --check)
      check_only=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf '未知参数: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${platform}" in
  windows|macos|all) ;;
  *)
    printf '无效平台: %s\n' "${platform}" >&2
    usage >&2
    exit 2
    ;;
esac

if [ "${check_only}" -eq 1 ]; then
  check_build_script
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' '缺少 node 命令，无法解析 installer/contracts/*.json 构建清单。' >&2
  exit 1
fi

node - "${script_dir}" "${output_dir}" "${platform}" <<'NODE_SCRIPT'
const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const installerRoot = path.resolve(process.argv[2]);
const outputDir = path.resolve(process.argv[3]);
const platform = process.argv[4];

function fail(message) {
  console.error(`[FAIL] ${message}`);
  process.exit(1);
}

function pass(message) {
  console.log(`[PASS] ${message}`);
}

function info(message) {
  console.log(`[INFO] ${message}`);
}

function readText(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function readJson(relativePath) {
  const fullPath = path.join(installerRoot, relativePath);
  if (!fs.existsSync(fullPath)) fail(`JSON 文件不存在: ${fullPath}`);
  return JSON.parse(readText(fullPath));
}

function requireFile(relativePath) {
  const fullPath = path.join(installerRoot, relativePath);
  if (!fs.existsSync(fullPath) || !fs.statSync(fullPath).isFile()) {
    fail(`源文件不存在: ${fullPath}`);
  }
  return fullPath;
}

function normalizeRelPath(value) {
  return String(value || '').replace(/\\/g, '/').replace(/^\.\//, '');
}

function normalizeWindowsBuildPath(value) {
  const normalized = normalizeRelPath(value);
  if (normalized.startsWith('windows/')) return normalized;
  return `windows/${normalized}`;
}

function windowsStepFiles(stepsContract) {
  const files = [];
  const steps = [...(stepsContract.Steps || [])].sort((a, b) => Number(a.Order || 0) - Number(b.Order || 0));
  for (const step of steps) {
    for (const sub of step.SubModules || []) files.push(normalizeWindowsBuildPath(sub));
    if (step.StepFile) files.push(normalizeWindowsBuildPath(step.StepFile));
  }
  return files;
}

function macOSStepFiles(manifest, stepsContract) {
  const files = [];
  const common = manifest.MacOS.CommonStepFile;
  if (common && fs.existsSync(path.join(installerRoot, common))) files.push(normalizeRelPath(common));
  const steps = [...(stepsContract.Steps || [])].sort((a, b) => Number(a.Order || 0) - Number(b.Order || 0));
  for (const step of steps) {
    if (!step.MacOSStepFile) continue;
    const relPath = normalizeRelPath(step.MacOSStepFile);
    if (fs.existsSync(path.join(installerRoot, relPath))) files.push(relPath);
  }
  return files;
}

function artifactFor(manifest, platformName, role) {
  const artifact = ((manifest[platformName] || {}).Artifacts || []).find((item) => item.Role === role);
  if (!artifact) fail(`未找到构建 artifact 配置: ${platformName}/${role}`);
  return artifact;
}

function windowsBuildOrder(manifest, stepsContract, role) {
  const artifact = artifactFor(manifest, 'Windows', role);
  const order = [...(artifact.CoreFiles || []).map(normalizeRelPath)];
  if (artifact.IncludeSteps) order.push(...windowsStepFiles(stepsContract));
  order.push(normalizeRelPath(artifact.EntryFile));
  return { artifact, order };
}

function macOSBuildOrder(manifest, stepsContract, role) {
  const artifact = artifactFor(manifest, 'MacOS', role);
  const order = [...(manifest.MacOS.CoreFiles || []).map(normalizeRelPath)];
  if (artifact.IncludeSteps) order.push(...macOSStepFiles(manifest, stepsContract));
  order.push(normalizeRelPath(artifact.EntryFile));
  return { artifact, order };
}

function findTopLevelParamBlock(relativePath) {
  const fullPath = requireFile(relativePath);
  const lines = readText(fullPath).split(/\r?\n/);
  const start = lines.findIndex((line) => /^param\s*\(/.test(line));
  if (start < 0) return null;

  let depth = 0;
  for (let i = start; i < lines.length; i += 1) {
    const line = lines[i];
    for (const char of line) {
      if (char === '(') depth += 1;
      else if (char === ')') depth -= 1;
    }
    if (depth === 0) {
      return { startLine: start + 1, endLine: i + 1, lines: lines.slice(start, i + 1) };
    }
  }
  return null;
}

function buildPowerShellArtifact(manifest, stepsContract, role) {
  const { artifact, order } = windowsBuildOrder(manifest, stepsContract, role);
  for (const relPath of order) requireFile(relPath);

  const outputPath = path.join(outputDir, artifact.OutputFile);
  const lines = [];
  lines.push('# ═══════════════════════════════════════════════════════════════════════════════');
  lines.push('# 本文件由 build.sh 自动生成，请勿手动编辑');
  lines.push(`# 生成时间: ${new Date().toISOString()}`);
  lines.push('# 原始文件:');
  for (const relPath of order) lines.push(`#   - ${relPath}`);
  lines.push('# ═══════════════════════════════════════════════════════════════════════════════');
  lines.push(String(artifact.RequiresHeader || '#Requires -Version 7.0'));
  lines.push('');

  let hoisted = null;
  if (artifact.HoistParamFrom) {
    hoisted = findTopLevelParamBlock(normalizeRelPath(artifact.HoistParamFrom));
    if (!hoisted) fail(`未找到可提升的 param 块: ${artifact.HoistParamFrom}`);
    lines.push(...hoisted.lines);
    lines.push('');
  }

  const dotSourcePattern = /^\s*\.\s+/;
  const scriptRootPattern = /^\s*\$scriptRoot\s*=\s*Split-Path\s+.*\$MyInvocation\.MyCommand\.Path/;

  for (const relPath of order) {
    lines.push('');
    lines.push(`# ─── 来自: ${relPath} ────────────────────────────────────────`);
    lines.push('');

    const sourceLines = readText(requireFile(relPath)).split(/\r?\n/);
    for (let i = 0; i < sourceLines.length; i += 1) {
      const lineNumber = i + 1;
      const line = sourceLines[i];
      if (hoisted && relPath === normalizeRelPath(artifact.HoistParamFrom) && lineNumber >= hoisted.startLine && lineNumber <= hoisted.endLine) continue;
      if (/^\s*#Requires\s/.test(line)) continue;
      if (dotSourcePattern.test(line)) continue;
      if (scriptRootPattern.test(line)) continue;
      lines.push(line);
    }
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${lines.join('\r\n')}`, 'utf8');
  pass(`已生成: ${outputPath}`);
  validatePowerShellArtifact(outputPath, artifact);
  return outputPath;
}

function contractEmbeds() {
  return [
    { file: 'steps.json', marker: 'CCQ_CONTRACT_STEPS_JSON' },
    { file: 'providers.json', marker: 'CCQ_CONTRACT_PROVIDERS_JSON' },
    { file: 'mcp-servers.json', marker: 'CCQ_CONTRACT_MCP_SERVERS_JSON' },
    { file: 'claude-config.json', marker: 'CCQ_CONTRACT_CLAUDE_CONFIG_JSON' },
  ];
}

function appendMacOSWrapper(lines) {
  lines.push('#!/usr/bin/env bash');
  lines.push('# ═══════════════════════════════════════════════════════════════════════════════');
  lines.push('# 本文件由 build.sh 自动生成，请勿手动编辑');
  lines.push(`# 生成时间: ${new Date().toISOString()}`);
  lines.push('# ═══════════════════════════════════════════════════════════════════════════════');
  lines.push('if [ -z "${ZSH_VERSION:-}" ]; then');
  lines.push('  if [ -x "/bin/zsh" ]; then');
  lines.push('    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then');
  lines.push('      exec /bin/zsh "${BASH_SOURCE[0]}" "$@"');
  lines.push('    fi');
  lines.push('    ccq_streamed_script="$(mktemp "${TMPDIR:-/tmp}/ccq-built.XXXXXX.zsh")" || exit 1');
  lines.push('    cat > "${ccq_streamed_script}"');
  lines.push('    export CCQ_STREAMED_SCRIPT_PATH="${ccq_streamed_script}"');
  lines.push('    exec /bin/zsh "${ccq_streamed_script}" "$@"');
  lines.push('  fi');
  lines.push("  printf '%s\\n' 'CCQ macOS built script requires /bin/zsh.' >&2");
  lines.push('  exit 1');
  lines.push('fi');
  lines.push('export CCQ_BUILT_MODE=1');
  lines.push('ccq_cleanup_built_artifacts() {');
  lines.push('  if [ -n "${CCQ_STREAMED_SCRIPT_PATH:-}" ]; then rm -f "${CCQ_STREAMED_SCRIPT_PATH}"; fi');
  lines.push('  if [ -n "${CCQ_BUILT_CONTRACTS_DIR:-}" ]; then rm -rf "${CCQ_BUILT_CONTRACTS_DIR}"; fi');
  lines.push('}');
  lines.push('trap ccq_cleanup_built_artifacts EXIT');
  lines.push('CCQ_BUILT_CONTRACTS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ccq-contracts.XXXXXX")" || exit 1');
  lines.push('export CCQ_BUILT_CONTRACTS_DIR');
  lines.push('export CCQ_CONTRACTS_DIR="${CCQ_BUILT_CONTRACTS_DIR}"');
  lines.push('export CCQ_STEPS_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/steps.json"');
  lines.push('export CCQ_PROVIDER_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/providers.json"');
  lines.push('export CCQ_MCP_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/mcp-servers.json"');
  lines.push('export CCQ_CLAUDE_CONFIG_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/claude-config.json"');

  for (const contract of contractEmbeds()) {
    const contractPath = path.join(installerRoot, 'contracts', contract.file);
    if (!fs.existsSync(contractPath)) fail(`契约文件不存在，无法生成自包含 macOS artifact: ${contractPath}`);
    lines.push(`cat > "\${CCQ_BUILT_CONTRACTS_DIR}/${contract.file}" <<'${contract.marker}'`);
    lines.push(readText(contractPath).replace(/[\r\n]+$/g, ''));
    lines.push(contract.marker);
  }
  lines.push('');
}

function filterZshSource(relativePath) {
  const sourceLines = readText(requireFile(relativePath)).split(/\r?\n/);
  const lines = [];
  let skipUntilSetOpt = false;
  let skipStreamedTrapBlock = false;

  for (const line of sourceLines) {
    if (/^\s*#!/.test(line)) continue;
    if (/^\s*if \[ -z "\$\{ZSH_VERSION:-\}" \]; then\s*$/.test(line)) {
      skipUntilSetOpt = true;
      continue;
    }
    if (skipUntilSetOpt) {
      if (/^\s*setopt\s+/.test(line)) skipUntilSetOpt = false;
      else continue;
    }
    if (/^\s*if \[ -n "\$\{CCQ_STREAMED_SCRIPT_PATH:-\}" \]; then\s*$/.test(line)) {
      skipStreamedTrapBlock = true;
      continue;
    }
    if (skipStreamedTrapBlock) {
      if (/^\s*fi\s*$/.test(line)) skipStreamedTrapBlock = false;
      continue;
    }
    if (/^\s*(source|\.)\s+/.test(line)) continue;
    if (/^\s*ccq_main "\$@"\s*$/.test(line)) continue;
    if (/^\s*ccq_manage_main "\$@"\s*$/.test(line)) continue;
    lines.push(line);
  }

  return lines;
}

function buildMacOSArtifact(manifest, stepsContract, role) {
  const { artifact, order } = macOSBuildOrder(manifest, stepsContract, role);
  for (const relPath of order) requireFile(relPath);

  const outputPath = path.join(outputDir, artifact.OutputFile);
  const lines = [];
  appendMacOSWrapper(lines);
  lines.push('# 原始文件:');
  for (const relPath of order) lines.push(`#   - ${relPath}`);

  for (const relPath of order) {
    lines.push('');
    lines.push(`# ─── 来自: ${relPath} ────────────────────────────────────────`);
    lines.push('');
    lines.push(...filterZshSource(relPath));
  }

  const entryFile = order[order.length - 1] || '';
  lines.push('');
  if (/macos\/Install-ClaudeEnv\.zsh$/.test(entryFile)) lines.push('ccq_main "$@"');
  else if (/macos\/Manage-ClaudeEnv\.zsh$/.test(entryFile)) lines.push('ccq_manage_main "$@"');
  else fail(`无法识别 macOS artifact 入口文件: ${entryFile}`);

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${lines.join('\n')}`, 'utf8');
  fs.chmodSync(outputPath, 0o755);
  pass(`已生成: ${outputPath}`);
  validateMacOSArtifact(outputPath);
  return outputPath;
}

function validatePowerShellArtifact(outputPath, artifact) {
  const content = readText(outputPath);
  const requiresCount = (content.match(/^#Requires\s/gm) || []).length;
  if (requiresCount !== 1) fail(`${path.basename(outputPath)} 必须包含且仅包含一个 #Requires，实际 ${requiresCount}`);

  if (/^\s*\.\s+/m.test(content)) fail(`${path.basename(outputPath)} 仍包含 dot-source 行`);

  const topParamCount = (content.match(/^param\s*\(/gm) || []).length;
  if (artifact.HoistParamFrom && topParamCount !== 1) {
    fail(`${path.basename(outputPath)} 必须包含且仅包含一个 hoisted param 块，实际 ${topParamCount}`);
  }
  if (!artifact.HoistParamFrom && topParamCount !== 0) {
    fail(`${path.basename(outputPath)} 不应包含顶层 param 块，实际 ${topParamCount}`);
  }

  if (content.includes('�')) fail(`${path.basename(outputPath)} UTF-8 文本检查失败`);

  const pwsh = childProcess.spawnSync('pwsh', ['-NoProfile', '-Command', 'exit 0'], { encoding: 'utf8' });
  if (pwsh.error || pwsh.status !== 0) {
    info(`未检测到可用 pwsh，跳过 AST 检查: ${path.basename(outputPath)}`);
    return;
  }

  const quotedPath = `'${String(outputPath).replace(/'/g, "''")}'`;
  const script = `$path=${quotedPath}; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)|Out-Null; if($errors.Count -gt 0){$errors|ForEach-Object{Write-Error $_.Message}; exit 1}`;
  const result = childProcess.spawnSync('pwsh', ['-NoProfile', '-Command', script], { encoding: 'utf8' });
  if (result.status !== 0) fail(`PowerShell AST 检查失败: ${path.basename(outputPath)}\n${result.stderr || result.stdout}`);
  pass(`PowerShell AST 检查通过: ${outputPath}`);
}

function validateMacOSArtifact(outputPath) {
  const content = readText(outputPath);
  if (!content.startsWith('#!/usr/bin/env bash')) fail(`${path.basename(outputPath)} 缺少 bash wrapper shebang`);
  if (!content.includes('export CCQ_BUILT_MODE=1')) fail(`${path.basename(outputPath)} 缺少 CCQ_BUILT_MODE`);
  if (!content.includes('CCQ_CONTRACT_STEPS_JSON')) fail(`${path.basename(outputPath)} 未嵌入 steps contract`);
  if (/^\s*(source|\.)\s+/m.test(content)) fail(`${path.basename(outputPath)} 仍包含 source 行`);

  const zsh = childProcess.spawnSync('zsh', ['-n', outputPath], { encoding: 'utf8' });
  if (zsh.error && zsh.error.code === 'ENOENT') {
    info(`未检测到 zsh，跳过 zsh -n 检查: ${path.basename(outputPath)}`);
    return;
  }
  if (zsh.status !== 0) fail(`zsh 语法检查失败: ${path.basename(outputPath)}\n${zsh.stderr || zsh.stdout}`);
  pass(`zsh 语法检查通过: ${outputPath}`);
}

function ensureExpectedOutputs(manifest, selectedPlatform) {
  const expected = [];
  if (selectedPlatform === 'all' || selectedPlatform === 'windows') {
    expected.push(...manifest.Windows.Artifacts.map((item) => item.OutputFile));
  }
  if (selectedPlatform === 'all' || selectedPlatform === 'macos') {
    expected.push(...manifest.MacOS.Artifacts.map((item) => item.OutputFile));
  }
  for (const fileName of expected) {
    const fullPath = path.join(outputDir, fileName);
    if (!fs.existsSync(fullPath)) fail(`缺少预期输出文件: ${fullPath}`);
  }
  pass(`输出文件集合检查通过: ${expected.join(', ')}`);
}

const manifest = readJson('contracts/build.json');
const stepsContract = readJson(manifest.Windows.StepContract || 'contracts/steps.json');
fs.mkdirSync(outputDir, { recursive: true });

console.log('═══════════════════════════════════════════════════════════════');
console.log('  Claude Code 安装器 - Unix 单文件构建工具');
console.log('═══════════════════════════════════════════════════════════════');
console.log(`安装器根目录: ${installerRoot}`);
console.log(`输出目录:     ${outputDir}`);
console.log(`构建平台:     ${platform}`);

if (platform === 'all' || platform === 'windows') {
  buildPowerShellArtifact(manifest, stepsContract, 'Bootstrap');
  buildPowerShellArtifact(manifest, stepsContract, 'Install');
  buildPowerShellArtifact(manifest, stepsContract, 'Manage');
}

if (platform === 'all' || platform === 'macos') {
  buildMacOSArtifact(manifest, stepsContract, 'Install');
  buildMacOSArtifact(manifest, stepsContract, 'Manage');
}

ensureExpectedOutputs(manifest, platform);
console.log('');
console.log('[PASS] 构建完成');
NODE_SCRIPT
