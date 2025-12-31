module.exports = async ({github, context, core}) => {
  const fs = require('fs');
  const path = require('path');

  // Helper function to get status icon
  const getStatusIcon = (outcome) => {
    switch(outcome) {
      case 'success': return '✅';
      case 'failure': return '❌';
      case 'skipped': return '⏭️';
      default: return '❓';
    }
  };

  // Helper function to parse changed stacks
  const getChangedStacks = () => {
    const changedStacks = process.env.CHANGED_STACKS || '';
    if (!changedStacks || changedStacks.trim() === '') {
      return 'None';
    }
    return changedStacks.split('\n')
      .filter(s => s.trim())
      .map(s => '`' + s + '`')
      .join(', ');
  };

  // Read Trivy output and count issues
  let trivyResults = 'No issues found or Trivy did not run';
  let trivyCritical = 0;
  let trivyHigh = 0;
  let trivyMedium = 0;
  const trivyPath = path.join(process.env.GITHUB_WORKSPACE, 'trivy_output.txt');
  if (fs.existsSync(trivyPath)) {
    trivyResults = fs.readFileSync(trivyPath, 'utf8').trim() || 'No issues found';
    trivyCritical = (trivyResults.match(/\(CRITICAL\):/g) || []).length;
    trivyHigh = (trivyResults.match(/\(HIGH\):/g) || []).length;
    trivyMedium = (trivyResults.match(/\(MEDIUM\):/g) || []).length;
  }

  // Determine overall status
  const fmtStatus = process.env.FMT_STATUS || 'success';
  const validateStatus = process.env.VALIDATE_STATUS || 'success';
  const trivyStatus = (trivyCritical > 0 || trivyHigh > 0) ? 'failure' : 'success';

  const allPassed = fmtStatus === 'success' &&
                   validateStatus === 'success' &&
                   trivyStatus === 'success';

  const changedStacks = getChangedStacks();
  const summary = allPassed ? '✅ **All checks passed!**' : '🔴 **Some checks failed**';
  const issueCount = trivyCritical + trivyHigh + trivyMedium;

  const output = '## 🔍 Terragrunt Check Results\n\n' +
    '### 📊 Summary\n' +
    summary + '\n\n' +
    '| Check | Status | Issues | Scope |\n' +
    '|-------|--------|--------|-------|\n' +
    '| 🖌 **HCL Format** | ' + getStatusIcon(fmtStatus) + ' ' + fmtStatus + ' | - | All HCL files |\n' +
    '| 🤖 **HCL Validate** | ' + getStatusIcon(validateStatus) + ' ' + validateStatus + ' | - | All HCL files |\n' +
    '| 🔒 **Trivy** | ' + getStatusIcon(trivyStatus) + ' ' + trivyStatus + ' | ' + trivyCritical + ' critical, ' + trivyHigh + ' high, ' + trivyMedium + ' medium | ' + changedStacks + ' |\n\n' +
    '---\n\n' +
    '<details>\n' +
    '<summary>🔒 Trivy Security Details (' + issueCount + ' issue(s))</summary>\n\n' +
    '```\n' +
    trivyResults + '\n' +
    '```\n' +
    '</details>\n\n' +
    '---\n' +
    '💡 **Note:** Terragrunt plan is disabled. To enable, configure AWS OIDC credentials in the workflow.\n\n' +
    '---\n' +
    '<sub>👤 Pusher: @' + context.actor + ' | 🔄 Action: `' + context.eventName + '` | ⚙️ Workflow: `' + context.workflow + '`</sub>';

  await github.rest.issues.createComment({
    issue_number: context.issue.number,
    owner: context.repo.owner,
    repo: context.repo.repo,
    body: output
  });
};
