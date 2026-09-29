'use strict';
const { isMainWindow } = require('./agent.cjs');
const expressions = {
  cleanup: `(() => { window.__codexUsageBadge?.destroy?.(); window.__codexProjectColors?.destroy?.({clearStorage:true}); window.__codexThreadTokens?.destroy?.(); return !document.getElementById('codex-usage-badge') && !document.getElementById('codex-project-colors-style') && !document.getElementById('codex-thread-tokens-style'); })()`,
  status: `JSON.stringify({quota:!!window.__codexUsageBadge,folderColors:!!window.__codexProjectColors,threadTokens:!!window.__codexThreadTokens})`
};
async function evaluate(target, expression) {
  const endpoint = new URL(target.webSocketDebuggerUrl);
  if (endpoint.protocol !== 'ws:' || !['127.0.0.1','localhost','[::1]'].includes(endpoint.hostname) || endpoint.port !== '39222') throw new Error('Refusing a non-local badge endpoint');
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(endpoint);
    const timer = setTimeout(() => done(new Error('Window response timed out')), 3500);
    let settled = false;
    function done(error, value) {
      if (settled) return;
      settled = true; clearTimeout(timer); ws.close();
      error ? reject(error) : resolve(value);
    }
    ws.addEventListener('open', () => ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression,returnByValue:true}})));
    ws.addEventListener('message', event => {
      try {
        const data = JSON.parse(event.data);
        if (data.id !== 1) return;
        if (data.error || data.result?.exceptionDetails) return done(new Error('Window script execution failed'));
        done(null, data.result?.result?.value);
      } catch (error) { done(error); }
    });
    ws.addEventListener('error', () => done(new Error('Could not connect to the window')));
    ws.addEventListener('close', () => done(new Error('The window closed')));
  });
}
async function main(action) {
  if (!Object.hasOwn(expressions, action)) throw new Error('Usage: bridge.cjs status|cleanup');
  const response = await fetch('http://127.0.0.1:39222/json/list', {signal:AbortSignal.timeout(2500)});
  if (!response.ok) throw new Error('The debug port is not ready');
  const targets = (await response.json()).filter(isMainWindow);
  if (!targets.length) throw new Error('No connected main window found');
  const result = await Promise.all(targets.map(t => evaluate(t, expressions[action])));
  if (action === 'cleanup' && result.some(value => value !== true)) throw new Error('Some UI components were not removed');
  console.log(JSON.stringify({action,windows:result},null,2));
}
module.exports = {evaluate, main};
if (require.main === module) main(process.argv[2]).catch(error => { console.error(error.message); process.exitCode=1; });
