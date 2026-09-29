// Formatting is independent of platform and account storage.
function remainingPercent(used) { return Math.max(0, Math.min(100, Math.round(100 - used))); }
function validWindow(value) { return value != null && Number.isFinite(value.usedPercent); }
function isCodexLimit(value) { return value?.limitId == null || value.limitId === 'codex'; }
function formatResetTime(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  const date = new Date(seconds * 1000);
  if (!Number.isFinite(date.getTime())) return null;
  return new Intl.DateTimeFormat('en-US', {month:'short', day:'numeric', hour:'2-digit', minute:'2-digit', hour12:false}).format(date);
}
function durationLabel(minutes) {
  for (const [unit, label] of [[10080,'week'],[1440,'day'],[60,'hour']]) {
    if (Number.isFinite(minutes) && minutes > 0 && minutes % unit === 0) return `${minutes / unit}${label}`;
  }
  return Number.isFinite(minutes) && minutes > 0 ? `${minutes} minutes` : 'usage';
}
function formatResetCredits(response) {
  const credits = response?.rateLimitResetCredits;
  if (!credits || typeof credits !== 'object') return [];
  const available = Array.isArray(credits.credits) ? credits.credits.filter(c => c?.status === 'available' && c?.resetType === 'codexRateLimits') : [];
  const count = Number.isFinite(Number(credits.availableCount)) ? Math.max(0, Math.floor(Number(credits.availableCount))) : available.length;
  const expiry = formatResetTime(available.map(c=>c.expiresAt).filter(v=>Number.isFinite(v)&&v>0).sort((a,b)=>a-b)[0]);
  return [`Reset credits: ${count} available`, ...(count && expiry ? [`Earliest expiry: ${expiry}`] : [])];
}
function formatPrimaryRateLimits(response) {
  const snapshot = pickCodexSnapshot(response);
  const windows = [snapshot?.primary, snapshot?.secondary].filter(validWindow);
  const weekly = w => Number.isFinite(w.windowDurationMins) && w.windowDurationMins >= 10080 && w.windowDurationMins % 10080 === 0;
  const plan = String(snapshot?.planType ?? response?.planType ?? '').toLowerCase();
  const window = plan.startsWith('pro') ? windows.find(weekly) : windows.find(w=>w.windowDurationMins === 300) ?? (!plan ? windows.find(weekly) : null);
  const details = windows.map(w=>`${durationLabel(w.windowDurationMins)}: ${remainingPercent(w.usedPercent)}% remaining${formatResetTime(w.resetsAt) ? ` · resets ${formatResetTime(w.resetsAt)}` : ''}`);
  const percent = window ? remainingPercent(window.usedPercent) : null;
  return {percent, windowLabel: window && weekly(window) ? 'Weekly' : '', tone:quotaTone(percent),
    title:[window ? `${durationLabel(window.windowDurationMins)} usage: ${percent}% remaining` : 'Codex usage is temporarily unavailable',...details,...formatResetCredits(response)].join('\n')};
}
