'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {NativeBridge,portInUse}=require('./windows.cjs');

const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function main(){
  const root=path.dirname(__dirname),config=JSON.parse(fs.readFileSync(path.join(root,'config.json'),'utf8'));
  const force=process.argv.includes('--force');
  if(await portInUse())throw Error('Usage Badge is already connected.');
  const bridge=new NativeBridge(config.AppExe,path.join(root,'stop.request'));
  try{
    const before=await bridge.call('snapshot');
    if(before.apps.length!==1)throw Error('Close every Codex window except the one you want to relaunch.');
    const app=before.apps[0],quit=await bridge.call(force?'killManual':'quitManual',{pid:app.pid,key:app.key});
    if(!quit.accepted)throw Error(force?'Codex could not be closed.':'Codex declined the normal exit request.');
    let empty;
    for(let i=0;i<50;i++){
      await wait(200);const snapshot=await bridge.call('snapshot');
      if(snapshot.apps.length===0){empty=snapshot;break;}
    }
    if(!empty)throw Error('Codex did not close within 10 seconds.');
    const opened=await bridge.call('launch',{stamp:empty.inputStamp,foreground:empty.frontmostPid});
    if(!opened.launched)throw Error('Windows did not reopen Codex with the Badge connection.');
    console.log('Codex reopened with Usage Badge.');
  }finally{bridge.close();}
}
if(require.main===module)main().catch(error=>{console.error(error.message);process.exitCode=1;});
