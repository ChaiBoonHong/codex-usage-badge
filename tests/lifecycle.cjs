// Exercise real filesystem install/uninstall in a disposable home; launchctl and UI are mocked.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const vm=require('node:vm');
const childProcess=require('node:child_process');
const root=path.resolve(__dirname,'..');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'badge-install-'));
const installDir=path.join(temp,'Library/Application Support/CodexUsageBadge');
const shortcut=path.join(temp,'Desktop/Codex 用量条.app');
const launcher=path.join(temp,'Applications/Codex 用量条.app');
const jobs=new Set();
const messages=[];
let failBootstrap=false;
let failIconCopy=false;
const calls=[];
const testFs={...fs,copyFileSync(source,destination,...args){
  if(failIconCopy&&destination===path.join(launcher,'Contents/Resources/AppIcon.icns')) {
    failIconCopy=false;throw new Error('simulated first-install icon write failure');
  }
  return fs.copyFileSync(source,destination,...args);
}};
const execFileSync=(bin,args,options)=>{
  calls.push([bin,...args]);
  if(bin==='/bin/launchctl') {
    const label='com.codexusagebadge.agent';
    if(args[0]==='print'){if(jobs.has(args[1].split('/').at(-1)))return 'state = running';throw new Error('not loaded');}
    if(args[0]==='bootout'){jobs.delete(args[1].split('/').at(-1));return '';}
    if(args[0]==='bootstrap'){
      if(failBootstrap){failBootstrap=false;throw new Error('simulated bootstrap failure');}
      assert.ok(fs.existsSync(args[2]));jobs.add(label);return '';
    }
    throw new Error('unexpected launchctl command');
  }
  assert.ok(!['/usr/bin/open','/usr/bin/osascript'].includes(bin),'install/uninstall must not activate or close the app');
  return childProcess.execFileSync(bin,args,options);
};
class FailedSocket {
  constructor(){this.events={};setImmediate(()=>this.events.error?.());}
  addEventListener(name,handler){this.events[name]=handler;}
  close(){}
}
const sandbox={module:{exports:{}},__dirname:root,process,Buffer,URL,setTimeout,clearTimeout,
  AbortSignal,WebSocket:FailedSocket,console:{log:s=>messages.push(s),warn:s=>messages.push(s)},
  fetch:async()=>({ok:true,json:async()=>[{type:'page',url:'app://-/index.html',webSocketDebuggerUrl:'ws://127.0.0.1/unreachable'}]}),
  require:id=>id==='node:fs'?testFs:id==='node:os'?{...os,homedir:()=>temp}:id==='node:child_process'?{...childProcess,execFileSync}:id==='./agent.cjs'?require('../agent.cjs'):require(id)};
vm.runInNewContext(fs.readFileSync(path.join(root,'manage.cjs'),'utf8'),sandbox,{filename:'manage.cjs'});
const manager=sandbox.module.exports;
(async()=>{
  try {
    fs.mkdirSync(path.join(temp,'Desktop'),{recursive:true});
    fs.writeFileSync(shortcut,'unrelated desktop file');
    await assert.rejects(manager.install(),/桌面启动入口名称已被占用/);
    assert.equal(jobs.size,0);
    assert.equal(fs.existsSync(installDir),false);
    assert.equal(fs.readFileSync(shortcut,'utf8'),'unrelated desktop file');
    fs.unlinkSync(shortcut);
    failIconCopy=true;
    await assert.rejects(manager.install(),/已恢复安装前的程序文件/);
    assert.equal(jobs.size,0);
    assert.equal(fs.existsSync(launcher),false,'failed first install must not leave an empty launcher that blocks retry');
    assert.equal(fs.existsSync(installDir),false);
    await manager.install();
    await manager.install();
    assert.equal(jobs.size,1);
    assert.equal(fs.lstatSync(shortcut).isSymbolicLink(),true);
    assert.equal(fs.statSync(path.join(installDir,'agent.cjs')).mode&0o777,0o600);
    const agent=path.join(installDir,'agent.cjs');
    const previous=fs.readFileSync(agent,'utf8')+'\n// previous installed copy\n';
    fs.writeFileSync(agent,previous);
    failBootstrap=true;
    await assert.rejects(manager.install(),/已恢复安装前的程序文件/);
    assert.equal(fs.readFileSync(agent,'utf8'),previous);
    assert.equal(jobs.size,1,'old agent job restored after failed upgrade');
    await manager.uninstall();
    assert.equal(jobs.size,0);
    assert.equal(fs.existsSync(installDir),false);
    assert.equal(fs.existsSync(launcher),false);
    assert.throws(()=>fs.lstatSync(shortcut),{code:'ENOENT'});
    assert.ok(messages.some(s=>s.includes('部分窗口暂不可连接')),'renderer disconnect must not abort uninstall');
    const trash=path.join(temp,'.Trash',fs.readdirSync(path.join(temp,'.Trash'))[0]);
    const moved=fs.readdirSync(trash);
    assert.ok(moved.includes('Codex 用量条.app')&&moved.includes('Codex 用量条.app-shortcut'),'broken moved symlink must not overwrite launcher');
    await manager.install();
    const info=path.join(launcher,'Contents/Info.plist');
    fs.writeFileSync(info,fs.readFileSync(info,'utf8').replace('local.codexusagebadge.launcher','another.app'));
    fs.unlinkSync(shortcut);fs.writeFileSync(shortcut,'unrelated desktop file');
    await manager.uninstall();
    assert.equal(fs.readFileSync(shortcut,'utf8'),'unrelated desktop file');
    assert.ok(fs.existsSync(info),'uninstall must preserve a different application at the same name');
    assert.ok(!manager.activationConfig().ProgramArguments.includes('--allow-restart'));
    console.log('PASS fresh/repeated install, preflight conflicts, first-install failure/retry, failed-upgrade rollback, offline-window uninstall, trash collision and unrelated app preservation');
  } finally {fs.rmSync(temp,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
