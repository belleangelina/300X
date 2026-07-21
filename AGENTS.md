# AGENTS.md

## 构建与验证

- 长构建和测试输出必须写入 `.artifacts/validation/logs/`。
- 对话和审查只展示结论与有限失败摘要。
- 闭环回归默认只运行本次修改直接影响的测试和静态检查；只有用户明确要求或进入发布门禁时才运行全量验证。
- 需要交付 Release 时使用根目录 `build_release.sh --platform <android|linux|ios>`，由脚本递增版本并生成带版本号的平台产物。
- 设计与功能以 `docs/spec/yamibox-v1.md` 为单一权威文档。
- 通过单元测试或构建不等于功能完成；必须在目标平台执行实际路径、修复并复验。
