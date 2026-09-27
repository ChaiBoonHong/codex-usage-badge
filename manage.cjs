// Installation/explicit launch operations are deliberately separate from agent.cjs.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync, spawn } = require('node:child_process');
const { resolveCodexBin, isMainWindow } = require('./agent.cjs');
const home = os.homedir();
const app = process.env.CODEX_BADGE_APP || ['/Applications/Codex.app','/Applications/ChatGPT.app',path.join(home,'Applications/Codex.app'),path.join(home,'Applications/ChatGPT.app')].find(candidate => { try { resolveCodexBin(undefined,candidate); return true; } catch { return false; } }) || '/Applications/Codex.app';
const node = process.execPath;
const installDir = path.join(home, 'Library/Application Support/CodexUsageBadge');
const logs = path.join(home, 'Library/Logs');
const label = 'com.codexusagebadge.agent';
const activationLabel = 'com.codexusagebadge.activate-once';
const gui = `gui/${process.getuid()}`;
const plistPath = path.join(home, 'Library/LaunchAgents', `${label}.plist`);
const launcher = path.join(home, 'Applications/Codex 用量条.app');
const desktopLauncher = path.join(home, 'Desktop/Codex 用量条.app');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function command(bin, args, options = {}) {
  return execFileSync(bin, args, { encoding: 'utf8', timeout: 15000, stdio: ['ignore', 'pipe', 'pipe'], ...options });
}
function xml(value) {
  if (typeof value === 'boolean') return value ? '<true/>' : '<false/>';
  if (typeof value === 'number') return `<integer>${value}</integer>`;
  if (Array.isArray(value)) return `<array>${value.map(xml).join('')}</array>`;
  if (value && typeof value === 'object') return `<dict>${Object.entries(value).map(([k,v]) => `<key>${escapeXml(k)}</key>${xml(v)}`).join('')}</dict>`;
  return `<string>${escapeXml(value)}</string>`;
}
function escapeXml(value) { return String(value).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;'); }
function writePlist(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">${xml(value)}</plist>\n`, {mode:0o644});
  command('/usr/bin/plutil', ['-lint', file]);
}
function loaded(job) { try { return command('/bin/launchctl',['print',`${gui}/${job}`]); } catch { return null; } }
async function stop(job) {
  if (!loaded(job)) return;
  command('/bin/launchctl', ['bootout', `${gui}/${job}`]);
  for(let i=0;i<30;i++) { if(!loaded(job)) return; await pause(100); }
  throw new Error(`后台任务未能停止：${job}`);
}
function quoteShell(value) { return "'" + value.replaceAll("'", "'\\''") + "'"; }
function agentConfig() {
  return {
    Label: label, ProgramArguments: [node, path.join(installDir,'agent.cjs')],
    EnvironmentVariables: { ...(process.env.CODEX_HOME ? {CODEX_HOME:process.env.CODEX_HOME} : {}), CODEX_BADGE_APP:app, CODEX_BADGE_BIN:resolveCodexBin(undefined,app), CODEX_BADGE_PORT:'39222', CODEX_BADGE_DEBUG:'0' },
    RunAtLoad:true, KeepAlive:{SuccessfulExit:false}, ThrottleInterval:10, ProcessType:'Background',
    StandardOutPath:path.join(logs,'CodexUsageBadge.out.log'), StandardErrorPath:path.join(logs,'CodexUsageBadge.err.log')
  };
}
function activationConfig({waitForExit=false}={}) {
  return {
    Label:activationLabel, ProgramArguments:[node,path.join(installDir,'manage.cjs'),...(waitForExit?['activate-after-exit']:['activate'])],
    RunAtLoad:true, KeepAlive:false, ProcessType:'Background',
    StandardOutPath:path.join(logs,'CodexUsageBadge.activate.log'), StandardErrorPath:path.join(logs,'CodexUsageBadge.activate.err.log')
  };
}
function statOrNull(file) { try { return fs.lstatSync(file); } catch (error) { if(error.code==='ENOENT')return null; throw error; } }
function ownedLauncher() {
  const stat=statOrNull(launcher);
  if(!stat)return false;
  if(stat.isSymbolicLink()||!stat.isDirectory())return false;
  try { return command('/usr/libexec/PlistBuddy',['-c','Print :CFBundleIdentifier',path.join(launcher,'Contents/Info.plist')]).trim()==='local.codexusagebadge.launcher'; }
  catch { return false; }
}
function ownedShortcut() {
  const stat=statOrNull(desktopLauncher);
  return !!stat?.isSymbolicLink()&&fs.readlinkSync(desktopLauncher)===launcher;
}
function preflight() {
  if(!fs.existsSync(node))throw new Error('客户端内置 Node.js 不存在');
  if(statOrNull(launcher)&&!ownedLauncher())throw new Error('启动入口已被其他应用占用');
  if(statOrNull(desktopLauncher)&&!ownedShortcut())throw new Error('桌面启动入口名称已被占用');
  for(const file of ['agent.cjs','manage.cjs'])command(node,['--check',path.join(__dirname,file)]);
  command(resolveCodexBin(undefined,app),['--version']);
}
function saveInstallFiles() {
  // Roll back only directories this install creates, deepest first, and only when empty.
  const newDirectories=[path.join(launcher,'Contents/Resources'),path.join(launcher,'Contents/MacOS'),
    path.join(launcher,'Contents'),launcher,installDir].filter(dir=>!statOrNull(dir));
  const files=[plistPath,...['agent.cjs','manage.cjs','状态.json'].map(f=>path.join(installDir,f)),
    path.join(launcher,'Contents/Info.plist'),path.join(launcher,'Contents/MacOS/launcher'),path.join(launcher,'Contents/Resources/AppIcon.icns'),desktopLauncher];
  const entries=files.map(file=>{const s=statOrNull(file);return {file,mode:s?.mode,link:s?.isSymbolicLink()?fs.readlinkSync(file):null,data:s&&!s.isSymbolicLink()?fs.readFileSync(file):null};});
  return () => {
    for(const {file,mode,link,data} of entries) {
      if(statOrNull(file))fs.unlinkSync(file);
      if(link!==null)fs.symlinkSync(link,file);
      else if(data!==null){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,data,{mode});}
    }
    for(const dir of newDirectories) {
      try { fs.rmdirSync(dir); }
      catch(error) { if(!['ENOENT','ENOTEMPTY','EEXIST'].includes(error.code))throw error; }
    }
  };
}
async function install() {
  preflight();
  const restore=saveInstallFiles();
  const wasLoaded=!!loaded(label);
  try {
  for(const old of ['com.codexusagebadge.install-once',activationLabel,label]) await stop(old);
  fs.mkdirSync(installDir,{recursive:true});
  fs.mkdirSync(logs,{recursive:true});
  for(const name of ['agent.cjs','manage.cjs']) {
    if(path.join(__dirname,name)!==path.join(installDir,name)) fs.copyFileSync(path.join(__dirname,name),path.join(installDir,name));
    fs.chmodSync(path.join(installDir,name),0o600);
  }
  writePlist(plistPath,agentConfig());
  command('/bin/launchctl',['bootstrap',gui,plistPath]);
  if(fs.existsSync(launcher)) {
    const id=command('/usr/libexec/PlistBuddy',['-c','Print :CFBundleIdentifier',path.join(launcher,'Contents/Info.plist')]).trim();
    if(id!=='local.codexusagebadge.launcher') throw new Error('启动入口已被其他应用占用');
  }
  fs.mkdirSync(path.join(launcher,'Contents/MacOS'),{recursive:true});
  fs.mkdirSync(path.join(launcher,'Contents/Resources'),{recursive:true});
  writePlist(path.join(launcher,'Contents/Info.plist'),{
    CFBundleIdentifier:'local.codexusagebadge.launcher',CFBundleName:'Codex 用量条',CFBundleDisplayName:'Codex 用量条',
    CFBundleExecutable:'launcher',CFBundlePackageType:'APPL',CFBundleVersion:'0.8.0',CFBundleShortVersionString:'0.8.0',LSUIElement:true,CFBundleIconFile:'AppIcon.icns'
  });
  const icon=command('/usr/libexec/PlistBuddy',['-c','Print :CFBundleIconFile',path.join(app,'Contents/Info.plist')]).trim();
  const sourceIcon=path.join(app,'Contents/Resources',icon.endsWith('.icns')?icon:icon+'.icns');
  if(fs.existsSync(sourceIcon))fs.copyFileSync(sourceIcon,path.join(launcher,'Contents/Resources/AppIcon.icns'));
  const exe=path.join(launcher,'Contents/MacOS/launcher');
  fs.writeFileSync(exe,`#!/bin/sh\nexec ${quoteShell(node)} ${quoteShell(path.join(installDir,'manage.cjs'))} launch\n`,{mode:0o755});
  fs.chmodSync(exe,0o755);
  let desktopStat=null;try{desktopStat=fs.lstatSync(desktopLauncher);}catch{}
  if(desktopStat) {
    if(!desktopStat.isSymbolicLink()||fs.readlinkSync(desktopLauncher)!==launcher) throw new Error('桌面启动入口名称已被占用');
  } else fs.symlinkSync(launcher,desktopLauncher);
  console.log('已安装 v0.8.0。后台只连接已有客户端，不会启动或激活窗口。');
  console.log('启动入口：'+desktopLauncher);
  record({state:'installed',message:'程序和自启已安装，等待带本机连接的客户端启动'});
  } catch(error) {
    let rollbackError;
    try { await stop(label); restore(); if(wasLoaded&&fs.existsSync(plistPath))command('/bin/launchctl',['bootstrap',gui,plistPath]); }
    catch(failure) { rollbackError=failure; }
    throw new Error(`安装失败：${error.message}。${rollbackError?`恢复旧版失败：${rollbackError.message}`:'已恢复安装前的程序文件'}`);
  }
}
async function targets() {
  const response=await fetch('http://127.0.0.1:39222/json/list',{signal:AbortSignal.timeout(2000)});
  if(!response.ok)throw new Error('本机端口暂不可连接');
  return (await response.json()).filter(t=>t.type==='page'&&isMainWindow(t)&&t.webSocketDebuggerUrl);
}
async function cdp(target,method,params) {
  const ws=new WebSocket(target.webSocketDebuggerUrl);
  try {
    return await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('窗口检查超时')),5000);
      ws.addEventListener('open',()=>ws.send(JSON.stringify({id:1,method,params})));
      ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('窗口连接失败'));});
      ws.addEventListener('message',event=>{
        const m=JSON.parse(event.data);if(m.id!==1)return;clearTimeout(timer);
        if(m.error||m.result?.exceptionDetails)reject(new Error('窗口检查失败'));else resolve(m.result);
      });
    });
  } finally { ws.close(); }
}
async function evaluate(target,expression) {
  return (await cdp(target,'Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result?.value;
}
function appRunning() {
  let executable=path.basename(app,'.app');
  try { executable=command('/usr/libexec/PlistBuddy',['-c','Print :CFBundleExecutable',path.join(app,'Contents/Info.plist')]).trim(); } catch {}
  return command('/bin/ps',['-Ao','comm=']).split('\n').some(s=>s.trim()===path.join(app,'Contents/MacOS',executable));
}
function record(value) {
  fs.writeFileSync(path.join(installDir,'状态.json'),JSON.stringify({time:new Date().toISOString(),version:'0.8.0',...value},null,2)+'\n');
}
async function waitForExit({isRunning=appRunning,sleep=pause,now=Date.now,timeoutMs=300000}={}) {
  const deadline=now()+timeoutMs;
  for(;;) {
    if(now()>=deadline)throw new Error('等待退出已结束。稍后完全退出 Codex 后，可从桌面「Codex 用量条」启动。');
    if(!isRunning()) {
      await sleep(500);
      if(!isRunning())return;
    }
    await sleep(250);
  }
}
async function activateAfterExit() {
  try { if((await targets()).length) { await activate(); return; } } catch {}
  record({state:'waiting_for_exit',message:'等待完全退出 Codex；退出后将自动带正确参数打开一次',expiresAt:new Date(Date.now()+300000).toISOString()});
  console.log('等待用户完全退出客户端；不主动关闭窗口，不反复唤起。');
  await waitForExit();
  await activate();
}
async function activate({allowRestart=false,foreground=false}={}) {
  let ready=false;
  try { ready=(await targets()).length>0; } catch {}
  if(!ready&&appRunning()) {
    if(!allowRestart) {
      command('/usr/bin/osascript',['-e','display notification "请先完全退出 Codex，再从「Codex 用量条」打开。后台不会自动重启你的工作窗口。" with title "Codex 用量条"']);
      return;
    }
    record({state:'activating',message:'正在执行本次授权的一次重启'});
    command('/usr/bin/osascript',['-e','tell application id "com.openai.codex" to quit']);
    await waitForExit({timeoutMs:120000});
  }
  if(!ready) {
    const args=foreground?['-a',app]:['-g','-a',app];
    command('/usr/bin/open',[...args,'--args','--remote-debugging-address=127.0.0.1','--remote-debugging-port=39222']);
  } else if(foreground) {
    command('/usr/bin/open',['-a',app]); // Only a user's explicit launcher click may focus the app.
  }
  let uiWasShown=false;
  for(let attempt=0;attempt<45;attempt++) {
    try {
      const pages=await targets();
      const results=await Promise.all(pages.map(async t=>({target:t,status:await evaluate(t,'window.__codexUsageBadge?.status() ?? null'),colors:await evaluate(t,'window.__codexProjectColors?.status() ?? null'),tokens:await evaluate(t,'window.__codexThreadTokens?.status() ?? null')})));
      const shown=results.filter(r=>r.status?.placed&&r.status.badgeCount===1&&r.status.version===45&&!r.status.stale&&Number.isFinite(r.status.updatedAt)&&Date.now()-r.status.updatedAt<150000&&r.colors?.version===1&&r.tokens?.version===5);
      if(shown.length&&/state = running/.test(loaded(label)||'')) {
        uiWasShown=true;
        const target=shown[0].target;
        const current=await evaluate(target,'window.__codexUsageBadge.status()');
        const readings=current.mode==='dual' ? current.rings ?? [] : [{label:current.windowLabel,percent:current.percent}];
        if(!readings.some(r=>Number.isFinite(r.percent))) {
          record({state:'ui_ready_waiting_for_usage',message:'侧栏已显示，正在等待实际额度读数'});
          await pause(2000);
          continue;
        }
        const {version:uiVersion,...uiStatus}=current;
        record({state:'ready',message:'侧栏额度、文件夹颜色和会话 Token 显示已启用',windows:shown.length,uiVersion,...uiStatus,projectColors:shown[0].colors,threadTokens:shown[0].tokens});
        console.log(`安装成功：侧栏进度条已显示，${readings.map(r=>`${r.label} ${Number.isFinite(r.percent)?`剩余 ${r.percent}%`:'暂不可用'}`).join('，')}。`);
        return;
      }
    } catch {}
    await pause(2000);
  }
  throw new Error(uiWasShown?'侧栏已显示，但暂时无法读取额度，请运行诊断.command 查看读取错误':'客户端已启动，但暂未确认侧栏进度条显示，请运行诊断.command');
}
async function scheduleActivation(options={}) {
  await stop('com.codexusagebadge.install-once');
  await stop(activationLabel);
  const file=path.join(installDir,'activate-once.plist');
  writePlist(file,activationConfig(options));
  command('/bin/launchctl',['bootstrap',gui,file]);
  console.log('单次启用任务已提交，KeepAlive=false；退出后不会重复运行。');
}
async function cleanupUi() {
  let pages=[];try{pages=await targets();}catch{return;}
  const results=await Promise.allSettled(pages.map(page=>evaluate(page,'(() => {window.__codexUsageBadge?.destroy?.();window.__codexProjectColors?.destroy?.({clearStorage:true});window.__codexThreadTokens?.destroy?.();return !document.getElementById("codex-usage-badge")&&!document.getElementById("codex-project-colors-style")&&!document.getElementById("codex-thread-tokens-style");})()')));
  if(results.some(r=>r.status==='rejected'||r.value!==true))console.warn('部分窗口暂不可连接；后台仍会卸载，残留界面将在下次打开客户端时消失。');
}
async function uninstall() {
  for(const job of ['com.codexusagebadge.install-once',activationLabel,label])await stop(job);
  await cleanupUi();
  const trash=path.join(home,'.Trash',`CodexUsageBadge-${Date.now()}`);fs.mkdirSync(trash,{recursive:true});
  const paths=[plistPath,...(ownedShortcut()?[desktopLauncher]:[]),...(ownedLauncher()?[launcher]:[]),installDir,...['out.log','err.log','activate.log','activate.err.log'].map(s=>path.join(logs,`CodexUsageBadge.${s}`))];
  for(const file of paths) {
    try{fs.lstatSync(file);}catch{continue;}
    let dest=path.join(trash,path.basename(file));if(statOrNull(dest))dest+='-shortcut';
    fs.renameSync(file,dest);
  }
  console.log('已卸载并清除界面，无需重启。文件已移入废纸篓。');
}
async function status() {
  console.log('版本：0.8.0');
  console.log('后台：'+(/state = running/.test(loaded(label)||'')?'运行中':'未运行'));
  let pages=[];try{pages=await targets();}catch{}
  console.log('主窗口连接数：'+pages.length);
  for(let i=0;i<pages.length;i++)console.log('窗口 '+(i+1),await evaluate(pages[i],'({usage:window.__codexUsageBadge?.status()??null,projectColors:window.__codexProjectColors?.status()??null,threadTokens:window.__codexThreadTokens?.status()??null})'));
  const receipt=path.join(installDir,'状态.json');if(fs.existsSync(receipt))console.log('上次安装验证记录（历史数据，以以上实时读数为准）：\n'+fs.readFileSync(receipt,'utf8'));
}
module.exports={agentConfig,activationConfig,waitForExit,xml,install,uninstall,preflight};
if(require.main===module)(async()=>{
  const action=process.argv[2];
  if(action==='install')await install();
  else if(action==='schedule-activation')await scheduleActivation({waitForExit:process.argv.includes('--wait-for-exit')});
  else if(action==='activate'){await pause(3000);await activate({allowRestart:process.argv.includes('--allow-restart')});}
  else if(action==='activate-after-exit')await activateAfterExit();
  else if(action==='launch')await activate({foreground:true});
  else if(action==='uninstall')await uninstall();
  else if(action==='status')await status();
  else throw new Error('未知操作：'+action);
})().catch(error=>{
  console.error(error.message);
  if(process.argv[2]?.startsWith('activate')&&fs.existsSync(installDir))record({state:'error',message:error.message});
  process.exitCode=1;
});
