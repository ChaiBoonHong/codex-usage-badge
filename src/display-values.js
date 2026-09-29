function quotaTone(percent) {
  return !Number.isFinite(percent) ? 'muted' : percent < 10 ? 'danger' : percent <= 50 ? 'warning' : 'normal';
}
function unavailableValue(current, title = 'Codex usage is temporarily unavailable. Retrying…') {
  return { ...current, percent: null, title, tone: 'muted', stale: true,
    rings: current?.rings?.map(ring => ({ ...ring, percent: null, tone: 'muted', title: `${ring.label}: unavailable` })) ?? null };
}
function formatRateLimits(response) {
  const single = formatPrimaryRateLimits(response);
  single.tone = quotaTone(single.percent);
  const snapshot = pickCodexSnapshot(response);
  const planType = String(snapshot?.planType ?? response?.planType ?? '').toLowerCase();
  if (planType !== 'plus') return { ...single, mode: 'single', rings: null };
  const windows = [snapshot?.primary, snapshot?.secondary].filter(Boolean);
  function ring(key, label, match) {
    const window = windows.find(match);
    const percent = validWindow(window) ? remainingPercent(window.usedPercent) : null;
    const reset = formatResetTime(window?.resetsAt);
    const tone = quotaTone(percent);
    return { key, label, percent, tone,
      title: `${label}: ${percent === null ? 'unavailable' : `${percent}% remaining`}${reset ? ` · resets ${reset}` : ''}` };
  }
  const rings = [
    ring('five-hour', '5-hour', w => w.windowDurationMins === 300),
    ring('weekly', 'Weekly', w => Number.isFinite(w.windowDurationMins) && w.windowDurationMins >= 10080 && w.windowDurationMins % 10080 === 0)
  ];
  return { ...single, mode: 'dual', rings,
    title: ['Plus usage', ...rings.map(r => r.title), ...formatResetCredits(response)].join('\n') };
}
