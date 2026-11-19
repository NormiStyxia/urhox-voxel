(function(window){'use strict';const urlParams=new URLSearchParams(location.search);let verbose=window.WASM_PLAYER_CONFIG?.verbose||false;if(urlParams.get('verbose')==='true')verbose=true;(window.WASM_PLAYER_CONFIG??={}).verbose=verbose;let gameUrl=urlParams.get('game_url')||'';if(gameUrl&&!gameUrl.endsWith('/'))gameUrl+='/';const isPublishGame=/\/g\/[A-Za-z0-9_-]{10,}/.test(location.pathname);(window.UrhoX=window.UrhoX||{}).isPublishGame=isPublishGame;const embedParam=urlParams.get('embed');const isEmbed=embedParam!==null&&embedParam!=='0'&&String(embedParam).toLowerCase()!=='false';(window.UrhoX=window.UrhoX||{}).isEmbed=isEmbed;if(isEmbed){const loadingScreen=document.getElementById('loading-screen');if(loadingScreen)loadingScreen.style.transition='none';const watermark=document.getElementById('watermark-logo');if(watermark)watermark.style.display='none';}
let useLocalEngine=urlParams.get('local_engine');useLocalEngine=useLocalEngine==='true'||useLocalEngine==='1';const localEngineBase='';let debugMemory=urlParams.get('debug_memory');debugMemory=debugMemory==='true'||debugMemory==='1';const disableOpfs=(()=>{const v=urlParams.get('disableOPFS');if(v!==null)return!(v==='0'||v.toLowerCase()==='false');const ua=navigator.userAgent||'';const isIOS=/iPad|iPhone|iPod/.test(ua)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);if(isIOS)return true;return/Safari\//.test(ua)&&!/Chrome|Chromium|CriOS|Edg|OPR|Android/.test(ua);})();window.isInTapFrame=!isPublishGame&&window!==window.parent;(window.UrhoX=window.UrhoX||{}).isInTapFrame=()=>window.isInTapFrame;const _zhCN=/^zh\b/i.test(navigator.language)?{'Loading...':'加载中...','Loading engine...':'加载引擎...','Downloading...':'下载中...','Waiting for window...':'等待窗口响应...','Game running':'游戏运行中','Load failed':'加载失败','Engine error':'引擎异常','WebGL2 unavailable':'WebGL2 不可用','Please enable browser hardware acceleration and WebGL, then reload':'请开启浏览器硬件加速和 WebGL，然后刷新重试','The game ran into a problem, please reload':'游戏遇到问题，请刷新重试','This browser lacks required runtime support':'该浏览器不支持游戏所需的运行环境\n建议使用 Chrome、Edge 和 Safari 浏览器','JS load failed':'JS 加载失败','JS execution failed':'JS 执行失败','Reload':'刷新重试',}:null;function tr(key){return _zhCN?.[key]||key;}
let forceWelcome=window.WASM_PLAYER_CONFIG?.force_welcome||false;const log=(...a)=>console.log('[UrhoX]',...a);const logV=(...a)=>verbose&&log(...a);const error=(...a)=>console.error('[UrhoX]',...a);function hasWebGL2Support(){const canvas=document.createElement('canvas');canvas.width=1;canvas.height=1;let context=null;try{context=canvas.getContext('webgl2',{alpha:true,premultipliedAlpha:false,depth:true,stencil:true,antialias:false,});}catch(e){logV('WebGL2 probe failed:',e);}
if(!context)return false;context.getExtension('WEBGL_lose_context')?.loseContext();return true;}
let multiDebugNum=parseInt(urlParams.get('multiDebugNum'))||0;let directConnectParams=null;const directConnectBase64=urlParams.get('directConnectParams');if(directConnectBase64){logV('[DirectConnect] Found Base64 param, length:',directConnectBase64.length);try{directConnectParams=JSON.parse(atob(directConnectBase64));logV('[DirectConnect] Parsed for JS API');}catch(e){error('[DirectConnect] Failed to parse:',e);}}
let versionInfo=null;let initCallback=null;let initCompleted=false;let initResult=null;let initPrerequisitesReady=false;let webGpuBootstrapResult=null;let tapcodeGameID='';let publishScreenPortrait=String(urlParams.get('screen_orientation')||'').toLowerCase()==='portrait';let envConfig=isPublishGame?{env:'production'}:null;function updateStatus(text){const el=document.getElementById('loading-status');if(el)el.textContent=text;}
let _targetProg=0;let _displayProg=0;let _progLastTime=0;let _progRAF=0;const PROG_MIN_SPEED=2;const PROG_MAX_SPEED=350;let _progCreepSpeed=PROG_MIN_SPEED;function updateProgress(percent){const nextTarget=Math.max(0,Math.min(100,percent));if(nextTarget>_targetProg){_targetProg=nextTarget;}
if(!_progRAF){_progLastTime=performance.now();_progRAF=requestAnimationFrame(_tickProgress);}}
function _applyProgress(val){const bar=document.getElementById('loading-progress-bar');if(bar)bar.style.width=val+'%';const txt=document.getElementById('loading-percent');if(txt)txt.textContent=Math.floor(val)+'%';}
function _tickProgress(now){const dt=Math.min((now-_progLastTime)/1000,0.1);_progLastTime=now;const minD=_progCreepSpeed*dt;const maxD=PROG_MAX_SPEED*dt;const delta=_targetProg-_displayProg;if(delta>0){_displayProg+=Math.max(minD,Math.min(delta,maxD));_displayProg=Math.min(_displayProg,_targetProg);}else{const maxCreep=_targetProg>0?Math.min(_targetProg+5,99):0;if(_displayProg<maxCreep){_displayProg=Math.min(_displayProg+minD,maxCreep);}}
if(_targetProg>=100&&_displayProg>95){_displayProg=100;}
_applyProgress(_displayProg);if(_displayProg<100){_progRAF=requestAnimationFrame(_tickProgress);}else{_progRAF=0;}}
async function fetchJson(url,noCache=false){const hasHash=/-[a-f0-9]{8,}\./i.test(url);let fetchUrl=url;if(noCache||!hasHash){fetchUrl=url+(url.includes('?')?'&':'?')+'v='+(Date.now()/5000|0);}
const r=await fetch(fetchUrl);if(!r.ok)throw new Error(`HTTP ${r.status}: ${url}`);return r.json();}
function triggerInitCallback(result){if(initCompleted)return;initCompleted=true;initResult=result;if(initCallback){try{initCallback(result);}catch(e){console.error('[UrhoX] Callback error:',e);}}}
function tryCompleteInitialization(Module){if(initCompleted)return;const bootstrapResult=webGpuBootstrapResult||(Module&&Module.__urhoxWebGpuBootstrapResult)||null;if(bootstrapResult&&!bootstrapResult.success){triggerInitCallback({success:false,versionInfo,error:bootstrapResult.code||'WebGPUStartupFailed',message:bootstrapResult.message||'WebGPU initialization failed'});return;}
if(!initPrerequisitesReady)return;const requiresWebGpuBootstrap=Module&&typeof Module.__urhoxWebGpuBootstrapComplete==='function';if(requiresWebGpuBootstrap&&(!bootstrapResult||!bootstrapResult.success))return;if(bootstrapResult&&bootstrapResult.code==='WebGL2Fallback'&&bootstrapResult.graphicsReady===false)return;triggerInitCallback({success:true,versionInfo,message:'Ready'});}
function applyCanvasLayoutMode(){document.documentElement.classList.toggle('urhox-portrait-canvas',publishScreenPortrait);logV('Canvas layout mode:',publishScreenPortrait?'portrait':'default');return publishScreenPortrait;}
function ensureCanvasReady(Module){const canvas=document.getElementById('canvas');if(!canvas)return;const rect=canvas.getBoundingClientRect();const hasSize=rect.width>0&&rect.height>0;canvas.style.minWidth='64px';canvas.style.minHeight='64px';if(hasSize){log('Canvas size OK:',rect.width+'x'+rect.height);return;}
const DEP_ID='canvas-viewport-ready';if(!Module['addRunDependency'])return;Module['addRunDependency'](DEP_ID);log('Canvas has zero size, waiting for valid viewport...');updateStatus(tr('Waiting for window...'));const timer=setInterval(()=>{if(window.innerWidth>0&&window.innerHeight>0){clearInterval(timer);log('Viewport ready:',window.innerWidth+'x'+window.innerHeight);Module['removeRunDependency']?.(DEP_ID);}},50);}
const fileMap=new Map();function buildFileMap(files,baseUrl){if(!files?.length)return;for(const f of files){if(f.fs_path&&f.uuid&&f.hash&&f.ext){fileMap.set(f.fs_path,{url:baseUrl+f.uuid+'-'+f.hash+f.ext,size:f.size||0});}}}
function getFileInfo(fsPath){return fileMap.get(fsPath)||fileMap.get('/'+fsPath)||null;}
function getFileUrl(fsPath){return getFileInfo(fsPath)?.url||null;}
function getFileSize(fsPath){return getFileInfo(fsPath)?.size||0;}
let bootstrapMode=false;async function loadEngineManifest(){updateStatus(tr('Loading...'));const cdnOrigin=isPublishGame?location.origin:'https://tapcode-sce.spark.xd.com';const welcomeUrl=cdnOrigin+'/src/welcome/';if(forceWelcome){log('Force welcome mode');gameUrl=welcomeUrl;}
const load=async(engineSrc)=>{try{let engineUrl=engineSrc.base_url||'';if(engineUrl&&isPublishGame){engineUrl=engineUrl.replace(new URL(engineUrl).host,location.host);}
if(engineUrl&&!engineUrl.endsWith('/'))engineUrl+='/';let verName=(engineSrc.tag||'latest')+'.json';if(engineSrc.version)verName=engineSrc.version+'/version.json';const engineVer=await fetchJson(engineUrl+verName);const manifest=await fetchJson(engineUrl+engineVer.version+'/manifest-'+engineVer.client+'.json');buildFileMap(manifest.files,engineUrl+'assets/');const buildVerUrl=getFileUrl('version.json');if(buildVerUrl){fetchJson(buildVerUrl).then(info=>window.__ENGINE_BUILD_INFO__=info).catch(error);}
bootstrapMode=true;}catch(e){error('Load engine manifest failed:',e.message);}};if(isPublishGame){const pk=location.pathname.match(/\/g\/([A-Za-z0-9_-]{10,})/)?.[1];if(!pk){showError('Invalid publish link');return;}
const pkBase=location.origin+'/g/'+pk+'/';if(!gameUrl)gameUrl=pkBase;logV('Publish game mode: loading from '+pkBase);try{const ver=await fetchJson(pkBase+'version.json');if(!ver?.engine){showError('Invalid version info');return;}
await load(await fetchJson(location.origin+'/g/'+'engine-'+ver.engine+'.json'));}catch(e){error('Load engine manifest failed (publish game):',e.message);showError(e.message);}
return;}
let gameLatest;do{const gameLatestUrl=gameUrl+'latest.json';gameLatest=await fetchJson(gameLatestUrl).catch(e=>{log('Missing latest.json:',e.message);return null;});if(!gameLatest||!gameLatest.engine){if(gameUrl!==welcomeUrl){gameUrl=welcomeUrl;continue;}
gameUrl='';return;}
break;}while(true)
try{const engineSrcUrl=gameUrl+gameLatest.version+'/engine-'+gameLatest.engine+'.json';await load(await fetchJson(engineSrcUrl));}catch(e){error('Load engine manifest failed:',e.message);}}
async function loadProjectInfo(){try{const projectUrl=gameUrl?gameUrl+'project.json':'project.json';const info=await fetchJson(projectUrl);if(info?.project_id){tapcodeGameID=info.project_id;log('✓ Project:',tapcodeGameID);}
const tapMakerEnv=window.UrhoX?.getTapMakerEnv?.()||0;publishScreenPortrait||=(isPublishGame||tapMakerEnv===2)&&String(info?.taptap_publish?.screen_orientation||'').toLowerCase()==='portrait';if(publishScreenPortrait){logV('Publish screen orientation: portrait');}}catch(e){logV('Project info failed:',e.message);}}
async function loadEnvConfig(){try{const config=await fetchJson('env.json');if(config?.env){envConfig=config;log('✓ Env:',config.env);}}catch(e){logV('env.json not found');}}
async function downloadWithRetry(url,options={}){const{retries=3,onProgress=null,responseType='arraybuffer',name='文件',onResponse=null}=options;for(let attempt=1;attempt<=retries;attempt++){try{const response=await fetch(url,{credentials:'same-origin'});if(!response.ok){throw new Error(`HTTP ${response.status}`);}
if(onResponse){try{onResponse(response);}catch(e){logV('onResponse hook failed:',e.message);}}
if(onProgress&&response.headers.get('Content-Length')){const total=parseInt(response.headers.get('Content-Length'),10);const reader=response.body.getReader();const chunks=[];let loaded=0;while(true){const{done,value}=await reader.read();if(done)break;chunks.push(value);loaded+=value.length;onProgress(loaded,total);}
const buffer=new Uint8Array(loaded);let offset=0;for(const chunk of chunks){buffer.set(chunk,offset);offset+=chunk.length;}
return responseType==='text'?new TextDecoder().decode(buffer):buffer.buffer;}
return responseType==='text'?await response.text():await response.arrayBuffer();}catch(e){error(`Download failed (attempt ${attempt}/${retries}):`,url,e.message);if(attempt===retries){throw new Error(`${name}加载失败`);}
await new Promise(r=>setTimeout(r,1000*attempt));}}}
const ENGINE_DATA_CACHE='urhox-engine-data-v1';async function downloadEngineDataCached(url,options={}){let cache=null;try{cache=await caches.open(ENGINE_DATA_CACHE);}catch(e){logV('Cache API unavailable:',e.message);}
if(cache){try{const hit=await cache.match(url);if(hit){const buf=await hit.arrayBuffer();log('✓ .data from Cache Storage:',(buf.byteLength/1e6).toFixed(1)+'MB');options.onProgress?.(buf.byteLength,buf.byteLength);return buf;}}catch(e){logV('.data cache match failed:',e.message);}}
return downloadWithRetry(url,{...options,onResponse:cache?(resp)=>{cache.put(url,resp.clone()).then(()=>cache.keys()).then(keys=>{if(keys.length>2){return Promise.all(keys.slice(0,keys.length-2).filter(r=>r.url!==url).map(r=>cache.delete(r)));}}).catch(e=>logV('.data cache put failed:',e.message));}:undefined,});}
let preloadedWasm=null;let preloadedData=null;function initWasmModule(){const existingPreRun=window.Module?.preRun?(Array.isArray(window.Module.preRun)?window.Module.preRun:[window.Module.preRun]):[];const moduleArguments=(window.Module?.arguments?(Array.isArray(window.Module.arguments)?window.Module.arguments:[window.Module.arguments]):[]).filter(a=>a!=='-embed'&&!(typeof a==='string'&&a.startsWith('-embed=')));const excludedParams=['game_url','local_engine','verbose','debug_memory','screen_orientation','disableOPFS','embed','-rendertype'];for(const[key,value]of urlParams.entries()){if(!excludedParams.includes(key)){if(value){moduleArguments.push('-'+key+'='+value);}else{moduleArguments.push('-'+key);}}}
if(window.WASM_PLAYER_CONFIG?.intl&&!moduleArguments.some(a=>a.startsWith('-intl'))){moduleArguments.push('-intl');}
if(disableOpfs&&!moduleArguments.some(a=>a==='-disableOPFS'||a.startsWith('-disableOPFS='))){moduleArguments.push('-disableOPFS');log('OPFS disabled (Safari/iOS or explicit param), bundled engine-res mode');}
if(isEmbed){moduleArguments.push('-embed');}
if(bootstrapMode){const url=gameUrl||(location.origin+location.pathname.substring(0,location.pathname.lastIndexOf('/')+1));moduleArguments.push('-game_url='+url);}
if(forceWelcome){moduleArguments.push('-skip_login');}
const hasServer=moduleArguments.some(a=>a.startsWith('-server'));if(!hasServer){if(envConfig?.env==='production'){moduleArguments.push('-production');}else if(envConfig?.env==='rnd'){moduleArguments.push('-rnd');}}
if(!verbose){moduleArguments.push('-log=WARNING');}
logV('Module.arguments:',moduleArguments);let Module={__urhoxSetUploadContext:window.UrhoX.setUploadContext,preRun:[...existingPreRun,function(){log('Final Module.arguments:',Module.arguments);ensureCanvasReady(Module);if(preloadedWasm||preloadedData){preloadedWasm=null;preloadedData=null;logV('Preloaded data released');}
initPrerequisitesReady=true;tryCompleteInitialization(Module);}],postRun:[function(){if(Module.__urhoxWebGpuStartupError)return;log('=== postRun: Engine ready ===');requestAnimationFrame(()=>window.dispatchEvent(new Event('resize')));if(!bootstrapMode){updateStatus(tr('Game running'));window.UrhoX.hideLoading();}}],wasmBinary:preloadedWasm,getPreloadedPackage:preloadedData?function(name,size){logV('Using preloaded package:',name,size);return preloadedData;}:undefined,locateFile:function(path,prefix){if(useLocalEngine){const resolved=(localEngineBase||prefix)+path;logV('locateFile (local):',path,'->',resolved);return resolved;}
const cdnUrl=getFileUrl(path);if(cdnUrl){logV('locateFile:',path,'->',cdnUrl);return cdnUrl;}
return prefix+path;},print:console.log.bind(console),printErr:console.error.bind(console),onWebGpuBootstrapComplete:function(result){webGpuBootstrapResult=result;tryCompleteInitialization(Module);},onWebGpuStartupError:function(info){if(!document.getElementById('dialog-overlay'))return false;showError(info.message,info.title,info.code+(info.detail?'\n'+info.detail:''));return true;},onAbort:function(what){window.UrhoX.reportCrash(what);if(Module.__urhoxWebGpuStartupError)return;error('Engine aborted:',what);showError(tr('The game ran into a problem, please reload'),tr('Engine error'),what);},canvas:(function(){const c=document.getElementById('canvas');if(c){c.addEventListener('webglcontextlost',e=>{alert('WebGL context lost. You will need to reload the page.');e.preventDefault();},false);c.setAttribute('tabindex','0');c.addEventListener('click',()=>{const ae=document.activeElement;if(ae&&ae.tagName==='INPUT')return;c.focus();});}
return c;})(),setStatus:function(text){if(!text)return;const m=text.match(/\((\d+)\/(\d+)\)/);if(m){const current=parseInt(m[1],10);let total=parseInt(m[2],10);const manifestDataSize=getFileSize('UrhoXRuntime.data');if(manifestDataSize>0){total=manifestDataSize;}else if(current>total){total=current;}
if(total>0){updateProgress((current/total)*100);}}
if(text.includes('Downloading')){updateStatus(tr('Downloading...'));}}};window.Module=Module;Object.defineProperty(window.Module,'arguments',{value:moduleArguments,writable:false,configurable:false});logV('Module.arguments protected:',window.Module.arguments);}
async function loadEngine(){updateStatus(tr('Loading engine...'));if(typeof SharedArrayBuffer==='undefined'){error('SharedArrayBuffer is not available.');showError(tr('This browser lacks required runtime support'));triggerInitCallback({success:false,error:'SharedArrayBuffer is not available.'});return;}
if(!hasWebGL2Support()){error('WebGL2 is not available.');showError(tr('Please enable browser hardware acceleration and WebGL, then reload'),tr('WebGL2 unavailable'));triggerInitCallback({success:false,error:'WebGL2 is not available.'});return;}
updateProgress(0);try{if(useLocalEngine){updateProgress(50);initWasmModule();const s=document.createElement('script');s.src=(localEngineBase||'')+'UrhoXRuntime.js';s.onload=()=>log('✓ Engine loaded (local)');s.onerror=()=>showError(tr('JS load failed'));document.body.appendChild(s);return;}
const jsUrl=getFileUrl('UrhoXRuntime.js');const wasmUrl=getFileUrl('UrhoXRuntime.wasm');const dataUrl=disableOpfs?getFileUrl('UrhoXRuntime.data'):null;if(!jsUrl||!wasmUrl){throw new Error('引擎文件 URL 缺失');}
const jsSize=getFileSize('UrhoXRuntime.js')||0;const wasmSize=getFileSize('UrhoXRuntime.wasm')||0;const dataSize=dataUrl?(getFileSize('UrhoXRuntime.data')||0):0;const totalSize=jsSize+wasmSize+dataSize;let jsLoaded=0,wasmLoaded=0,dataLoaded=0;const updateTotalProgress=()=>{if(totalSize>0){const percent=((jsLoaded+wasmLoaded+dataLoaded)/totalSize)*100;updateProgress(Math.min(percent,100));}};updateStatus(tr('Downloading...'));const downloads=[downloadWithRetry(jsUrl,{responseType:'text',name:'启动脚本',onProgress:(loaded)=>{jsLoaded=loaded;updateTotalProgress();}}),downloadWithRetry(wasmUrl,{name:'引擎',onProgress:(loaded)=>{wasmLoaded=loaded;updateTotalProgress();}})];if(dataUrl){downloads.push(downloadEngineDataCached(dataUrl,{name:'引擎资源',onProgress:(loaded)=>{dataLoaded=loaded;updateTotalProgress();}}).catch(e=>{error('engine-res bundle download failed (fallback to per-file):',e.message);return null;}));}
const results=await Promise.all(downloads);const jsCode=results[0];preloadedWasm=results[1];if(dataUrl&&results[2]){preloadedData=results[2];}
log('✓ Downloads complete'+(dataUrl?'':' (no .data needed)'));updateProgress(100);initWasmModule();const blob=new Blob([jsCode],{type:'application/javascript'});const blobUrl=URL.createObjectURL(blob);const s=document.createElement('script');s.src=blobUrl;s.onload=()=>log('✓ Engine JS executed');s.onerror=()=>showError(tr('JS execution failed'));document.body.appendChild(s);}catch(e){error('Engine load failed:',e);showError(e.message);}}
function showError(message,title,detail){title=title||tr('Load failed');updateStatus(title);UrhoX.showDialog(title,message,tr('Reload'),null,-1);if(detail){const messageEl=document.getElementById('dialog-message');if(messageEl){const d=document.createElement('div');d.textContent=String(detail);d.style.cssText='margin-top:10px;font-size:11px;color:rgba(255,255,255,.35);word-break:break-all;line-height:1.4';messageEl.appendChild(d);}}
const confirmBtn=document.getElementById('dialog-confirm');if(confirmBtn){confirmBtn.onclick=()=>location.reload();}}~function initMemoryDebugHooks(){if(!debugMemory)return;log('🔍 Memory debug hooks enabled');const originalGrow=WebAssembly.Memory.prototype.grow;WebAssembly.Memory.prototype.grow=function(pages){const before=this.buffer.byteLength/1024/1024;const result=originalGrow.call(this,pages);const after=this.buffer.byteLength/1024/1024;const delta=pages*64/1024;console.log(`\n%c[Memory.grow] ${before.toFixed(0)} MB → ${after.toFixed(0)} MB (+${delta.toFixed(0)} MB, ${pages} pages)`,'color: #ff6b6b; font-weight: bold');console.trace('Growth stack:');return result;};}();const OriginalWorker=window.Worker;window.Worker=function(url,options){const isCrossOrigin=url.startsWith('http')&&!url.startsWith(location.origin);if(isCrossOrigin){logV('Cross-origin Worker detected:',url);const xhr=new XMLHttpRequest();xhr.open('GET',url,false);xhr.send();if(xhr.status===200){const blob=new Blob([xhr.responseText],{type:'application/javascript'});const blobUrl=URL.createObjectURL(blob);logV('Worker loaded via Blob URL:',url);return new OriginalWorker(blobUrl,options);}else{throw new Error(`Failed to load Worker: ${url}`);}}
return new OriginalWorker(url,options);};window.Worker.prototype=OriginalWorker.prototype;window.UrhoX=window.UrhoX||{};window.UrhoX.getVersionInfo=()=>window.__ENGINE_BUILD_INFO__||null;window.UrhoX.onReady=function(cb){if(typeof cb!=='function')return;if(initCompleted&&initResult){try{cb(initResult);}catch(e){console.error('[UrhoX] Callback error:',e);}}else{initCallback=cb;}};window.UrhoX.isTapcode=()=>true;window.UrhoX.getTapcodeUrl=()=>{const p=location.pathname;return location.origin+p.substring(0,p.lastIndexOf('/')+1);};window.UrhoX.getTapcodeGameID=()=>tapcodeGameID||'';window.UrhoX.getWebSocketHost=()=>undefined;window.UrhoX.copyToClipboard=(text)=>{window.UrhoX._clipboardCache=text;window.UrhoX._clipboardGen++;try{if(navigator.clipboard&&typeof navigator.clipboard.writeText==="function"){navigator.clipboard.writeText(text).catch(()=>{});}}catch(err){}};window.UrhoX._clipboardCache='';window.UrhoX._clipboardGen=0;document.addEventListener('paste',(e)=>{const text=e.clipboardData?e.clipboardData.getData('text'):'';if(text){window.UrhoX._clipboardCache=text;window.UrhoX._clipboardGen++;}});window.UrhoX.getClipboard=()=>{var gen=window.UrhoX._clipboardGen;if(navigator.clipboard&&navigator.clipboard.readText){navigator.clipboard.readText().then(text=>{if(text&&window.UrhoX._clipboardGen===gen){window.UrhoX._clipboardCache=text;}}).catch(()=>{});}
return window.UrhoX._clipboardCache||'';};window.UrhoX.setLoadingProgress=function(progress,status,incrementSpeed){if(progress>=0){const next=Math.max(0,Math.min(100,progress*100));if(_targetProg>=98&&next<_targetProg){_targetProg=next;_displayProg=next;_applyProgress(next);}
updateProgress(next);}
if(status){updateStatus(status);}
if(incrementSpeed>0){_progCreepSpeed=incrementSpeed*100;}else if(incrementSpeed!==undefined&&incrementSpeed<0){_progCreepSpeed=PROG_MIN_SPEED;}};window.UrhoX.hideLoading=function(){const screen=document.getElementById('loading-screen');if(screen){screen.classList.add('hidden');log('Loading screen hidden');}
window.dispatchEvent(new Event('urhox:loading-hidden'));};window.UrhoX.showLoading=function(){const screen=document.getElementById('loading-screen');if(screen){screen.classList.remove('hidden');}};window.UrhoX.getMultiDebugNum=()=>multiDebugNum;window.UrhoX.getDirectConnectParams=()=>directConnectParams;window.UrhoX.isDirectConnectMode=()=>directConnectParams!==null;window.UrhoX.showDialog=function(title,message,confirmText,cancelText,callbackId){log('showDialog:',title,message);const overlay=document.getElementById('dialog-overlay');const titleEl=document.getElementById('dialog-title');const messageEl=document.getElementById('dialog-message');const confirmBtn=document.getElementById('dialog-confirm');const cancelBtn=document.getElementById('dialog-cancel');if(!overlay){const result=cancelText?confirm(title+'\n\n'+message):(alert(message),true);if(callbackId>=0&&window.Module&&window.Module._UrhoX_DialogCallback){window.Module._UrhoX_DialogCallback(callbackId,result?1:0);}
return;}
titleEl.textContent=title;messageEl.textContent=message;confirmBtn.textContent=confirmText||'OK';if(cancelText){cancelBtn.textContent=cancelText;cancelBtn.classList.remove('hidden');}else{cancelBtn.classList.add('hidden');}
const handleResult=(confirmed)=>{overlay.classList.remove('visible');confirmBtn.onclick=null;cancelBtn.onclick=null;if(callbackId>=0&&window.Module&&window.Module._UrhoX_DialogCallback){window.Module._UrhoX_DialogCallback(callbackId,confirmed?1:0);}};confirmBtn.onclick=()=>handleResult(true);cancelBtn.onclick=()=>handleResult(false);overlay.classList.add('visible');};{const s=document.createElement('style');s.textContent='#dialog-overlay{position:fixed;inset:0;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;z-index:20000;opacity:0;visibility:hidden;transition:opacity .3s,visibility .3s;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)}'+'#dialog-overlay.visible{opacity:1;visibility:visible}'+'#dialog-box{width:min(400px,85vw);background:rgba(30,30,45,.95);border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:32px 28px 24px;display:flex;flex-direction:column;align-items:center;gap:16px;box-shadow:0 24px 80px rgba(0,0,0,.5),0 0 0 1px rgba(255,255,255,.05) inset}'+'#dialog-title{color:rgba(255,255,255,.95);font-size:18px;font-weight:600;margin:0;letter-spacing:.01em}'+'#dialog-message{color:rgba(255,255,255,.6);font-size:14px;text-align:center;line-height:1.6;margin:0;word-break:break-word;white-space:pre-line}'+'#dialog-buttons{display:flex;gap:12px;width:100%;margin-top:8px}'+'.dialog-btn{flex:1;padding:12px 0;font-size:15px;font-weight:500;border:none;border-radius:10px;cursor:pointer;transition:transform .1s,opacity .15s}'+'.dialog-btn:active{transform:scale(.97)}'+'#dialog-confirm{background:linear-gradient(135deg,#5b6af0,#7c5bf0);color:#fff}'+'#dialog-confirm:active{opacity:.85}'+'#dialog-cancel{background:rgba(255,255,255,.08);color:rgba(255,255,255,.7)}'+'#dialog-cancel:active{background:rgba(255,255,255,.12)}'+'#dialog-cancel.hidden{display:none}';(document.head||document.documentElement).appendChild(s);}
document.body.style.backgroundColor='transparent';async function start(){try{await new Promise(resolve=>setTimeout(resolve,0));if(isPublishGame){await loadEngineManifest();}else{await Promise.all([loadEnvConfig(),loadEngineManifest()]);}
await loadProjectInfo();applyCanvasLayoutMode();await loadEngine();}catch(e){console.error('[UrhoX] Fatal:',e);updateStatus(tr('Load failed')+': '+e.message);triggerInitCallback({success:false,error:e.message});}}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',start);}else{start();}})(window);(function(window){'use strict';window.UrhoX=window.UrhoX||{};var context=null;function setUploadContext(json){context=json?JSON.parse(json):null;}
function captureAbortStack(){var previousLimit=Error.stackTraceLimit;try{if(typeof previousLimit==='number'&&previousLimit<32)
Error.stackTraceLimit=32;return new Error('Wasm abort').stack;}finally{if(typeof previousLimit==='number')
Error.stackTraceLimit=previousLimit;}}
function reportCrash(reason){if(!context)
return;try{var entry=Object.assign({},context.metadata);entry.git_info=context.git_info;entry.topic='engine';entry.level='ERROR';entry.log_marker='wasm_crash';entry.message=String(reason&&reason.message||reason||'Unknown abort').slice(0,2048);entry.stack=String(reason&&reason.stack||captureAbortStack()||'').slice(0,8192);entry.time=String(Date.now());var body=JSON.stringify({__topic__:'engine',__source__:entry.platform||'unknown',__logs__:[entry]});if(new TextEncoder().encode(body).byteLength>60*1024)
return;window.fetch(context.url,{method:'POST',headers:{'Content-Type':'application/json'},body:body,credentials:'omit',keepalive:true}).catch(function(){});}catch(error){}}
window.UrhoX.setUploadContext=setUploadContext;window.UrhoX.reportCrash=reportCrash;})(window);(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[TapMakerLogin]',...args);}
function getTapMakerEnv(){var urlParams=new URLSearchParams(window.location.search);if(urlParams.has('enc')){log('getTapMakerEnv: Share (enc param)');return 2;}
if(window.isInTapFrame){log('getTapMakerEnv: Preview (iframe)');return 1;}
log('getTapMakerEnv: None');return 0;}
function getTapMakerCode(){var urlParams=new URLSearchParams(window.location.search);return urlParams.get('enc')||'';}
function getPreviewLoginCode(){var urlParams=new URLSearchParams(window.location.search);if(urlParams.has('enc'))return'';return urlParams.get('preview_login')||'';}
window.UrhoX=window.UrhoX||{};window.UrhoX.getTapMakerEnv=getTapMakerEnv;window.UrhoX.getTapMakerCode=getTapMakerCode;window.UrhoX.getPreviewLoginCode=getPreviewLoginCode;log('TapMaker login extension loaded');})(window);(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;var DEFAULT_TIMEOUT_MS=30000;var inFlight=false;function log(){if(VERBOSE)console.log.apply(console,['[TapBridge]'].concat([].slice.call(arguments)));}
function logWarn(){console.warn.apply(console,['[TapBridge]'].concat([].slice.call(arguments)));}
function isEmbed(){return!!(window.UrhoX&&window.UrhoX.isEmbed===true);}
function hasTapApi(name){if(name==='requestPaymentGameItem')return false;return isEmbed()&&typeof window.tap==='object'&&window.tap!==null&&typeof window.tap[name]==='function';}
function hasTapHostLogin(){return hasTapApi('login');}
function isLoginOk(res){if(!res||typeof res!=='object')return false;return res.errMsg==='login:ok';}
function extractCode(res){if(res==null)return'';if(typeof res==='string')return res;if(typeof res!=='object')return'';if(res.errMsg&&res.errMsg!=='login:ok')return'';if(res.code==null)return'';return String(res.code);}
function extractError(res){if(res==null)return'login failed';if(typeof res==='string')return res;if(res instanceof Error)return res.message||'login failed';if(typeof res==='object'){if(res.errMsg)return String(res.errMsg);if(res.message)return String(res.message);}
return'login failed';}
function notifyCpp(code,error){if(!window.Module||typeof window.Module.ccall!=='function'){logWarn('Engine ccall unavailable, drop tap.login result');return;}
try{window.Module.ccall('UrhoX_OnTapHostLogin',null,['string','string'],[code||'',error||'']);}catch(e){logWarn('ccall UrhoX_OnTapHostLogin failed:',e&&e.message);}}
function invokeTapLogin(timeoutMs){return new Promise(function(resolve,reject){var settled=false;var timer=setTimeout(function(){if(settled)return;settled=true;reject(new Error('timeout'));},timeoutMs);function done(ok,value){if(settled)return;settled=true;clearTimeout(timer);if(ok)resolve(value);else reject(value);}
try{var ret=window.tap.login({timeout:timeoutMs,success:function(res){done(true,res);},fail:function(res){done(false,res);},complete:function(){}});if(ret&&typeof ret.then==='function'){ret.then(function(res){done(true,res);}).catch(function(err){done(false,err);});}}catch(e){done(false,e);}});}
function requestTapHostLogin(){if(inFlight){log('login request ignored, already in flight');return;}
if(!hasTapHostLogin()){notifyCpp('','tap.login unavailable');return;}
inFlight=true;log('calling tap.login');invokeTapLogin(DEFAULT_TIMEOUT_MS).then(function(res){inFlight=false;if(!isLoginOk(res)&&!(res&&res.code)){notifyCpp('',extractError(res));return;}
var code=extractCode(res);if(!code){notifyCpp('','empty code');return;}
log('tap.login ok, code length:',code.length);notifyCpp(code,'');}).catch(function(err){inFlight=false;notifyCpp('',extractError(err));});}
window.UrhoX=window.UrhoX||{};window.UrhoX.tap=window.UrhoX.tap||{};window.UrhoX.tap.has=hasTapApi;window.UrhoX.tap.login=requestTapHostLogin;window.UrhoX.hasTapHostLogin=hasTapHostLogin;window.UrhoX.requestTapHostLogin=requestTapHostLogin;var achievementManager;var achievementListener;var achievementGeneration=0;var pendingRequests=new Map();var rewardedVideoAds=new Map();function adError(error){var result=Object.assign({},error);result.code=error&&error.code!=null?error.code:(error&&error.errCode!=null?error.errCode:(error&&error.errno!=null?error.errno:-1));result.message=error&&(error.message||error.errMsg)||(typeof error==='string'?error:'ad error');return result;}
function rewardedVideoAd(method,options,handle){var owner=rewardedVideoAds.get(handle);var loadSettled=false;function notifyLoad(ok,error){if(loadSettled||(owner&&rewardedVideoAds.get(handle)!==owner))return;loadSettled=true;var data=ok?{success:true}:Object.assign(adError(error),{success:false});emit('rewardedVideoAd',handle,{event:2,request:options.request||0,data:data});}
function notifyError(error){if(owner&&rewardedVideoAds.get(handle)!==owner)return;emit('rewardedVideoAd',handle,{event:1,data:adError(error)});}
function removeListener(index){var callback=owner.listeners[index];owner.listeners[index]=undefined;if(callback)owner.ad[['offClose','offError'][index]](callback);}
try{if(method==='destroy'){if(!owner)return;rewardedVideoAds.delete(handle);try{for(var i=0;i<2;++i){try{removeListener(i);}catch(error){logWarn('ad listener removal failed:',error);}}}finally{owner.ad.destroy();}
return;}
if(!hasTapApi('createRewardedVideoAd'))throw new Error('Tap host RewardedVideoAd is unavailable');if(method==='create'){if(owner)return;owner={ad:window.tap.createRewardedVideoAd(options),listeners:[]};rewardedVideoAds.set(handle,owner);return;}
if(!owner)throw new Error('RewardedVideoAd is unavailable');if(method==='listen'){var index=options.event;removeListener(index);if(!options.enabled)return;var callback=function(data){if(rewardedVideoAds.get(handle)!==owner||owner.listeners[index]!==callback)return;emit('rewardedVideoAd',handle,{event:index,generation:options.generation,data:index===1?adError(data):(data||{})});};owner.listeners[index]=callback;owner.ad[['onClose','onError'][index]](callback);return;}
if(method==='load'){var loading=owner.ad.load({success:function(){notifyLoad(true);},fail:function(error){notifyLoad(false,error);}});if(loading&&typeof loading.then==='function')
loading.then(function(){notifyLoad(true);},function(error){notifyLoad(false,error);});return;}
if(method!=='load'&&method!=='show')throw new Error('Unsupported RewardedVideoAd method');var returned=owner.ad[method]();if(returned&&typeof returned.catch==='function')returned.catch(notifyError);}catch(error){if(method==='load')notifyLoad(false,error);else notifyError(error);}}
function emit(kind,handle,result){if(window.Module&&typeof window.Module.ccall==='function'){window.Module.ccall('UrhoX_OnTapHostResult',null,['string','number','string'],[kind,handle,JSON.stringify(result)]);}}
function failure(error){return{success:false,code:Number(error&&(error.errno||error.code))||-1,message:extractError(error)};}
function request(kind,method,options,handle){var settled=false;var cleanup=function(){};var timer=setTimeout(function(){done(false,new Error('timeout'));},120000);function done(ok,value){if(settled)return;settled=true;clearTimeout(timer);pendingRequests.delete(handle);try{cleanup();}catch(error){logWarn('cleanup failed:',extractError(error));}
emit(kind,handle,ok?{success:true,data:value||{}}:failure(value));}
pendingRequests.set(handle,function(){done(false,new Error('SDK shutdown'));});try{if(!isEmbed())throw new Error('Tap host APIs require embed mode');if(kind!=='ad'&&kind!=='leaderboard')
throw new Error('Unsupported Tap bridge request');if(kind==='ad'){var ad=window.tap.createRewardedVideoAd(options);var onClose=function(result){done(true,result);};var onError=function(error){done(false,error);};cleanup=function(){try{if(ad.offClose)ad.offClose(onClose);if(ad.offError)ad.offError(onError);}finally{ad.destroy();}};ad.onClose(onClose);ad.onError(onError);Promise.resolve(ad.load()).then(function(){if(!settled)return ad.show();}).catch(onError);return;}
var target=window.tap.getLeaderboardManager();options=Object.assign({},options);options.success=function(result){done(true,result);};options.fail=function(error){done(false,error);};options.callback={onSuccess:options.success,onFailure:function(code,message){done(false,{code:code,message:message});}};var returned=target[method](options);if(returned&&typeof returned.then==='function'){returned.then(options.success,options.fail);}}catch(error){done(false,error);}}
function achievement(method,options,generation){try{if(method==='unregisterListener'){achievementGeneration=0;if(achievementManager&&achievementListener)
achievementManager.unregisterListener(achievementListener);achievementListener=undefined;return;}
if(!isEmbed())throw new Error('Tap host APIs require embed mode');if(!achievementManager)achievementManager=window.tap.createAchievementManager();if(method==='registerListener'){achievement('unregisterListener',{},0);achievementGeneration=generation;achievementListener={onAchievementSuccess:function(code,result){if(achievementGeneration===generation)
emit('achievement',generation,{success:true,code:code,data:result});},onAchievementFailure:function(id,code,message){if(achievementGeneration===generation)
emit('achievement',generation,{success:false,achievementId:id,code:code,message:message});}};achievementManager.registerListener(achievementListener);}else if(method==='setToastEnabled'){achievementManager.toastEnable=options.enabled;}else{achievementManager[method](options);}}catch(error){var result=failure(error);result.achievementId=options.achievementId||'';emit('achievement',generation,result);}}
window.UrhoX.tap.request=request;window.UrhoX.tap.achievement=achievement;window.UrhoX.tap.rewardedVideoAd=rewardedVideoAd;window.UrhoX.tap.shutdown=function(){Array.from(rewardedVideoAds.keys()).forEach(function(handle){rewardedVideoAd('destroy',{},handle);});achievement('unregisterListener',{},0);Array.from(pendingRequests.values()).forEach(function(cancel){cancel();});achievementManager=undefined;};window.UrhoX.tap.vibrate=function(method,type){if(!hasTapApi(method))return false;try{var result=window.tap[method]({type:type,fail:function(){}});if(result&&result.catch)result.catch(function(){});return result!==false;}catch(error){return false;}};window.UrhoX.tap.getNativeExitMenuRect=function(){if(!hasTapApi('getMenuButtonBoundingClientRect'))return'';try{var rect=window.tap.getMenuButtonBoundingClientRect();var width=window.innerWidth;var height=window.innerHeight;if(!rect||!(width>0&&height>0))return'';var normalized={left:rect.left/width,top:rect.top/height,right:rect.right/width,bottom:rect.bottom/height};if(!Object.values(normalized).every(Number.isFinite))return'';return JSON.stringify(normalized);}catch(error){return'';}};log('loaded, has login:',hasTapHostLogin());})(window);(function(){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[Audio]',...args);}
function logWarn(...args){console.warn('[Audio]',...args);}
var audioUnlocked=false;var unlockAttempts=0;var maxAttempts=10;var checkModuleInterval=null;var events=['touchstart','touchend','mousedown','click','keydown'];function cleanup(){events.forEach(function(eventName){document.removeEventListener(eventName,onUserInteraction);});if(checkModuleInterval){clearInterval(checkModuleInterval);checkModuleInterval=null;}
log('Cleanup completed, event listeners removed');}
function markUnlocked(){if(audioUnlocked)return;audioUnlocked=true;cleanup();}
function tryUnlockAudio(){if(audioUnlocked||unlockAttempts>=maxAttempts)return;unlockAttempts++;if(typeof Module!=='undefined'&&Module.SDL2&&Module.SDL2.audioContext){var ctx=Module.SDL2.audioContext;if(ctx.state==='suspended'){log('Attempting to resume SDL2 AudioContext (attempt '+unlockAttempts+')');ctx.resume().then(function(){log('SDL2 AudioContext resumed successfully');markUnlocked();}).catch(function(err){logWarn('Failed to resume SDL2 AudioContext:',err);});}else if(ctx.state==='running'){log('SDL2 AudioContext already running');markUnlocked();}}}
function onUserInteraction(e){if(audioUnlocked)return;log('User interaction detected:',e.type);tryUnlockAudio();if(!audioUnlocked){setTimeout(tryUnlockAudio,100);setTimeout(tryUnlockAudio,300);setTimeout(tryUnlockAudio,500);setTimeout(tryUnlockAudio,1000);}}
events.forEach(function(eventName){document.addEventListener(eventName,onUserInteraction,{passive:true});});checkModuleInterval=setInterval(function(){if(typeof Module!=='undefined'&&Module.SDL2&&Module.SDL2.audioContext){if(Module.SDL2.audioContext.state==='running'){log('AudioContext already running at init');markUnlocked();}}},500);setTimeout(function(){if(checkModuleInterval){clearInterval(checkModuleInterval);checkModuleInterval=null;}},30000);log('Web audio unlock script initialized');})();(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[QRCodeLogin]',...args);}
function logWarn(...args){console.warn('[QRCodeLogin]',...args);}
function logError(...args){console.error('[QRCodeLogin]',...args);}
const CONFIG={qrCodeSize:200,modalPadding:40,colors:{overlay:'rgba(0, 0, 0, 0.85)',modalBg:'#26262a',title:'#ffffff',hint:'#999999',qrBorder:'#ffffff',expiredOverlay:'rgba(0, 0, 0, 0.75)'}};const lang=navigator.language||'zh-CN';const isZh=lang.startsWith('zh');const isIntl=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.intl;const appName=isIntl?'TapTap Maker':'TapTap';const TEXT=isZh?{title:appName+' 扫码登录',hint:'请使用 '+appName+' APP 扫描二维码',refreshing:'刷新中...',expired:'二维码已过期，正在刷新...'}:{title:appName+' Scan Login',hint:'Open '+appName+' APP to scan',refreshing:'Refreshing...',expired:'QR code expired, refreshing...'};let modalElement=null;let isExpired=false;function injectStyles(){const styleId='qrcode-login-styles';if(document.getElementById(styleId))return;const style=document.createElement('style');style.id=styleId;style.textContent=`
      .qrcode-login-overlay {
        position: fixed;
        inset: 0;
        background: ${CONFIG.colors.overlay};
        z-index: 100000;
        display: flex;
        align-items: center;
        justify-content: center;
        animation: qrcode-fade-in 0.3s ease;
      }

      @keyframes qrcode-fade-in {
        from { opacity: 0; }
        to { opacity: 1; }
      }

      @keyframes qrcode-fade-out {
        from { opacity: 1; }
        to { opacity: 0; }
      }

      .qrcode-login-modal {
        background: ${CONFIG.colors.modalBg};
        border-radius: 16px;
        padding: ${CONFIG.modalPadding}px;
        text-align: center;
        box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
        animation: qrcode-modal-in 0.3s ease;
      }

      @keyframes qrcode-modal-in {
        from {
          opacity: 0;
          transform: scale(0.95) translateY(-10px);
        }
        to {
          opacity: 1;
          transform: scale(1) translateY(0);
        }
      }

      .qrcode-login-title {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        font-size: 22px;
        font-weight: 600;
        color: ${CONFIG.colors.title};
        margin: 0 0 16px 0;
      }

      .qrcode-login-container {
        position: relative;
        display: inline-block;
        padding: 8px;
        background: ${CONFIG.colors.qrBorder};
        border-radius: 8px;
      }

      .qrcode-login-image {
        display: block;
        width: ${CONFIG.qrCodeSize}px;
        height: ${CONFIG.qrCodeSize}px;
      }

      .qrcode-login-expired-overlay {
        position: absolute;
        inset: 8px;
        background: ${CONFIG.colors.expiredOverlay};
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        border-radius: 4px;
      }

      .qrcode-login-loading {
        width: 40px;
        height: 40px;
        border: 3px solid rgba(255, 255, 255, 0.3);
        border-top-color: #fff;
        border-radius: 50%;
        animation: qrcode-spin 1s linear infinite;
      }

      @keyframes qrcode-spin {
        to { transform: rotate(360deg); }
      }

      .qrcode-login-expired-text {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        font-size: 14px;
        color: #fff;
        margin-top: 12px;
      }

      .qrcode-login-hint {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        font-size: 14px;
        color: ${CONFIG.colors.hint};
        margin: 16px 0 0 0;
      }
    `;document.head.appendChild(style);}
let qrLibLoaded=false;function loadQRCodeLib(){return new Promise((resolve,reject)=>{if(qrLibLoaded||window.QRCode){qrLibLoaded=true;resolve();return;}
var cdnOrigin=(window.UrhoX&&window.UrhoX.isPublishGame)?location.origin:'https://tapcode-sce.spark.xd.com';const script=document.createElement('script');script.src=cdnOrigin+'/src/web/libs/qrcode.min.js';script.onload=()=>{qrLibLoaded=true;log('QR code library loaded');resolve();};script.onerror=()=>reject(new Error('Failed to load QR code library'));document.head.appendChild(script);});}
function generateQRCodeDataUrl(content){if(!window.qrcode){logError('QR code library not loaded');return null;}
try{const qr=window.qrcode(0,'M');qr.addData(content);qr.make();const moduleCount=qr.getModuleCount();const cellSize=Math.floor(CONFIG.qrCodeSize/moduleCount);const size=moduleCount*cellSize;const canvas=document.createElement('canvas');canvas.width=size;canvas.height=size;const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,size,size);ctx.fillStyle='#000000';for(let row=0;row<moduleCount;row++){for(let col=0;col<moduleCount;col++){if(qr.isDark(row,col)){ctx.fillRect(col*cellSize,row*cellSize,cellSize,cellSize);}}}
return canvas.toDataURL('image/png');}catch(e){logError('Failed to generate QR code:',e);return null;}}
async function showQRCode(qrcodeUrl){log('showQRCode:',qrcodeUrl);injectStyles();isExpired=false;hideQRCode(true);modalElement=document.createElement('div');modalElement.className='qrcode-login-overlay';modalElement.id='qrcode-login-overlay';const modal=document.createElement('div');modal.className='qrcode-login-modal';const title=document.createElement('h2');title.className='qrcode-login-title';title.textContent=TEXT.title;modal.appendChild(title);const container=document.createElement('div');container.className='qrcode-login-container';container.id='qrcode-login-container';let qrDataUrl=null;try{await loadQRCodeLib();qrDataUrl=generateQRCodeDataUrl(qrcodeUrl);}catch(e){logError('Failed to load QR code library:',e);}
const img=document.createElement('img');img.className='qrcode-login-image';img.alt='QR Code';if(qrDataUrl){img.src=qrDataUrl;}else{logError('Failed to generate QR code');img.style.display='none';const fallback=document.createElement('div');fallback.style.cssText=`
        width: ${CONFIG.qrCodeSize}px;
        height: ${CONFIG.qrCodeSize}px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 12px;
        color: #333;
        word-break: break-all;
        padding: 10px;
        box-sizing: border-box;
      `;fallback.textContent=qrcodeUrl;container.appendChild(fallback);};container.appendChild(img);modal.appendChild(container);const hint=document.createElement('p');hint.className='qrcode-login-hint';hint.id='qrcode-login-hint';hint.textContent=TEXT.hint;modal.appendChild(hint);modalElement.appendChild(modal);document.body.appendChild(modalElement);log('QR code modal shown');}
function hideQRCode(immediate){if(!modalElement)return;log('hideQRCode');if(immediate){modalElement.remove();modalElement=null;}else{modalElement.style.animation='qrcode-fade-out 0.2s ease forwards';const el=modalElement;setTimeout(()=>{if(el&&el.parentNode){el.remove();}
if(modalElement===el){modalElement=null;}},200);}
isExpired=false;log('QR code modal hidden');}
function showQRCodeExpired(){if(!modalElement||isExpired)return;log('showQRCodeExpired');isExpired=true;const container=document.getElementById('qrcode-login-container');const hint=document.getElementById('qrcode-login-hint');if(container){const overlay=document.createElement('div');overlay.className='qrcode-login-expired-overlay';const spinner=document.createElement('div');spinner.className='qrcode-login-loading';overlay.appendChild(spinner);const text=document.createElement('div');text.className='qrcode-login-expired-text';text.textContent=TEXT.refreshing;overlay.appendChild(text);container.appendChild(overlay);}
if(hint){hint.textContent=TEXT.expired;}
log('Expired state shown');}
window.UrhoX=window.UrhoX||{};window.UrhoX.showQRCode=showQRCode;window.UrhoX.hideQRCode=function(){hideQRCode(false);};window.UrhoX.showQRCodeExpired=showQRCodeExpired;log('QR code login extension loaded, isInTapFrame:',window.isInTapFrame);})(window);(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[FloatingActionButton]',...args);}
function logWarn(...args){console.warn('[FloatingActionButton]',...args);}
function logError(...args){console.error('[FloatingActionButton]',...args);}
const CONFIG={position:{left:16,top:16},fabSize:52,actionSize:46,animationDuration:200,colors:{bg:'rgba(255, 255, 255, 0.5)',bgHover:'rgba(255, 255, 255, 0.65)',border:'rgba(255, 255, 255, 0.3)',text:'#fff'}};const ENV={isMobile:(function(){const ua=navigator.userAgent;return/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(ua)||(window.innerWidth<=768&&'ontouchstart'in window);})(),isIOS:(function(){return/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);})(),isInStandaloneMode:(function(){return window.navigator.standalone===true||window.matchMedia('(display-mode: standalone)').matches;})(),isInIframe:!!window.isInTapFrame,isPublishGame:!!(window.UrhoX&&window.UrhoX.isPublishGame),isEmbed:!!(window.UrhoX&&window.UrhoX.isEmbed),supportsFullscreen:(function(){return!!(document.documentElement.requestFullscreen||document.documentElement.webkitRequestFullscreen||document.documentElement.mozRequestFullScreen||document.documentElement.msRequestFullscreen);})()};log('环境检测:',ENV);function setManifestOrientation(orientation){const manifest={name:document.title||'UrhoX Game',short_name:'UrhoX',start_url:window.location.href,display:'fullscreen',orientation:orientation,background_color:'#000000',theme_color:'#000000',icons:[{src:'icon-192.png',sizes:'192x192',type:'image/png'},{src:'icon-512.png',sizes:'512x512',type:'image/png'}]};const blob=new Blob([JSON.stringify(manifest)],{type:'application/json'});const url=URL.createObjectURL(blob);let link=document.querySelector('link[rel="manifest"]');if(!link){link=document.createElement('link');link.rel='manifest';document.head.appendChild(link);}
link.href=url;setMeta('apple-mobile-web-app-capable','yes');setMeta('apple-mobile-web-app-status-bar-style','black-translucent');setMeta('apple-mobile-web-app-title',manifest.short_name);log('Manifest 已设置:',orientation);}
function setMeta(name,content){let meta=document.querySelector(`meta[name="${name}"]`);if(!meta){meta=document.createElement('meta');meta.name=name;document.head.appendChild(meta);}
meta.content=content;}
function showIOSRotateGuide(){const existing=document.getElementById('ios-pwa-guide');if(existing)existing.remove();const guide=document.createElement('div');guide.id='ios-pwa-guide';guide.innerHTML=`
      <style>
        #ios-pwa-guide {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.92);
          z-index: 999999;
          display: flex;
          align-items: center;
          justify-content: center;
          animation: iosGuideIn 0.3s ease;
        }
        @keyframes iosGuideIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        #ios-pwa-guide-box {
          background: linear-gradient(145deg, #2a2a2a, #1a1a1a);
          border-radius: 20px;
          padding: 35px 30px;
          max-width: 340px;
          width: 90%;
          text-align: center;
          color: #fff;
          box-shadow: 0 20px 60px rgba(0,0,0,0.5);
          border: 1px solid rgba(255,255,255,0.1);
        }
        #ios-pwa-guide-box h2 {
          margin: 0 0 12px;
          font-size: 22px;
          font-weight: 600;
        }
        #ios-pwa-guide-box .subtitle {
          color: #888;
          font-size: 14px;
          margin: 0 0 20px;
          line-height: 1.5;
        }
        #ios-pwa-guide-box .rotate-icon {
          font-size: 64px;
          margin: 20px 0;
          animation: rotateHint 2s ease-in-out infinite;
          position: relative;
          z-index: 0;
        }
        @keyframes rotateHint {
          0%, 100% { transform: rotate(0deg); }
          50% { transform: rotate(90deg); }
        }
        #ios-pwa-guide-close {
          position: relative;
          z-index: 1;
          background: linear-gradient(135deg, #4a9eff, #2d7ed9);
          border: none;
          color: #fff;
          padding: 14px 40px;
          border-radius: 12px;
          font-size: 16px;
          font-weight: 500;
          cursor: pointer;
          margin-top: 10px;
        }
      </style>
      <div id="ios-pwa-guide-box">
        <h2>📱 请旋转您的设备</h2>
        <p class="subtitle">iOS 不支持自动转屏<br>请手动将设备横过来</p>
        <div class="rotate-icon">📱</div>
        <button id="ios-pwa-guide-close">我知道了</button>
      </div>
    `;document.body.appendChild(guide);const checkOrientation=()=>{if(window.innerWidth>window.innerHeight){guide.remove();window.removeEventListener('resize',checkOrientation);}};window.addEventListener('resize',checkOrientation);document.getElementById('ios-pwa-guide-close').onclick=()=>{guide.style.animation='iosGuideIn 0.2s ease reverse';setTimeout(()=>guide.remove(),200);window.removeEventListener('resize',checkOrientation);};guide.onclick=(e)=>{if(e.target===guide){guide.style.animation='iosGuideIn 0.2s ease reverse';setTimeout(()=>guide.remove(),200);window.removeEventListener('resize',checkOrientation);}};}
function showIOSFullscreenGuide(){setManifestOrientation('landscape');const existing=document.getElementById('ios-pwa-guide');if(existing)existing.remove();const guide=document.createElement('div');guide.id='ios-pwa-guide';guide.innerHTML=`
      <style>
        #ios-pwa-guide {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.92);
          z-index: 999999;
          display: flex;
          align-items: center;
          justify-content: center;
          animation: iosGuideIn 0.3s ease;
        }
        @keyframes iosGuideIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        #ios-pwa-guide-box {
          background: linear-gradient(145deg, #2a2a2a, #1a1a1a);
          border-radius: 20px;
          padding: 35px 30px;
          max-width: 340px;
          width: 90%;
          text-align: center;
          color: #fff;
          box-shadow: 0 20px 60px rgba(0,0,0,0.5);
          border: 1px solid rgba(255,255,255,0.1);
        }
        #ios-pwa-guide-box h2 {
          margin: 0 0 12px;
          font-size: 22px;
          font-weight: 600;
        }
        #ios-pwa-guide-box .subtitle {
          color: #888;
          font-size: 14px;
          margin: 0 0 25px;
          line-height: 1.5;
        }
        #ios-pwa-guide-box .steps {
          text-align: left;
          margin: 0 0 25px;
          padding: 0 10px;
        }
        #ios-pwa-guide-box .step {
          display: flex;
          align-items: center;
          gap: 14px;
          margin: 16px 0;
          font-size: 15px;
        }
        #ios-pwa-guide-box .step-icon {
          width: 36px;
          height: 36px;
          background: rgba(74, 158, 255, 0.15);
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 18px;
          flex-shrink: 0;
        }
        #ios-pwa-guide-box .step-text b {
          color: #4a9eff;
        }
        #ios-pwa-guide-close {
          background: linear-gradient(135deg, #4a9eff, #2d7ed9);
          border: none;
          color: #fff;
          padding: 14px 40px;
          border-radius: 12px;
          font-size: 16px;
          font-weight: 500;
          cursor: pointer;
        }
      </style>
      <div id="ios-pwa-guide-box">
        <h2>📱 沉浸式体验</h2>
        <p class="subtitle">iOS 浏览器限制，请添加到主屏幕<br>即可享受全屏游戏</p>
        <div class="steps">
          <div class="step">
            <span class="step-icon">⬆️</span>
            <span class="step-text">点击底部 <b>分享</b> 按钮</span>
          </div>
          <div class="step">
            <span class="step-icon">➕</span>
            <span class="step-text">选择 <b>「添加到主屏幕」</b></span>
          </div>
          <div class="step">
            <span class="step-icon">🚀</span>
            <span class="step-text">从主屏幕启动即可</span>
          </div>
        </div>
        <button id="ios-pwa-guide-close">我知道了</button>
      </div>
    `;document.body.appendChild(guide);document.getElementById('ios-pwa-guide-close').onclick=()=>{guide.style.animation='iosGuideIn 0.2s ease reverse';setTimeout(()=>guide.remove(),200);};guide.onclick=(e)=>{if(e.target===guide){guide.style.animation='iosGuideIn 0.2s ease reverse';setTimeout(()=>guide.remove(),200);}};}
function injectStyles(){const styleId='floating-action-button-styles';if(document.getElementById(styleId))return;const style=document.createElement('style');style.id=styleId;style.textContent=`
      .fab-container {
        position: fixed;
        left: ${CONFIG.position.left}px;
        top: ${CONFIG.position.top}px;
        z-index: 99999;
        pointer-events: none;
      }

      .fab-main {
        width: ${CONFIG.fabSize}px;
        height: ${CONFIG.fabSize}px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.15);
        border: 1px solid rgba(255, 255, 255, 0.2);
        cursor: pointer;
        pointer-events: auto;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: all ${CONFIG.animationDuration}ms ease;
        -webkit-tap-highlight-color: transparent;
        user-select: none;
      }

      .fab-main:hover {
        background: rgba(255, 255, 255, 0.25);
      }

      .fab-main:active {
        transform: scale(0.95);
      }

      .fab-main.expanded {
        background: rgba(255, 255, 255, 0.25);
      }

      .fab-icon {
        width: 20px;
        height: 20px;
      }

      .fab-icon svg {
        width: 100%;
        height: 100%;
        fill: ${CONFIG.colors.text};
      }

      .fab-menu {
        position: absolute;
        top: 0;
        left: 0;
        pointer-events: none;
      }

      .fab-action {
        position: absolute;
        width: ${CONFIG.actionSize}px;
        height: ${CONFIG.actionSize}px;
        border-radius: 50%;
        background: ${CONFIG.colors.bg};
        border: 1px solid ${CONFIG.colors.border};
        cursor: pointer;
        pointer-events: none;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: all ${CONFIG.animationDuration}ms ease;
        opacity: 0;
        transform: translateY(-8px);
        top: 0;
        left: ${(CONFIG.fabSize - CONFIG.actionSize) / 2}px;
        -webkit-tap-highlight-color: transparent;
        user-select: none;
      }

      .fab-action.visible {
        opacity: 1;
        transform: translateY(0);
        pointer-events: auto;
      }

      .fab-action:hover {
        background: ${CONFIG.colors.bgHover};
      }

      .fab-action:active {
        transform: scale(0.95);
      }

      .fab-action-icon {
        font-size: 20px;
        line-height: 1;
      }

      .fab-action-label {
        position: absolute;
        left: calc(100% + 8px);
        top: 50%;
        transform: translateY(-50%);
        background: ${CONFIG.colors.bg};
        color: #fff;
        padding: 6px 12px;
        border-radius: 12px;
        font-size: 13px;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        white-space: nowrap;
        opacity: 0;
        pointer-events: none;
        transition: opacity 150ms ease;
        border: 1px solid ${CONFIG.colors.border};
      }

      .fab-action:hover .fab-action-label {
        opacity: 1;
      }

      .fab-overlay {
        position: fixed;
        inset: 0;
        background: transparent;
        opacity: 0;
        pointer-events: none;
        transition: opacity ${CONFIG.animationDuration}ms ease;
        z-index: 99998;
      }

      .fab-overlay.visible {
        opacity: 1;
        pointer-events: auto;
      }

      .fab-container.dragging .fab-main {
        cursor: grabbing;
      }

      @media (max-width: 768px) {
        .fab-action-label {
          display: none;
        }
      }
    `;document.head.appendChild(style);}
class FloatingActionButton{constructor(){this.actions=new Map();this.isExpanded=false;this.isDragging=false;this.dragStartPos=null;this.fabStartPos=null;this.container=null;this.overlay=null;this.mainButton=null;this.menuContainer=null;this.currentPosition={left:CONFIG.position.left,top:CONFIG.position.top};this.animationTimers=[];this.toggle=this.toggle.bind(this);this.expand=this.expand.bind(this);this.collapse=this.collapse.bind(this);this.handleDragStart=this.handleDragStart.bind(this);this.handleDragMove=this.handleDragMove.bind(this);this.handleDragEnd=this.handleDragEnd.bind(this);}
clearAnimationTimers(){this.animationTimers.forEach(timer=>clearTimeout(timer));this.animationTimers=[];}
init(){injectStyles();this.createElements();this.registerDefaultActions();this.setupEventListeners();this.render();this.updateVisibility();if(this.actions.size>0){log('✓ 悬浮球功能集合已初始化，共 '+this.actions.size+' 个功能');}else{log('✓ 悬浮球已初始化，当前无可用功能（等待其他扩展注册）');}}
createElements(){this.overlay=document.createElement('div');this.overlay.className='fab-overlay';document.body.appendChild(this.overlay);this.container=document.createElement('div');this.container.className='fab-container';this.container.id='floatingActionButtonContainer';this.menuContainer=document.createElement('div');this.menuContainer.className='fab-menu';this.mainButton=document.createElement('button');this.mainButton.className='fab-main';this.mainButton.setAttribute('aria-label','功能菜单');this.mainButton.innerHTML=`
        <span class="fab-icon">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/>
          </svg>
        </span>
      `;this.container.appendChild(this.menuContainer);this.container.appendChild(this.mainButton);document.body.appendChild(this.container);}
registerDefaultActions(){if(ENV.isMobile){this.registerAction({id:'orientation',icon:'🔄',label:'转屏',order:1,onClick:()=>{if(ENV.isIOS){showIOSRotateGuide();this.collapse();return;}
this.toggleOrientation();this.collapse();}});}
if(!ENV.isInIframe){if(ENV.isIOS&&!ENV.isInStandaloneMode){this.registerAction({id:'fullscreen',icon:'⛶',label:'全屏',order:2,onClick:()=>{showIOSFullscreenGuide();this.collapse();}});}else if(ENV.supportsFullscreen){this.registerAction({id:'fullscreen',icon:'⛶',label:'全屏',order:2,onClick:()=>{this.toggleFullscreen();this.collapse();}});}}}
setupEventListeners(){this.mainButton.addEventListener('click',(e)=>{if(!this.isDragging){this.toggle();}});this.overlay.addEventListener('click',this.collapse);this.mainButton.addEventListener('mousedown',this.handleDragStart);this.mainButton.addEventListener('touchstart',this.handleDragStart,{passive:false});document.addEventListener('mousemove',this.handleDragMove);document.addEventListener('touchmove',this.handleDragMove,{passive:false});document.addEventListener('mouseup',this.handleDragEnd);document.addEventListener('touchend',this.handleDragEnd);document.addEventListener('keydown',(e)=>{if(e.key==='Escape'&&this.isExpanded){this.collapse();}});}
toggle(){if(this.isExpanded){this.collapse();}else{this.expand();}}
expand(){if(this.isExpanded)return;this.clearAnimationTimers();this.isExpanded=true;this.mainButton.classList.add('expanded');this.overlay.classList.add('visible');const actionButtons=this.menuContainer.querySelectorAll('.fab-action');actionButtons.forEach((btn,index)=>{const timer=setTimeout(()=>{btn.classList.add('visible');},index*40);this.animationTimers.push(timer);});}
collapse(){if(!this.isExpanded)return;this.clearAnimationTimers();this.isExpanded=false;this.mainButton.classList.remove('expanded');this.overlay.classList.remove('visible');const actionButtons=this.menuContainer.querySelectorAll('.fab-action');actionButtons.forEach(btn=>{btn.classList.remove('visible');});}
render(){if(!this.menuContainer){logWarn('DOM 尚未创建，延迟渲染');return;}
this.menuContainer.innerHTML='';const sortedActions=Array.from(this.actions.values()).sort((a,b)=>(a.order||100)-(b.order||100));const totalActions=sortedActions.length;this.updateVisibility();sortedActions.forEach((action,index)=>{const btn=document.createElement('button');btn.className='fab-action';btn.setAttribute('data-action-id',action.id);btn.setAttribute('aria-label',action.label);const spacing=CONFIG.actionSize+6;const y=CONFIG.fabSize+6+index*spacing;btn.style.left=`${(CONFIG.fabSize - CONFIG.actionSize) / 2}px`;btn.style.top=`${y}px`;btn.innerHTML=`
          <span class="fab-action-icon">${action.icon}</span>
          <span class="fab-action-label">${action.label}</span>
        `;btn.addEventListener('click',(e)=>{e.stopPropagation();if(typeof action.onClick==='function'){action.onClick();}});this.menuContainer.appendChild(btn);});}
updateVisibility(){const hasActions=this.actions.size>0;if(this.container){this.container.style.display=hasActions?'block':'none';}
if(!hasActions){log('没有可用功能，悬浮球已隐藏');}}
handleDragStart(e){if(this.isExpanded)return;const touch=e.touches?e.touches[0]:e;this.dragStartPos={x:touch.clientX,y:touch.clientY};this.fabStartPos={...this.currentPosition};this.dragTimeout=setTimeout(()=>{this.isDragging=true;this.container.classList.add('dragging');},150);}
handleDragMove(e){if(!this.dragStartPos)return;const touch=e.touches?e.touches[0]:e;const deltaX=touch.clientX-this.dragStartPos.x;const deltaY=touch.clientY-this.dragStartPos.y;if(!this.isDragging&&(Math.abs(deltaX)>10||Math.abs(deltaY)>10)){this.isDragging=true;this.container.classList.add('dragging');if(this.dragTimeout){clearTimeout(this.dragTimeout);}}
if(this.isDragging){e.preventDefault();const newLeft=Math.max(10,Math.min(window.innerWidth-CONFIG.fabSize-10,this.fabStartPos.left+deltaX));const newTop=Math.max(10,Math.min(window.innerHeight-CONFIG.fabSize-10,this.fabStartPos.top+deltaY));this.currentPosition={left:newLeft,top:newTop};this.container.style.left=newLeft+'px';this.container.style.top=newTop+'px';}}
handleDragEnd(e){if(this.dragTimeout){clearTimeout(this.dragTimeout);}
if(this.isDragging){this.container.classList.remove('dragging');setTimeout(()=>{this.isDragging=false;},50);}else{this.isDragging=false;}
this.dragStartPos=null;this.fabStartPos=null;}
async toggleOrientation(){if(this._orientationLock){return;}
this._orientationLock=true;setTimeout(()=>{this._orientationLock=false;},500);const isLandscape=window.innerWidth>window.innerHeight;const targetOrientation=isLandscape?'portrait':'landscape';try{if(!document.fullscreenElement&&!document.webkitFullscreenElement){const elem=document.documentElement;if(elem.requestFullscreen){await elem.requestFullscreen();}else if(elem.webkitRequestFullscreen){await elem.webkitRequestFullscreen();}}
if(screen.orientation&&screen.orientation.lock){await screen.orientation.lock(targetOrientation);}else if(screen.mozLockOrientation){screen.mozLockOrientation(targetOrientation);}else if(screen.lockOrientation){screen.lockOrientation(targetOrientation);}
setTimeout(()=>{window.dispatchEvent(new Event('resize'));if(window.screenAdapter&&typeof window.screenAdapter.handleResize==='function'){window.screenAdapter.handleResize();}},100);}catch(error){logWarn('转屏操作失败:',error.message);}}
toggleFullscreen(){if(this._fullscreenLock){return;}
this._fullscreenLock=true;setTimeout(()=>{this._fullscreenLock=false;},500);if(!document.fullscreenElement&&!document.webkitFullscreenElement){const elem=document.documentElement;if(elem.requestFullscreen){elem.requestFullscreen();}else if(elem.webkitRequestFullscreen){elem.webkitRequestFullscreen();}else if(elem.mozRequestFullScreen){elem.mozRequestFullScreen();}else if(elem.msRequestFullscreen){elem.msRequestFullscreen();}
this.updateFullscreenIcon(true);}else{if(document.exitFullscreen){document.exitFullscreen();}else if(document.webkitExitFullscreen){document.webkitExitFullscreen();}else if(document.mozCancelFullScreen){document.mozCancelFullScreen();}else if(document.msExitFullscreen){document.msExitFullscreen();}
this.updateFullscreenIcon(false);}}
updateFullscreenIcon(isFullscreen){const action=this.actions.get('fullscreen');if(action){action.icon=isFullscreen?'⛶':'⛶';action.label=isFullscreen?'退出全屏':'全屏';this.render();}}
registerAction(action){if(!action.id){logError('注册动作需要提供 id');return false;}
this.actions.set(action.id,{id:action.id,icon:action.icon||'⚙️',label:action.label||action.id,onClick:action.onClick,order:action.order||100});this.render();log(`✓ 已注册动作: ${action.id} (当前共 ${this.actions.size} 个)`);return true;}
unregisterAction(actionId){if(this.actions.has(actionId)){this.actions.delete(actionId);this.render();log(`✓ 已注销动作: ${actionId} (当前共 ${this.actions.size} 个)`);return true;}
return false;}
getEnv(){return{...ENV};}
updateAction(actionId,updates){const action=this.actions.get(actionId);if(action){Object.assign(action,updates);this.render();return true;}
return false;}
getActions(){return Array.from(this.actions.values());}
setPosition(position){if(position.left!==undefined){this.currentPosition.left=position.left;this.container.style.left=position.left+'px';}
if(position.top!==undefined){this.currentPosition.top=position.top;this.container.style.top=position.top+'px';}}
setVisible(visible){this.container.style.display=visible?'block':'none';}
destroy(){this.collapse();if(this.container){this.container.remove();}
if(this.overlay){this.overlay.remove();}
const style=document.getElementById('floating-action-button-styles');if(style){style.remove();}
log('✓ 已销毁');}}
if(ENV.isInIframe||ENV.isPublishGame||ENV.isEmbed){window.floatingActionButton={registerAction:function(){},updateAction:function(){},collapse:function(){}};return;}
const instance=new FloatingActionButton();function initFAB(){instance.init();}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',initFAB);}else{initFAB();}
document.addEventListener('fullscreenchange',()=>{instance.updateFullscreenIcon(!!document.fullscreenElement);});document.addEventListener('webkitfullscreenchange',()=>{instance.updateFullscreenIcon(!!document.webkitFullscreenElement);});window.floatingActionButton=instance;window.FloatingActionButton=FloatingActionButton;window.FloatingActionButtonEnv=ENV;})(window);(function(){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[ErrorClipboard]',...args);}
function isDebugClient(){var urlParams=new URLSearchParams(window.location.search);return urlParams.has('directConnectParams')||urlParams.has('debug');}
var enabled=window.isInTapFrame||isDebugClient();if(!enabled)
return;function injectStyles(){const styleId='error-clipboard-styles';if(document.getElementById(styleId)){return;}
const style=document.createElement('style');style.id=styleId;style.textContent=`
      /* 错误复制按钮样式 */
      #copy-errors-btn {
        position: fixed;
        bottom: 10px;
        left: 10px;
        padding: 10px 15px;
        background: rgba(220, 53, 69, 0.8);
        color: white;
        border: 1px solid rgba(255, 255, 255, 0.3);
        border-radius: 6px;
        font-size: 14px;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
        cursor: pointer;
        z-index: 9998;
        transition: all 0.3s ease;
        user-select: none;
        -webkit-user-select: none;
        touch-action: none;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      
      #copy-errors-btn:hover {
        background: rgba(220, 53, 69, 1);
        transform: translateY(-2px);
        box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
      }
      
      #copy-errors-btn:active {
        transform: translateY(0);
      }

      #copy-errors-btn.dragging {
        cursor: grabbing;
        transition: none;
        transform: none;
      }
      
      #copy-errors-btn.success {
        background: rgba(40, 167, 69, 0.8);
        animation: successPulse 0.3s ease;
      }
      
      #copy-errors-btn.success:hover {
        background: rgba(40, 167, 69, 1);
      }
      
      #error-badge {
        background: rgba(255, 255, 255, 0.9);
        color: #dc3545;
        padding: 2px 6px;
        border-radius: 10px;
        font-size: 11px;
        font-weight: bold;
        min-width: 18px;
        text-align: center;
        white-space: nowrap;
      }

      @keyframes successPulse {
        0%, 100% {
          transform: scale(1);
        }
        50% {
          transform: scale(1.05);
        }
      }
    `;document.head.appendChild(style);}
function createButton(){if(document.getElementById('copy-errors-btn')){return;}
const button=document.createElement('button');button.id='copy-errors-btn';button.title='发送修复指令到聊天框';button.innerHTML='🛠 修复错误';button.style.display='none';const badge=document.createElement('span');badge.id='error-badge';badge.style.display='none';badge.textContent='0';button.appendChild(badge);document.body.appendChild(button);}
injectStyles();const originalConsoleError=console.error;const errorLogs=[];const errorRepeatCounts=[];const errorIndexes=new Map();const seenErrors=new Set();const MAX_SEEN_ERRORS=2000;let errorCount=0;let duplicateCount=0;let omittedCount=0;const MAX_ERROR_LOGS=100;window.UrhoX=window.UrhoX||{};function formatVersionString(versionInfo){if(!versionInfo)return'Version: N/A';const binaryHash=versionInfo.binary_hash||versionInfo.binaryCrc||'N/A';const commitHash=versionInfo.commit_hash||versionInfo.commitHash||'N/A';const branch=versionInfo.branch||'N/A';return`Version: ${binaryHash} (${branch}@${commitHash})`;}
function formatReportTimestamp(){const now=new Date();return now.toISOString().replace('T',' ').substring(0,23);}
const MAX_REPORT_LENGTH=10000;function addErrorLog(errorMsg){const normalized=normalizeError(errorMsg);if(seenErrors.has(normalized)){duplicateCount++;const index=errorIndexes.get(normalized);if(index!==undefined){errorRepeatCounts[index]++;}else{omittedCount++;}
return false;}
if(seenErrors.size<MAX_SEEN_ERRORS){seenErrors.add(normalized);}
errorCount++;if(errorLogs.length<MAX_ERROR_LOGS){errorIndexes.set(normalized,errorLogs.length);errorLogs.push(errorMsg);errorRepeatCounts.push(0);}else{omittedCount++;}
return true;}
function normalizeError(message){let normalized=String(message);const engineTimestamp=/^\s*\[\d{4}-\d{2}-\d{2}(?:[T ][^\]]*|[ _]\d{2}[_:]\d{2}[_:]\d{2}[_.]\d{3})\]\s*/;if(!engineTimestamp.test(normalized))return normalized.replace(/\s+/g,' ').trim();normalized=normalized.replace(engineTimestamp,'').replace(/^\s*(?:\[(?:debug|info|warn(?:ing)?|error|fatal)\]|(?:debug|info|warn(?:ing)?|error|fatal):)\s*/i,'');if(engineTimestamp.test(normalized)){normalized=normalized.replace(engineTimestamp,'').replace(/^\s*\[\d+\]\s*/,'').replace(/^\s*(?:\[(?:debug|info|warn(?:ing)?|error|fatal)\]|(?:debug|info|warn(?:ing)?|error|fatal):)\s*/i,'');}
return normalized.replace(/\s+/g,' ').trim();}
function resetErrors(){errorLogs.length=0;errorRepeatCounts.length=0;errorIndexes.clear();seenErrors.clear();errorCount=0;duplicateCount=0;omittedCount=0;}
function formatErrorReport(){const versionInfo=window.UrhoX.getVersionInfo();const errorText=errorLogs.map((error,index)=>{const repeats=errorRepeatCounts[index];return repeats>0?`${error}\n... repeated ${repeats} additional times`:error;}).join('\n');const omittedInfo=omittedCount>0?` (${omittedCount} later errors omitted)`:'';const totalCount=errorCount+duplicateCount;const uniqueCount=seenErrors.size>=MAX_SEEN_ERRORS?`${MAX_SEEN_ERRORS}+`:errorCount;let report=`TapTap Maker - Error Report
Generated: ${formatReportTimestamp()}
${formatVersionString(versionInfo)}
Error Count: ${totalCount} total, ${uniqueCount} unique${omittedInfo}

${errorText}`;if(report.length>MAX_REPORT_LENGTH){const truncatedLength=report.length-MAX_REPORT_LENGTH;report=report.substring(0,MAX_REPORT_LENGTH)+`\n\n... (truncated ${truncatedLength} characters)`;}
return report;}
window.UrhoX.getErrors=function(options={}){const format=options.format||'pretty';let result;if(format==='json'){result={logs:[...errorLogs],repeatCounts:[...errorRepeatCounts],count:errorCount,duplicateCount:duplicateCount,omittedCount:omittedCount,timestamp:new Date().toISOString(),versionInfo:window.UrhoX.getVersionInfo(),browser:navigator.userAgent};}else{result=formatErrorReport();}
if(options.clear){resetErrors();const badge=document.getElementById('error-badge');if(badge)badge.style.display='none';}
return result;};window.UrhoX.clearErrors=function(){resetErrors();const badge=document.getElementById('error-badge');const button=document.getElementById('copy-errors-btn');if(badge)badge.style.display='none';if(button)button.style.display='none';};let copyErrorsCallback=null;window.UrhoX.onCopyErrors=function(callback){if(typeof callback==='function'){copyErrorsCallback=callback;}};function triggerCopyErrors(report){if(copyErrorsCallback){try{copyErrorsCallback(report);}catch(e){originalConsoleError('[UrhoX] Error in onCopyErrors callback:',e);}}}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',init);}else{init();}
function init(){createButton();const copyButton=document.getElementById('copy-errors-btn');const errorBadge=document.getElementById('error-badge');if(!copyButton||!errorBadge){originalConsoleError('Error capture UI elements not found');return;}
const BUTTON_POS_KEY='urhox-copy-errors-btn-pos';const BUTTON_MARGIN=10;const DRAG_THRESHOLD=10;const DRAG_DBLCLICK_GUARD_MS=600;let dragStartX=0;let dragStartY=0;let dragOriginLeft=0;let dragOriginTop=0;let desiredLeft=0;let desiredTop=0;let gestureStartDesiredLeft=0;let gestureStartDesiredTop=0;let hadCustomPosBeforeGesture=false;let activePointerId=null;let isDraggingButton=false;let suppressButtonClick=false;let lastDragEndAt=0;function clampButtonPos(left,top){const w=copyButton.offsetWidth||120;const h=copyButton.offsetHeight||40;const maxLeft=Math.max(BUTTON_MARGIN,window.innerWidth-w-BUTTON_MARGIN);const maxTop=Math.max(BUTTON_MARGIN,window.innerHeight-h-BUTTON_MARGIN);return{left:Math.min(Math.max(BUTTON_MARGIN,left),maxLeft),top:Math.min(Math.max(BUTTON_MARGIN,top),maxTop)};}
function applyButtonPos(left,top){desiredLeft=left;desiredTop=top;const pos=clampButtonPos(left,top);copyButton.style.left=pos.left+'px';copyButton.style.top=pos.top+'px';copyButton.style.right='auto';copyButton.style.bottom='auto';return pos;}
function hasCustomButtonPos(){return copyButton.style.top!==''&&copyButton.style.top!=='auto';}
function restoreButtonPos(){try{const raw=localStorage.getItem(BUTTON_POS_KEY);if(!raw)return;const parsed=JSON.parse(raw);if(typeof parsed.left==='number'&&typeof parsed.top==='number'){applyButtonPos(parsed.left,parsed.top);}}catch(e){}}
function saveButtonPos(pos){try{localStorage.setItem(BUTTON_POS_KEY,JSON.stringify(pos));}catch(e){}}
function reclampButtonPos(){if(!hasCustomButtonPos())return;if(copyButton.style.display==='none')return;const pos=clampButtonPos(desiredLeft,desiredTop);copyButton.style.left=pos.left+'px';copyButton.style.top=pos.top+'px';}
function onButtonPointerMove(e){if(e.pointerId!==activePointerId)return;const dx=e.clientX-dragStartX;const dy=e.clientY-dragStartY;if(!isDraggingButton&&(Math.abs(dx)>DRAG_THRESHOLD||Math.abs(dy)>DRAG_THRESHOLD)){isDraggingButton=true;suppressButtonClick=true;copyButton.classList.add('dragging');if(copyButton.setPointerCapture){try{copyButton.setPointerCapture(e.pointerId);}catch(err){}}}
if(isDraggingButton){e.preventDefault();const pos=clampButtonPos(dragOriginLeft+dx,dragOriginTop+dy);applyButtonPos(pos.left,pos.top);}}
function endButtonGesture(e,cancelled){if(e.pointerId!==activePointerId)return;activePointerId=null;document.removeEventListener('pointermove',onButtonPointerMove);document.removeEventListener('pointerup',onButtonPointerUp);document.removeEventListener('pointercancel',onButtonPointerCancel);if(e.pointerId!==undefined&&copyButton.hasPointerCapture&&copyButton.hasPointerCapture(e.pointerId)){try{copyButton.releasePointerCapture(e.pointerId);}catch(err){}}
copyButton.classList.remove('dragging');const wasDragging=isDraggingButton;isDraggingButton=false;if(!wasDragging)return;lastDragEndAt=Date.now();if(cancelled){if(hadCustomPosBeforeGesture){applyButtonPos(gestureStartDesiredLeft,gestureStartDesiredTop);}else{copyButton.style.left='';copyButton.style.top='';copyButton.style.right='';copyButton.style.bottom='';desiredLeft=0;desiredTop=0;}}else{saveButtonPos({left:desiredLeft,top:desiredTop});}
setTimeout(function(){suppressButtonClick=false;},50);}
function onButtonPointerUp(e){endButtonGesture(e,false);}
function onButtonPointerCancel(e){endButtonGesture(e,true);}
restoreButtonPos();copyButton.addEventListener('pointerdown',function(e){if(e.button!==undefined&&e.button!==0)return;if(activePointerId!==null)return;const rect=copyButton.getBoundingClientRect();dragStartX=e.clientX;dragStartY=e.clientY;dragOriginLeft=rect.left;dragOriginTop=rect.top;hadCustomPosBeforeGesture=hasCustomButtonPos();gestureStartDesiredLeft=desiredLeft;gestureStartDesiredTop=desiredTop;activePointerId=e.pointerId;isDraggingButton=false;document.addEventListener('pointermove',onButtonPointerMove);document.addEventListener('pointerup',onButtonPointerUp);document.addEventListener('pointercancel',onButtonPointerCancel);});copyButton.addEventListener('click',function(e){if(!suppressButtonClick)return;e.preventDefault();e.stopImmediatePropagation();suppressButtonClick=false;},true);copyButton.addEventListener('dblclick',function(e){if(lastDragEndAt===0||Date.now()-lastDragEndAt>=DRAG_DBLCLICK_GUARD_MS)return;e.preventDefault();e.stopImmediatePropagation();},true);window.addEventListener('resize',reclampButtonPos);function updateErrorBadge(){if(errorCount>0){copyButton.style.display='flex';const totalCount=errorCount+duplicateCount;const nextBadgeText=totalCount>99?'99+':String(totalCount);const widthMayChange=errorBadge.style.display==='none'||errorBadge.textContent!==nextBadgeText;errorBadge.textContent=nextBadgeText;errorBadge.style.display='inline-block';if(widthMayChange)reclampButtonPos();}else{copyButton.style.display='none';errorBadge.style.display='none';}}
function formatTimestamp(){const now=new Date();return now.toISOString().replace('T',' ').substring(0,23);}
function formatError(type,args){const timestamp=formatTimestamp();const message=Array.from(args).map(arg=>{if(typeof arg==='object'){try{return JSON.stringify(arg,null,2);}catch(e){return String(arg);}}
return String(arg);}).join(' ');return`[${timestamp}] [${type.toUpperCase()}] ${message}`;}
const ERROR_BLACKLIST_RE=/SecurityError|NotAllowedError|AbortError|QuotaExceededError|ResizeObserver loop/i;function isBlacklisted(message){return ERROR_BLACKLIST_RE.test(message);}
console.error=function(...args){const message=args.map(a=>String(a)).join(' ');if(!isBlacklisted(message)){const errorMsg=formatError('error',args);addErrorLog(errorMsg);updateErrorBadge();}
originalConsoleError.apply(console,args);};window.addEventListener('error',function(event){const message=event.message||'';if(isBlacklisted(message))return;const errorMsg=formatError('error',[`${event.message}\n  at ${event.filename}:${event.lineno}:${event.colno}`,event.error?.stack||'']);addErrorLog(errorMsg);updateErrorBadge();});window.addEventListener('unhandledrejection',function(event){const message=String(event.reason||'');if(isBlacklisted(message))return;const errorMsg=formatError('rejection',[`${event.reason}`,event.reason?.stack||'']);addErrorLog(errorMsg);updateErrorBadge();});function copyErrorsToClipboard(){if(errorLogs.length===0){alert('当前没有错误信息\nNo errors to fix');return;}
const fullReport=formatErrorReport();const prompt=`请修复游戏中的以下错误。请定位根因并修改代码，完成后验证游戏不再报错。\n\n${fullReport}`;if(copyErrorsCallback){showCopyFeedback('✓ 已发送',prompt,true);}
void copyToClipboardFallback(prompt,!copyErrorsCallback).then(function(ok){if(!ok&&copyErrorsCallback){showCopyFeedback('✗ 复制失败',null,false);}});}
function copyWithExecCommand(text){const textarea=document.createElement('textarea');textarea.value=text;textarea.setAttribute('readonly','');textarea.style.cssText='position:fixed;left:-999999px;top:0';document.body.appendChild(textarea);textarea.focus();textarea.setSelectionRange(0,textarea.value.length);textarea.select();try{if(!document.execCommand('copy'))throw new Error('execCommand failed');}finally{textarea.remove();}}
async function copyToClipboardFallback(text,showCopiedFeedback){try{if(navigator.clipboard?.writeText){try{await navigator.clipboard.writeText(text);}catch(err){copyWithExecCommand(text);}}else{copyWithExecCommand(text);}
if(showCopiedFeedback){showCopyFeedback('✓ 已复制',null,true);}
return true;}catch(err){originalConsoleError('复制失败 / Copy failed:',err);if(showCopiedFeedback){alert('复制失败，请检查浏览器权限\nFailed to copy repair prompt');}
return false;}}
const copyButtonDefaultLabel='🛠 修复错误';let copyButtonResetTimer=0;function setCopyButtonLabel(label){copyButton.textContent=label;copyButton.appendChild(errorBadge);}
function showCopyFeedback(label,report,ok){clearTimeout(copyButtonResetTimer);copyButton.classList.toggle('success',!!ok);setCopyButtonLabel(label);if(report)triggerCopyErrors(report);copyButtonResetTimer=setTimeout(()=>{copyButton.classList.remove('success');setCopyButtonLabel(copyButtonDefaultLabel);},2000);}
copyButton.addEventListener('click',copyErrorsToClipboard);copyButton.addEventListener('dblclick',function(e){e.preventDefault();if(confirm('确定要清空错误日志吗？\nClear all error logs?')){resetErrors();updateErrorBadge();log('错误日志已清空 / Error logs cleared');}});log('✓ 错误捕获系统已启动');log('  - 单击按钮：发送修复指令');log('  - 拖动按钮：移位');log('  - 双击按钮：清空日志');}})();(function(){var whitelist=['d7b48456-b1c4-44fa-9025-c4ffb591bed8','.ipv.taptap-code.org'];var url=location.href;var whitelisted=whitelist.some(function(id){return url.indexOf(id)!==-1;});if(window.UrhoX&&window.UrhoX.isPublishGame)return;if(window.UrhoX&&window.UrhoX.isEmbed)return;if(whitelisted){(window.WASM_PLAYER_CONFIG=window.WASM_PLAYER_CONFIG||{}).verbose=true;}else{if(window.isInTapFrame)return;}
var verbose=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function onErudaReady(){if(!verbose)return;console.log('[Eruda] UA:',navigator.userAgent);var hasMR=typeof MediaRecorder!=='undefined';console.log('[Eruda] MediaRecorder:',hasMR,'| mp4:',hasMR&&MediaRecorder.isTypeSupported('video/mp4'),'| webm:',hasMR&&MediaRecorder.isTypeSupported('video/webm'));console.log('[Eruda] AudioContext:',typeof AudioContext!=='undefined','| AudioNode:',typeof AudioNode!=='undefined');console.log('[Eruda] canvasRecorder:',!!window.canvasRecorder);}
var s=document.createElement('script');s.src='https://tapcode-sce.spark.xd.com/src/web/libs/eruda.min.js';s.onload=function(){if(typeof eruda!=='undefined'&&eruda){eruda.init();onErudaReady();}};document.body.appendChild(s);})();(function(){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[UrhoX Bridge]',...args);}
var registeredHandlers={};function isValidOrigin(origin){if(!origin)return false;var originLower=origin.toLowerCase();var allowedKeywords=['taptap','lishu','fuping','tapcode','urhox','localhost','crystal.agnt.xd'];return allowedKeywords.some(function(keyword){return originLower.includes(keyword);});}
function registerHandler(type,handler,options){options=options||{};registeredHandlers[type]={handler:handler,validateOrigin:!!options.validateOrigin};log('Handler registered:',type);}
function unregisterHandler(type){if(registeredHandlers[type]){delete registeredHandlers[type];log('Handler unregistered:',type);}}
function postToParent(type,data){try{if(window.isInTapFrame){window.parent.postMessage({type:type,data:data},'*');log('Posted to parent:',type);}}catch(e){}}
window.UrhoXBridge={registerHandler:registerHandler,unregisterHandler:unregisterHandler,postToParent:postToParent,isValidOrigin:isValidOrigin};if(!window.isInTapFrame){log('Not in iframe, message listener skipped');return;}
function captureCanvasScreenshot(){try{var canvas=document.getElementById('canvas');if(!canvas){return{success:false,error:'Canvas element not found'};}
if(canvas.width===0||canvas.height===0){return{success:false,error:'Canvas has no valid size'};}
var dataUrl=canvas.toDataURL('image/png');if(!dataUrl||dataUrl==='data:,'){return{success:false,error:'Failed to export canvas: empty result'};}
return{success:true,data:dataUrl};}catch(error){log('Screenshot capture failed:',error);return{success:false,error:error.message||'Unknown error during capture'};}}
window.addEventListener('message',function(event){if(event.source!==window.parent)return;const{type,id,data:requestData}=event.data||{};if(typeof type!=='string'||!type)return;log('Received:',type,requestData);function reply(data){event.source.postMessage({type:type+'.response',id,data},event.origin);}
var registered=registeredHandlers[type];if(registered){if(registered.validateOrigin&&!isValidOrigin(event.origin)){console.warn('[UrhoX Bridge] Request rejected: invalid origin',type,event.origin);return;}
try{registered.handler(requestData,event);}catch(e){console.error('[UrhoX Bridge] Handler error:',type,e);}
return;}
switch(type){case'UrhoX.getErrors':case'getErrors':reply(window.UrhoX?.getErrors(requestData));break;case'screenshot-request':if(!isValidOrigin(event.origin)){console.warn('[UrhoX Bridge] Screenshot request rejected: invalid origin',event.origin);return;}
requestAnimationFrame(function(){var result=captureCanvasScreenshot();event.source.postMessage({type:'screenshot-response',success:result.success,data:result.data,error:result.error},event.origin);log('Screenshot response sent, success:',result.success);});break;default:var responseType=type.replace(/-request.*$/,'-response');if(responseType===type)return;log('Unhandled message type:',type);try{event.source.postMessage({type:responseType,success:false,error:type+' is not supported by this user agent'},event.origin);}catch(e){}
break;}});setTimeout(()=>{window.UrhoX?.onReady?.(function(result){window.parent.postMessage({type:'UrhoX.onReady',data:result},'*');});window.UrhoX?.onCopyErrors?.(function(report){window.parent.postMessage({type:'UrhoX.onCopyErrors',data:report},'*');});},0);log('initialized (in iframe)');})();(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(){if(VERBOSE)console.log.apply(console,['[Capsule]'].concat([].slice.call(arguments)));}
var userCfg=(window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.capsule)||{};var CFG={visible:userCfg.visible===true,widthCss:userCfg.widthCss||83,heightCss:userCfg.heightCss||34,offsetTopCss:userCfg.offsetTopCss||28,offsetRightCss:userCfg.offsetRightCss||12,imageUrl:userCfg.imageUrl||null};var STYLE_ID='urhox-capsule-styles';var EL_ID='urhox-capsule-simulator';function resolveImageUrl(){if(CFG.imageUrl)return CFG.imageUrl;var logo=document.getElementById('watermark-logo');if(logo&&logo.src){return logo.src.replace(/Logo\.png(\?.*)?$/,'capsule.png');}
return'src/capsule.png';}
function injectStyles(imageUrl){if(document.getElementById(STYLE_ID))return;var style=document.createElement('style');style.id=STYLE_ID;style.textContent='#'+EL_ID+'{'+'position:fixed;'+'top:'+CFG.offsetTopCss+'px;'+'right:'+CFG.offsetRightCss+'px;'+'width:'+CFG.widthCss+'px;'+'height:'+CFG.heightCss+'px;'+'background-image:url("'+imageUrl+'");'+'background-size:100% 100%;'+'background-repeat:no-repeat;'+'pointer-events:none;user-select:none;'+'z-index:9997;'+'}'+'#'+EL_ID+'.hidden{display:none;}';document.head.appendChild(style);}
function createElement(){var el=document.createElement('div');el.id=EL_ID;el.setAttribute('aria-hidden','true');if(!CFG.visible)el.classList.add('hidden');document.body.appendChild(el);return el;}
var capsuleEl=null;var cachedJson='';var cacheDirty=true;function ensureMounted(){if(capsuleEl&&document.body.contains(capsuleEl))return;injectStyles(resolveImageUrl());capsuleEl=createElement();cacheDirty=true;}
function recompute(){if(!capsuleEl){cachedJson='';return;}
var canvas=document.getElementById('canvas')||document.querySelector('canvas');var dpr=window.devicePixelRatio||1;var winW=canvas?canvas.width:window.innerWidth*dpr;var winH=canvas?canvas.height:window.innerHeight*dpr;if(winW<=0||winH<=0){cachedJson='';return;}
var left=(winW-CFG.offsetRightCss*dpr)-CFG.widthCss*dpr;var top=CFG.offsetTopCss*dpr;var right=winW-CFG.offsetRightCss*dpr;var bottom=top+CFG.heightCss*dpr;function n(v){return Math.floor(v*10000)/10000;}
var obj={left:n(left/winW),top:n(top/winH),right:n(right/winW),bottom:n(bottom/winH)};cachedJson=JSON.stringify(obj);cacheDirty=false;log('rect updated',cachedJson);}
function invalidate(){cacheDirty=true;}
window.UrhoX=window.UrhoX||{};window.UrhoX.getNativeExitMenuRect=function(){if(!capsuleEl)return'';if(capsuleEl.classList.contains('hidden'))return'';if(cacheDirty)recompute();return cachedJson;};window.UrhoX.setNativeExitMenuVisible=function(visible){ensureMounted();if(!capsuleEl)return;if(visible){capsuleEl.classList.remove('hidden');invalidate();}else{capsuleEl.classList.add('hidden');}
log('visibility set to',!!visible);};function registerBridgeHandler(){if(!window.UrhoXBridge||!window.UrhoXBridge.registerHandler)return false;window.UrhoXBridge.registerHandler('capsule-menu-set-visible',function(data){var v=data&&typeof data.visible!=='undefined'?!!data.visible:true;window.UrhoX.setNativeExitMenuVisible(v);},{validateOrigin:true});log('postMessage handler registered');return true;}
function init(){ensureMounted();recompute();window.addEventListener('resize',invalidate,{passive:true});window.addEventListener('orientationchange',invalidate,{passive:true});if(window.visualViewport){window.visualViewport.addEventListener('resize',invalidate,{passive:true});}
if(!registerBridgeHandler()){setTimeout(registerBridgeHandler,0);}}
if(document.body){init();}else{document.addEventListener('DOMContentLoaded',init,{once:true});}})(window);(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;var RECORDING_CONFIG=(window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.recording)||{};function getBitrateForResolution(width,height,fps){var bpp=0.1;var raw=width*height*fps*bpp;return Math.max(1000000,Math.min(24000000,Math.round(raw)));}
var MIN_SHORT_SIDE=540;var MAX_SHORT_SIDE=1440;var MP4_MUXER_CDN='https://tapcode-sce.spark.xd.com/src/web/libs/mp4-muxer.mjs';var _webCodecsReady=false;function _loadMp4Muxer(){if(window._Mp4Muxer){_webCodecsReady=true;return Promise.resolve();}
if(typeof VideoEncoder==='undefined')return Promise.resolve();return import(MP4_MUXER_CDN).then(function(mod){window._Mp4Muxer=mod;_webCodecsReady=true;log('mp4-muxer loaded (WebCodecs path ready)');}).catch(function(e){logWarn('mp4-muxer load failed, WebCodecs path unavailable:',e.message);});}
var CONFIG={enabled:RECORDING_CONFIG.enabled!==false,uploadUrl:RECORDING_CONFIG.uploadUrl||null,maxDuration:RECORDING_CONFIG.maxDuration||90000,fps:RECORDING_CONFIG.fps||60,videoBitsPerSecond:RECORDING_CONFIG.videoBitsPerSecond||null,audioBitsPerSecond:RECORDING_CONFIG.audioBitsPerSecond||128000};function log(...args){if(VERBOSE)console.log('[CanvasRecorder]',...args);}
function logWarn(...args){console.warn('[CanvasRecorder]',...args);}
function logError(...args){console.error('[CanvasRecorder]',...args);}
function getSupportedMimeType(){if(!window.MediaRecorder)return null;var preferred='video/mp4;codecs="avc1.42E01E,mp4a.40.2"';if(MediaRecorder.isTypeSupported(preferred))return preferred;var fallback1='video/mp4;codecs="avc1,mp4a"';if(MediaRecorder.isTypeSupported(fallback1))return fallback1;if(MediaRecorder.isTypeSupported('video/mp4')){logWarn('H.264+AAC not supported, falling back to video/mp4 (may use Opus)');return'video/mp4';}
return null;}
function formatTime(ms){var totalSeconds=Math.floor(ms/1000);var minutes=Math.floor(totalSeconds/60);var seconds=totalSeconds%60;return String(minutes).padStart(2,'0')+':'+String(seconds).padStart(2,'0');}
function generateFileName(){var uuid='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,function(c){var r=Math.random()*16|0;return(c==='x'?r:(r&0x3|0x8)).toString(16);});return'rec_'+uuid+'.mp4';}
var _audioCapture={sourceNodes:new Set(),streamDest:null,patched:false,_origConnect:null,_origDisconnect:null,};(function _patchAudioNodes(){if(typeof AudioNode==='undefined')return;var origConnect=AudioNode.prototype.connect;var origDisconnect=AudioNode.prototype.disconnect;_audioCapture._origConnect=origConnect;_audioCapture._origDisconnect=origDisconnect;_audioCapture.patched=true;AudioNode.prototype.connect=function(dest){var result=origConnect.apply(this,arguments);if(typeof AudioDestinationNode!=='undefined'&&dest instanceof AudioDestinationNode){_audioCapture.sourceNodes.add(this);if(typeof AudioBufferSourceNode!=='undefined'&&this instanceof AudioBufferSourceNode){var self=this;this.addEventListener('ended',function(){_audioCapture.sourceNodes.delete(self);});}
if(_audioCapture.streamDest){try{origConnect.call(this,_audioCapture.streamDest);}catch(e){}}}
return result;};AudioNode.prototype.disconnect=function(){origDisconnect.apply(this,arguments);if(arguments.length===0){_audioCapture.sourceNodes.delete(this);}else if(typeof AudioDestinationNode!=='undefined'&&arguments[0]instanceof AudioDestinationNode){_audioCapture.sourceNodes.delete(this);}};})();function _startAudioCapture(){var ctx=(typeof Module!=='undefined'&&Module.SDL2&&Module.SDL2.audioContext)||null;if(!ctx){log('AudioContext not found, recording without audio');return null;}
if(!_audioCapture.patched){logWarn('AudioNode patch not installed, recording without audio');return null;}
try{if(ctx.state==='suspended'){ctx.resume().then(function(){log('AudioContext resumed');});}
var streamDest=ctx.createMediaStreamDestination();_audioCapture.streamDest=streamDest;var origConnect=_audioCapture._origConnect;var count=0;_audioCapture.sourceNodes.forEach(function(node){try{origConnect.call(node,streamDest);count++;}catch(e){}});log('Audio capture started,',count,'source node(s) connected');return streamDest.stream;}catch(e){logWarn('Audio capture setup failed:',e);_audioCapture.streamDest=null;return null;}}
function _stopAudioCapture(){var streamDest=_audioCapture.streamDest;if(!streamDest)return;_audioCapture.streamDest=null;var origDisconnect=_audioCapture._origDisconnect;_audioCapture.sourceNodes.forEach(function(node){try{if(origDisconnect){origDisconnect.call(node,streamDest);}else{node.disconnect(streamDest);}}catch(e){}});log('Audio capture stopped');}
function injectStyles(){var styleId='canvas-recorder-styles';if(document.getElementById(styleId))return;var style=document.createElement('style');style.id=styleId;style.textContent=`
      /* 录制状态容器 */
      #canvas-recorder-status {
        position: fixed;
        top: 16px;
        left: 80px;
        background: rgba(0, 0, 0, 0.75);
        border: 1px solid rgba(255, 255, 255, 0.2);
        border-radius: 20px;
        padding: 6px 12px;
        display: flex;
        align-items: center;
        gap: 8px;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', sans-serif;
        font-size: 14px;
        color: #fff;
        z-index: 99997;
        opacity: 0;
        transform: translateY(-10px);
        transition: opacity 0.3s ease, transform 0.3s ease;
        pointer-events: none;
        user-select: none;
      }

      #canvas-recorder-status.visible {
        opacity: 1;
        transform: translateY(0);
        pointer-events: auto;
      }

      /* 停止按钮（红色方块，闪烁） */
      @keyframes recorder-blink {
        0%, 59% { visibility: visible; }
        60%, 99% { visibility: hidden; }
      }

      .recorder-dot {
        width: 10px;
        height: 10px;
        background: #ff4444;
        border-radius: 2px;
        flex-shrink: 0;
        animation: recorder-blink 1.2s step-end infinite;
      }

      #canvas-recorder-status:hover .recorder-dot {
        background: #ff6666;
      }

      #canvas-recorder-status:active .recorder-dot {
        background: #cc2222;
      }

      /* 时间显示 */
      .recorder-time {
        font-variant-numeric: tabular-nums;
        min-width: 70px;
        transition: opacity 0.25s ease;
      }

      /* 上传文字叠加层 — 居中覆盖在 dot+time 之上 */
      .recorder-overlay {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        opacity: 0;
        transition: opacity 0.25s ease;
        pointer-events: none;
      }

      .recorder-overlay.active {
        opacity: 1;
      }

      /* 状态栏传输失败闪红 */
      #canvas-recorder-status.error {
        border-color: rgba(255, 68, 68, 0.5);
      }
    `;document.head.appendChild(style);}
class CanvasRecorder{constructor(){this.mediaRecorder=null;this.chunks=[];this.isRecording=false;this.uploadAfter=false;this.startTime=0;this.maxDuration=CONFIG.maxDuration;this.timerInterval=null;this.autoStopTimeout=null;this.statusEl=null;this._pendingRequest=null;this._currentXhr=null;this._isUploading=false;this._sessionId=0;this._init();}
_init(){if(!CONFIG.enabled){log('Recording disabled by config');return;}
if(!window.MediaRecorder){logWarn('MediaRecorder not supported');return;}
var mimeType=getSupportedMimeType();if(!mimeType){logWarn('video/mp4 not supported by MediaRecorder');return;}
injectStyles();this._createStatusUI();this._setupPostMessageListener();this._registerToFAB();this._registerUploadCallback();_loadMp4Muxer();log('Initialized, MIME type:',mimeType);}
_createStatusUI(){if(this.statusEl)return;this.statusEl=document.createElement('div');this.statusEl.id='canvas-recorder-status';this.statusEl.innerHTML=`
        <span class="recorder-dot"></span>
        <span class="recorder-time">00:00 / 01:00</span>
        <span class="recorder-overlay"></span>
      `;this.statusEl.addEventListener('click',()=>{if(this.isRecording){log('Stop via status bar click');this.stop();}else if(this._isUploading){log('Cancel upload via status bar click');this.cancelUpload();}});document.body.appendChild(this.statusEl);}
_showStatus(){if(this.statusEl){this.statusEl.style.cursor='pointer';this.statusEl.classList.add('visible');}}
_hideStatus(){if(this.statusEl){this.statusEl.classList.remove('visible');}}
_updateTimer(){if(!this.statusEl)return;var elapsed=Date.now()-this.startTime;var maxFormatted=formatTime(this.maxDuration);var elapsedFormatted=formatTime(Math.min(elapsed,this.maxDuration));var timeEl=this.statusEl.querySelector('.recorder-time');if(timeEl){timeEl.textContent=elapsedFormatted+' / '+maxFormatted;}}
_showOverlay(text){if(!this.statusEl)return;var dotEl=this.statusEl.querySelector('.recorder-dot');var timeEl=this.statusEl.querySelector('.recorder-time');var overlay=this.statusEl.querySelector('.recorder-overlay');if(dotEl){dotEl.style.opacity='0';dotEl.style.animation='none';}
if(timeEl)timeEl.style.opacity='0';if(overlay){overlay.textContent=text;overlay.classList.add('active');}
this.statusEl.style.cursor='default';this.statusEl.style.pointerEvents='none';this.statusEl.classList.remove('error');this.statusEl.classList.add('visible');}
_hideOverlay(){if(!this.statusEl)return;var dotEl=this.statusEl.querySelector('.recorder-dot');var timeEl=this.statusEl.querySelector('.recorder-time');var overlay=this.statusEl.querySelector('.recorder-overlay');if(dotEl){dotEl.style.opacity='';dotEl.style.animation='';}
if(timeEl)timeEl.style.opacity='';if(overlay){overlay.classList.remove('active');overlay.textContent='';}}
_showUploadProgress(){this._showOverlay('传输中');if(this.statusEl){this.statusEl.style.cursor='pointer';this.statusEl.style.pointerEvents='auto';}}
_showUploadComplete(){this._showOverlay('传输成功');this._autoHideTimerId&&clearTimeout(this._autoHideTimerId);this._autoHideTimerId=setTimeout(()=>{this._autoHideTimerId=null;this._resetStatusBar();},1000);}
_showUploadError(message){this._showOverlay(message||'传输失败');this.statusEl.classList.add('error');this._autoHideTimerId&&clearTimeout(this._autoHideTimerId);this._autoHideTimerId=setTimeout(()=>{this._autoHideTimerId=null;this._resetStatusBar();},3000);}
_resetStatusBar(){if(!this.statusEl)return;this.statusEl.classList.remove('visible','error');this.statusEl.style.cursor='';this.statusEl.style.pointerEvents='';this._resetTimerId&&clearTimeout(this._resetTimerId);this._resetTimerId=setTimeout(()=>{this._resetTimerId=null;this._hideOverlay();if(this.isRecording)return;var timeEl=this.statusEl.querySelector('.recorder-time');if(timeEl)timeEl.textContent='00:00 / 01:00';},350);}
_prepareForRecording(){this._resetTimerId&&clearTimeout(this._resetTimerId);this._resetTimerId=null;this._autoHideTimerId&&clearTimeout(this._autoHideTimerId);this._autoHideTimerId=null;if(!this.statusEl)return;this.statusEl.classList.remove('error');this.statusEl.style.cursor='';this.statusEl.style.pointerEvents='';this._hideOverlay();}
start(options){options=options||{};log('start() called, options:',JSON.stringify(options));if(this.isRecording){log('Interrupting current recording for new one');this.cancel();}
this._prepareForRecording();var canvas=document.getElementById('canvas');if(!canvas){logError('Canvas element not found');return false;}
var srcW=canvas.width;var srcH=canvas.height;var shortSide=Math.min(srcW,srcH);var dpr=window.devicePixelRatio||1;var recordCanvas=canvas;this._upscaleCanvas=null;this._upscaleCtx=null;if(shortSide<MIN_SHORT_SIDE){var scale=MIN_SHORT_SIDE/shortSide;var dstW=Math.round(srcW*scale);var dstH=Math.round(srcH*scale);var offscreen=document.createElement('canvas');offscreen.width=dstW;offscreen.height=dstH;var ctx=offscreen.getContext('2d');ctx.globalCompositeOperation='copy';this._upscaleCanvas=offscreen;this._upscaleCtx=ctx;recordCanvas=offscreen;log('Upscaling:',srcW+'x'+srcH,'->',dstW+'x'+dstH);}else if(shortSide>MAX_SHORT_SIDE){var scale=MAX_SHORT_SIDE/shortSide;var dstW=Math.round(srcW*scale);var dstH=Math.round(srcH*scale);var offscreen=document.createElement('canvas');offscreen.width=dstW;offscreen.height=dstH;var ctx=offscreen.getContext('2d');ctx.globalCompositeOperation='copy';ctx.imageSmoothingQuality='high';this._upscaleCanvas=offscreen;this._upscaleCtx=ctx;recordCanvas=offscreen;log('Downscaling:',srcW+'x'+srcH,'->',dstW+'x'+dstH);}
this.uploadAfter=!!options.uploadAfter;this.maxDuration=options.maxDuration||CONFIG.maxDuration;this._useWebCodecs=_webCodecsReady;if(this._useWebCodecs){return this._startWebCodecs(canvas,recordCanvas);}else{return this._startMediaRecorder(canvas,recordCanvas);}}
_startWebCodecs(sourceCanvas,recordCanvas){try{var recW=recordCanvas.width;var recH=recordCanvas.height;recW=recW%2===0?recW:recW-1;recH=recH%2===0?recH:recH-1;if(this._upscaleCanvas){this._upscaleCanvas.width=recW;this._upscaleCanvas.height=recH;this._upscaleCtx.globalCompositeOperation='copy';this._upscaleCtx.imageSmoothingQuality='high';}else if(recW!==recordCanvas.width||recH!==recordCanvas.height){var offscreen=document.createElement('canvas');offscreen.width=recW;offscreen.height=recH;var ctx=offscreen.getContext('2d');ctx.globalCompositeOperation='copy';this._upscaleCanvas=offscreen;this._upscaleCtx=ctx;recordCanvas=offscreen;}
var fps=CONFIG.fps;var bitrate=CONFIG.videoBitsPerSecond||getBitrateForResolution(recW,recH,fps);log('WebCodecs recording:',recW+'x'+recH,'@'+fps+'fps',bitrate+'bps');var Mp4Muxer=window._Mp4Muxer;var muxerTarget=new Mp4Muxer.ArrayBufferTarget();var muxerOpts={target:muxerTarget,video:{codec:'avc',width:recW,height:recH},fastStart:'in-memory'};var audioStream=_startAudioCapture();var audioCtx=(typeof Module!=='undefined'&&Module.SDL2&&Module.SDL2.audioContext)||null;if(audioStream&&audioCtx&&audioStream.getAudioTracks().length>0){muxerOpts.audio={codec:'aac',sampleRate:audioCtx.sampleRate,numberOfChannels:audioStream.getAudioTracks()[0].getSettings().channelCount||2};}
this._wc={};muxerOpts.firstTimestampBehavior='offset';this._wc.muxer=new Mp4Muxer.Muxer(muxerOpts);this._wc.muxerTarget=muxerTarget;var muxer=this._wc.muxer;this._wc.videoEncoder=new VideoEncoder({output:(chunk,meta)=>{muxer.addVideoChunk(chunk,meta);},error:(e)=>{logError('VideoEncoder error:',e);this.cancel();}});this._wc.videoEncoder.configure({codec:'avc1.42003d',width:recW,height:recH,bitrate:bitrate,framerate:fps,latencyMode:'quality',avc:{format:'avc'}});this._wc.audioEncoder=null;this._wc.audioReader=null;if(muxerOpts.audio&&typeof MediaStreamTrackProcessor!=='undefined'){this._wc.audioEncoder=new AudioEncoder({output:(chunk,meta)=>{muxer.addAudioChunk(chunk,meta);},error:(e)=>{logWarn('AudioEncoder error:',e);}});this._wc.audioEncoder.configure({codec:'mp4a.40.2',sampleRate:muxerOpts.audio.sampleRate,numberOfChannels:muxerOpts.audio.numberOfChannels,bitrate:CONFIG.audioBitsPerSecond});var audioTrack=audioStream.getAudioTracks()[0];var processor=new MediaStreamTrackProcessor({track:audioTrack});this._wc.audioReader=processor.readable.getReader();this._wc.audioReading=true;this._wcPumpAudio();}
this._wc.frameIndex=0;this._wc.fps=fps;this._wc.sourceCanvas=sourceCanvas;this._wc.recordCanvas=recordCanvas;this.startTime=Date.now();this.isRecording=true;var session=++this._sessionId;this._onContextLost=()=>{logError('WebGL context lost');this.cancel();};sourceCanvas.addEventListener('webglcontextlost',this._onContextLost);this._wcStartFramePump();this._startRecordingUI();log('WebCodecs recording started');return true;}catch(error){var savedUpscaleCanvas=this._upscaleCanvas;var savedUpscaleCtx=this._upscaleCtx;this._wcCleanup();this._upscaleCanvas=savedUpscaleCanvas;this._upscaleCtx=savedUpscaleCtx;logError('WebCodecs start failed, falling back to MediaRecorder:',error);this._useWebCodecs=false;return this._startMediaRecorder(sourceCanvas,this._upscaleCanvas||sourceCanvas);}}
_wcStartFramePump(){var fps=this._wc.fps;var frameDurationUs=1000000/fps;var keyframeInterval=fps*2;var pump=()=>{if(!this.isRecording||!this._wc)return;var elapsed=(Date.now()-this.startTime)*1000;var idealTs=this._wc.frameIndex*frameDurationUs;if(elapsed>=idealTs){if(this._wc.videoEncoder.encodeQueueSize>5){this._wc.frameIndex++;this._wc.framePumpId=requestAnimationFrame(pump);return;}
if(this._upscaleCanvas&&this._upscaleCtx){this._upscaleCtx.drawImage(this._wc.sourceCanvas,0,0,this._upscaleCanvas.width,this._upscaleCanvas.height);}
var frame=new VideoFrame(this._wc.recordCanvas,{timestamp:Math.round(idealTs),duration:Math.round(frameDurationUs)});this._wc.videoEncoder.encode(frame,{keyFrame:this._wc.frameIndex%keyframeInterval===0});frame.close();this._wc.frameIndex++;}
this._wc.framePumpId=requestAnimationFrame(pump);};this._wc.framePumpId=requestAnimationFrame(pump);}
async _wcPumpAudio(){while(this._wc&&this._wc.audioReading&&this._wc.audioReader){try{var result=await this._wc.audioReader.read();if(result.done)break;var audioData=result.value;try{if(this._wc&&this._wc.audioEncoder&&this._wc.audioEncoder.state==='configured'){this._wc.audioEncoder.encode(audioData);}}finally{audioData.close();}}catch(e){break;}}}
_wcStopCapture(){if(!this._wc)return;if(this._wc.framePumpId){cancelAnimationFrame(this._wc.framePumpId);this._wc.framePumpId=null;}
if(this._wc.audioReader){this._wc.audioReading=false;this._wc.audioReader.cancel().catch(()=>{});}
this._upscaleCanvas=null;this._upscaleCtx=null;if(this._onContextLost){var canvas=document.getElementById('canvas');if(canvas)canvas.removeEventListener('webglcontextlost',this._onContextLost);this._onContextLost=null;}
_stopAudioCapture();}
_wcCleanup(){this._wcStopCapture();if(!this._wc)return;if(this._wc.videoEncoder&&this._wc.videoEncoder.state!=='closed'){try{this._wc.videoEncoder.close();}catch(e){}}
if(this._wc.audioEncoder&&this._wc.audioEncoder.state!=='closed'){try{this._wc.audioEncoder.close();}catch(e){}}
this._wc=null;}
async _wcFinalize(session){if(session!==this._sessionId||!this._wc)return;var wc=this._wc;try{if(wc.videoEncoder&&wc.videoEncoder.state==='configured')
await wc.videoEncoder.flush();if(wc.audioEncoder&&wc.audioEncoder.state==='configured')
await wc.audioEncoder.flush();}catch(e){logWarn('Encoder flush error:',e);}
if(wc.videoEncoder&&wc.videoEncoder.state!=='closed')wc.videoEncoder.close();if(wc.audioEncoder&&wc.audioEncoder.state!=='closed')wc.audioEncoder.close();if(session!==this._sessionId)return;var buffer=null;try{wc.muxer.finalize();buffer=wc.muxerTarget.buffer;}catch(e){logError('Muxer finalize failed:',e);}
this._wc=null;this._hideStatus();this._updateFABIcon(false);if(!buffer||buffer.byteLength===0){logError('Encoding produced empty output');return;}
var duration=Date.now()-this.startTime;log('WebCodecs encoding done, duration:',duration,'size:',buffer.byteLength);if(this.uploadAfter){await this._uploadAndNotify(buffer,duration,session);}else{this._downloadBlob(new Blob([buffer],{type:'video/mp4'}));}}
_startMediaRecorder(sourceCanvas,recordCanvas){var mimeType=getSupportedMimeType();if(!mimeType){logError('No supported MIME type');return false;}
log('MediaRecorder path, MIME:',mimeType);try{if(this._upscaleCanvas){var upCanvas=this._upscaleCanvas;var upCtx=this._upscaleCtx;this._upscalePump=()=>{if(!this.isRecording)return;upCtx.drawImage(sourceCanvas,0,0,upCanvas.width,upCanvas.height);this._upscaleRafId=requestAnimationFrame(this._upscalePump);};}
var stream=recordCanvas.captureStream(CONFIG.fps);var audioStream=_startAudioCapture();if(audioStream){audioStream.getAudioTracks().forEach(function(track){stream.addTrack(track);});}
var recW=recordCanvas.width;var recH=recordCanvas.height;var bitrate=CONFIG.videoBitsPerSecond||getBitrateForResolution(recW,recH,CONFIG.fps);var opts={mimeType:mimeType,videoBitsPerSecond:bitrate};if(stream.getAudioTracks().length>0)opts.audioBitsPerSecond=CONFIG.audioBitsPerSecond;this.mediaRecorder=new MediaRecorder(stream,opts);this.chunks=[];this.startTime=Date.now();this.mediaRecorder.ondataavailable=(event)=>{if(event.data&&event.data.size>0)this.chunks.push(event.data);};this._onContextLost=()=>{logError('WebGL context lost');this.cancel();};sourceCanvas.addEventListener('webglcontextlost',this._onContextLost);this.mediaRecorder.start(1000);this.isRecording=true;if(this._upscalePump)this._upscalePump();var session=++this._sessionId;this.mediaRecorder.onstop=()=>{this._onMediaRecorderStop(session);};this._startRecordingUI();log('MediaRecorder recording started');return true;}catch(error){this._mrCleanup();logError('Failed to start recording:',error);return false;}}
_mrCleanup(){if(this._upscaleRafId){cancelAnimationFrame(this._upscaleRafId);this._upscaleRafId=null;}
this._upscaleCanvas=null;this._upscaleCtx=null;this._upscalePump=null;if(this._onContextLost){var canvas=document.getElementById('canvas');if(canvas)canvas.removeEventListener('webglcontextlost',this._onContextLost);this._onContextLost=null;}
_stopAudioCapture();}
async _onMediaRecorderStop(session){if(session!==this._sessionId)return;this.isRecording=false;this._hideStatus();this._updateFABIcon(false);var duration=Date.now()-this.startTime;if(this.uploadAfter){var totalSize=0;for(var i=0;i<this.chunks.length;i++)totalSize+=this.chunks[i].size;var buffer=new Uint8Array(totalSize);var offset=0;for(var i=0;i<this.chunks.length;i++){var ab=await this.chunks[i].arrayBuffer();buffer.set(new Uint8Array(ab),offset);offset+=ab.byteLength;}
this.chunks=[];log('MediaRecorder stopped, duration:',duration,'size:',totalSize);await this._uploadAndNotify(buffer.buffer,duration,session);}else{var blob=new Blob(this.chunks,{type:getSupportedMimeType()});this.chunks=[];log('MediaRecorder stopped, duration:',duration,'size:',blob.size);this._downloadBlob(blob);}}
_startRecordingUI(){this._showStatus();this._updateTimer();this.timerInterval=setInterval(()=>{this._updateTimer();},500);this.autoStopTimeout=setTimeout(()=>{if(this.isRecording){log('Max duration reached');this.stop();}},this.maxDuration);this._updateFABIcon(true);}
stop(){if(!this.isRecording){logWarn('Not recording');return false;}
if(this.timerInterval){clearInterval(this.timerInterval);this.timerInterval=null;}
if(this.autoStopTimeout){clearTimeout(this.autoStopTimeout);this.autoStopTimeout=null;}
this.isRecording=false;if(this._useWebCodecs){this._wcStopCapture();this._wcFinalize(this._sessionId);}else{this._mrCleanup();if(this.mediaRecorder&&this.mediaRecorder.state==='recording'){this.mediaRecorder.stop();}}
return true;}
cancel(){if(!this.isRecording)return false;if(this.timerInterval){clearInterval(this.timerInterval);this.timerInterval=null;}
if(this.autoStopTimeout){clearTimeout(this.autoStopTimeout);this.autoStopTimeout=null;}
this.isRecording=false;if(this._useWebCodecs){this._wcCleanup();}else{this._mrCleanup();if(this.mediaRecorder&&this.mediaRecorder.state==='recording'){this.mediaRecorder.onstop=null;this.mediaRecorder.stop();}
this.chunks=[];}
this._hideStatus();this._updateFABIcon(false);log('Recording cancelled');return true;}
_registerUploadCallback(){window.__onUploadUrlReady=(filename,uploadUrl,objectKey)=>{var pending=this._pendingRequest;if(!pending||pending.filename!==filename)return;clearTimeout(pending.timeout);this._pendingRequest=null;if(uploadUrl){uploadUrl=uploadUrl.replace(/^http:\/\//i,'https://');pending.resolve({uploadUrl,objectKey});}else{pending.reject(new Error('Upload URL request failed'));}};}
_requestUploadUrl(filename,type){if(this._pendingRequest){clearTimeout(this._pendingRequest.timeout);this._pendingRequest.reject(new Error('Superseded by new request'));this._pendingRequest=null;}
return new Promise((resolve,reject)=>{var timeout=setTimeout(()=>{this._pendingRequest=null;reject(new Error('Upload URL request timeout'));},5000);this._pendingRequest={filename,resolve,reject,timeout};if(typeof Module!=='undefined'&&typeof Module.ccall==='function'){try{Module.ccall('UrhoX_RequestUploadUrl',null,['string','string'],[filename,type]);}catch(e){clearTimeout(timeout);this._pendingRequest=null;reject(new Error('Engine ccall failed: '+e.message));}}else{clearTimeout(timeout);this._pendingRequest=null;reject(new Error('Engine upload API not available'));}});}
_putToOss(uploadUrl,buffer){return new Promise((resolve,reject)=>{var xhr=new XMLHttpRequest();this._currentXhr=xhr;xhr.addEventListener('load',()=>{this._currentXhr=null;if(xhr.status>=200&&xhr.status<300){resolve();}else{reject(new Error('OSS upload HTTP '+xhr.status));}});xhr.addEventListener('error',()=>{this._currentXhr=null;reject(new Error('Network error'));});xhr.addEventListener('abort',()=>{this._currentXhr=null;reject(new Error('Upload cancelled'));});xhr.open('PUT',uploadUrl);xhr.send(buffer);});}
cancelUpload(){if(!this._isUploading)return false;log('Cancelling upload');if(this._pendingRequest){clearTimeout(this._pendingRequest.timeout);this._pendingRequest.reject(new Error('Upload cancelled'));this._pendingRequest=null;}
if(this._currentXhr){this._currentXhr.abort();}
return true;}
async _uploadAndNotify(buffer,duration,session){var filename=generateFileName();var isStale=()=>session!==this._sessionId;this._isUploading=true;try{this._showUploadProgress();var credential=await this._requestUploadUrl(filename,'videos');if(isStale()){log('Upload abandoned (stale after credential)');this._isUploading=false;return;}
await this._putToOss(credential.uploadUrl,buffer);if(isStale()){log('Upload abandoned (stale after PUT)');this._isUploading=false;return;}
this._isUploading=false;this._showUploadComplete();var finalUrl='https://tapcode-sce.spark.xd.com/'+credential.objectKey;this._postResponse({type:'recording-response',success:true,data:{url:finalUrl,duration:duration}});log('Upload complete:',finalUrl);}catch(error){this._isUploading=false;if(isStale()){log('Upload error ignored (stale)');return;}
if(error.message==='Upload cancelled'){log('Upload cancelled by user');this._resetStatusBar();return;}
logError('Upload failed:',error);this._showUploadError('传输失败');this._postResponse({type:'recording-response',success:false,error:error.message||'Upload failed'});}}
_downloadBlob(blob){var url=URL.createObjectURL(blob);var a=document.createElement('a');a.href=url;a.download=generateFileName();document.body.appendChild(a);a.click();document.body.removeChild(a);setTimeout(()=>{URL.revokeObjectURL(url);},1000);log('Download triggered');}
_setupPostMessageListener(){var self=this;if(!window.UrhoXBridge)return;window.UrhoXBridge.registerHandler('recording-request-start',function(data){self.start({uploadAfter:true,maxDuration:data&&data.maxDuration});});window.UrhoXBridge.registerHandler('recording-request-stop',function(){self.stop();});window.UrhoXBridge.registerHandler('recording-request-cancel',function(){self.cancel();});log('Handlers registered to UrhoXBridge');}
_postResponse(responseData){try{if(window.isInTapFrame){window.parent.postMessage(responseData,'*');}}catch(e){}}
_registerToFAB(){var self=this;if(!window.floatingActionButton)return;window.floatingActionButton.registerAction({id:'canvas-recorder',icon:'🔴',label:'录屏',order:5,onClick:function(){if(self.isRecording){self.stop();}else{self.start({uploadAfter:false});}
window.floatingActionButton.collapse();}});log('Registered to FloatingActionButton');}
_updateFABIcon(isRecording){if(window.floatingActionButton){window.floatingActionButton.updateAction('canvas-recorder',{icon:isRecording?'⏹️':'🔴',label:isRecording?'停止录制':'录屏'});}}}
var recorder=new CanvasRecorder();window.canvasRecorder=recorder;log('Canvas Recorder Extension loaded');})(window);(function(){'use strict';var hrefLowerCase=window.location.href.toLowerCase();if(window.isInTapFrame||(hrefLowerCase.includes('tap')&&!hrefLowerCase.includes('test'))){return;}
var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[ScriptLoader]',...args);}
function logError(...args){console.error('[ScriptLoader]',...args);}
function logWarn(...args){console.warn('[ScriptLoader]',...args);}
let uploadedLuaContent=null;let uploadOverlay=null;let dragCounter=0;let dragTimer=null;function setupGlobalDragListener(){document.addEventListener('dragenter',(e)=>{if(e.dataTransfer&&e.dataTransfer.types.includes('Files')){dragCounter++;if(dragCounter===1){if(dragTimer){clearTimeout(dragTimer);dragTimer=null;}
showUploadPanel();}}});document.addEventListener('dragleave',(e)=>{dragCounter--;if(dragCounter<=0){dragCounter=0;}});document.addEventListener('drop',(e)=>{dragCounter=0;});document.addEventListener('dragend',(e)=>{dragCounter=0;});log('✓ 全局拖拽监听已启用（拖入文件显示上传面板）');}
function registerToFAB(){if(window.floatingActionButton){window.floatingActionButton.registerAction({id:'upload-script',icon:'🚀',label:'上传脚本',order:10,onClick:()=>{showUploadPanel();window.floatingActionButton.collapse();}});log('✓ 已注册到悬浮球菜单');}}
function showUploadPanel(){if(uploadOverlay){uploadOverlay.style.display='flex';uploadOverlay.classList.remove('fade-out');return;}
uploadOverlay=document.createElement('div');uploadOverlay.id='lua-upload-overlay';uploadOverlay.innerHTML=`
      <style>
        #lua-upload-overlay {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          background: rgba(0, 0, 0, 0.95);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 20000;
          opacity: 1;
          transition: opacity 0.3s ease-out;
        }
        
        #lua-upload-overlay.fade-out {
          opacity: 0;
          pointer-events: none;
        }
        
        #lua-upload-container {
          max-width: 800px;
          width: 95%;
          padding: 30px;
          text-align: center;
          position: relative;
        }
        
        #lua-upload-title {
          color: #fff;
          font-size: 28px;
          font-weight: 600;
          margin-bottom: 15px;
          text-shadow: 0 2px 4px rgba(0, 0, 0, 0.5);
        }
        
        #lua-upload-subtitle {
          color: rgba(255, 255, 255, 0.7);
          font-size: 16px;
          margin-bottom: 35px;
          line-height: 1.5;
        }
        
        #lua-drop-zone {
          border: 3px dashed rgba(74, 158, 255, 0.5);
          border-radius: 16px;
          padding: 100px 80px;
          min-height: 300px;
          background: rgba(26, 26, 26, 0.8);
          transition: all 0.3s ease;
          cursor: pointer;
          position: relative;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-sizing: border-box;
        }
        
        #lua-drop-zone:hover {
          border-color: rgba(74, 158, 255, 0.8);
          background: rgba(36, 36, 36, 0.9);
          box-shadow: 0 8px 24px rgba(74, 158, 255, 0.2);
        }
        
        #lua-drop-zone.drag-over {
          border-color: #4a9eff;
          background: rgba(74, 158, 255, 0.1);
          box-shadow: 0 0 30px rgba(74, 158, 255, 0.3);
        }
        
        #lua-drop-zone.uploading {
          border-color: #6eb5ff;
          background: rgba(74, 158, 255, 0.15);
        }
        
        #lua-drop-icon {
          font-size: 64px;
          margin-bottom: 20px;
          opacity: 0.8;
        }
        
        #lua-drop-text {
          color: #fff;
          font-size: 20px;
          font-weight: 500;
          margin-bottom: 12px;
        }
        
        #lua-drop-hint {
          color: rgba(255, 255, 255, 0.6);
          font-size: 14px;
          line-height: 1.6;
        }
        
        #lua-file-info {
          margin-top: 25px;
          padding: 20px;
          background: rgba(74, 158, 255, 0.1);
          border-radius: 12px;
          border: 1px solid rgba(74, 158, 255, 0.3);
          display: none;
        }
        
        #lua-file-info.visible {
          display: block;
        }
        
        #lua-file-name {
          color: #fff;
          font-size: 16px;
          font-weight: 500;
          margin-bottom: 8px;
          word-break: break-all;
        }
        
        #lua-file-size {
          color: rgba(255, 255, 255, 0.7);
          font-size: 14px;
          margin-bottom: 8px;
        }
        
        #lua-file-status {
          color: #6eb5ff;
          font-size: 14px;
          font-weight: 500;
        }
        
        #lua-upload-input {
          display: none;
        }
        
        @media (max-width: 600px) {
          #lua-upload-container {
            padding: 30px 20px;
          }
          
          #lua-upload-title {
            font-size: 24px;
          }
          
          #lua-drop-zone {
            padding: 40px 20px;
          }
          
          #lua-drop-icon {
            font-size: 48px;
          }
          
          #lua-drop-text {
            font-size: 18px;
          }
        }
      </style>
      
      <div id="lua-upload-container">
        <div id="lua-upload-title">🚀 上传并运行脚本</div>
        <div id="lua-upload-subtitle">上传 Lua 脚本文件，游戏将自动重启并运行（点击空白处关闭）</div>
        
        <div id="lua-drop-zone">
          <div id="lua-drop-icon">🚀</div>
          <div id="lua-drop-text">拖放 Lua 文件并运行</div>
          <div id="lua-drop-hint">
            或点击此区域选择文件<br>
            上传后将自动重启游戏并运行脚本
          </div>
        </div>
        
        <div id="lua-file-info">
          <div id="lua-file-name"></div>
          <div id="lua-file-size"></div>
          <div id="lua-file-status">✓ 准备就绪，正在重启并运行...</div>
        </div>
        
        <input type="file" id="lua-upload-input" accept=".lua" />
      </div>
    `;document.body.appendChild(uploadOverlay);const dropZone=document.getElementById('lua-drop-zone');const fileInput=document.getElementById('lua-upload-input');const fileInfo=document.getElementById('lua-file-info');const fileName=document.getElementById('lua-file-name');const fileSize=document.getElementById('lua-file-size');uploadOverlay.addEventListener('click',(e)=>{if(e.target===uploadOverlay){hideUploadPanel();}});uploadOverlay.addEventListener('drop',(e)=>{if(e.target===uploadOverlay){e.preventDefault();e.stopPropagation();log('在空白处松开，取消上传');hideUploadPanel();}});uploadOverlay.addEventListener('dragover',(e)=>{e.preventDefault();e.stopPropagation();});dropZone.addEventListener('click',()=>{fileInput.click();});fileInput.addEventListener('change',(e)=>{const files=e.target.files;if(files&&files.length>0){handleFile(files[0]);}});dropZone.addEventListener('dragover',(e)=>{e.preventDefault();e.stopPropagation();dropZone.classList.add('drag-over');});dropZone.addEventListener('dragleave',(e)=>{e.preventDefault();e.stopPropagation();dropZone.classList.remove('drag-over');});dropZone.addEventListener('drop',(e)=>{e.preventDefault();e.stopPropagation();dropZone.classList.remove('drag-over');log('在上传区域松开，开始处理文件');const files=e.dataTransfer.files;if(files&&files.length>0){handleFile(files[0]);}else{log('没有检测到文件');}});function handleFile(file){if(!file.name.endsWith('.lua')){alert('请上传 .lua 格式的文件！');return;}
const sizeKB=(file.size/1024).toFixed(2);fileName.textContent=`文件名: ${file.name}`;fileSize.textContent=`大小: ${sizeKB} KB`;fileInfo.classList.add('visible');dropZone.classList.add('uploading');const reader=new FileReader();reader.onload=function(e){uploadedLuaContent=e.target.result;log(`✓ Lua 文件已加载: ${file.name} (${file.size} bytes)`);setTimeout(()=>{hideUploadPanel();mountFileAndRestart();},1000);};reader.onerror=function(){alert('文件读取失败，请重试！');fileInfo.classList.remove('visible');dropZone.classList.remove('uploading');};reader.readAsText(file);}}
function hideUploadPanel(){if(uploadOverlay){uploadOverlay.classList.add('fade-out');setTimeout(()=>{uploadOverlay.style.display='none';},300);}
dragCounter=0;if(dragTimer){clearTimeout(dragTimer);dragTimer=null;}}
function mountFileAndRestart(){log('='.repeat(60));log('🔄 开始准备重启游戏...');log('='.repeat(60));if(!uploadedLuaContent){logError('✗ 没有可用的 Lua 文件内容');return;}
log(`文件内容长度: ${uploadedLuaContent.length} bytes`);log(`文件预览 (前100字符): ${uploadedLuaContent.substring(0, 100)}...`);try{const timestamp=Date.now();localStorage.setItem('urhoXPendingLuaFile',uploadedLuaContent);localStorage.setItem('urhoXPendingLuaTimestamp',timestamp.toString());const saved=localStorage.getItem('urhoXPendingLuaFile');if(saved&&saved.length===uploadedLuaContent.length){log(`✓ 文件内容已保存到 localStorage (${uploadedLuaContent.length} bytes)`);log(`✓ 时间戳: ${new Date(timestamp).toISOString()}`);}else{logError('✗ localStorage 保存验证失败！');alert('文件保存失败，请重试！');return;}
if(window.history&&window.history.replaceState){const baseUrl=window.location.origin+window.location.pathname;const newUrl=baseUrl+'?Scripts/UserUpload.lua';window.history.replaceState({},'',newUrl);log(`✓ URL 参数已更新: ${newUrl}`);}
log('✓ 准备工作完成，即将重启...');log('='.repeat(60));restartGame();}catch(error){logError('✗ 准备重启失败:',error);logError('错误堆栈:',error.stack);alert('准备重启失败: '+error.message);}}
function restartGame(){log('正在重启游戏...');try{if(window.Module&&typeof window.Module.ccall==='function'){try{log('尝试调用引擎重启接口...');}catch(e){log('引擎不支持直接重启:',e.message);}}
log('使用页面刷新方式重启游戏...');setTimeout(()=>{window.location.reload();},500);}catch(error){logError('✗ 重启游戏失败:',error);alert('重启失败: '+error.message);}}
function mountPendingLuaFile(){log('检查 localStorage 中的待处理文件...');const pendingFile=localStorage.getItem('urhoXPendingLuaFile');const timestamp=localStorage.getItem('urhoXPendingLuaTimestamp');log('localStorage 检查结果:');log('  - urhoXPendingLuaFile:',pendingFile?`存在 (${pendingFile.length} bytes)`:'不存在');log('  - urhoXPendingLuaTimestamp:',timestamp||'不存在');if(!pendingFile){log('没有待处理的文件，跳过');return;}
log('✓ 检测到待加载的 Lua 文件');if(timestamp){const age=Date.now()-parseInt(timestamp);log(`文件年龄: ${(age / 1000).toFixed(1)} 秒`);}
if(!window.Module){window.Module={};}
const originalPreRun=window.Module.preRun||[];const preRunArray=Array.isArray(originalPreRun)?originalPreRun:[originalPreRun];preRunArray.push(function(){log('>>> preRun 回调被调用');log('Module.FS 可用:',!!window.Module.FS);if(window.Module.FS){try{const FS=window.Module.FS;const targetDir='/AgentProject/Scripts';try{FS.stat(targetDir);log(`目录已存在: ${targetDir}`);}catch(e){log(`创建目录: ${targetDir}`);FS.mkdirTree(targetDir);}
const targetPath=targetDir+'/UserUpload.lua';FS.writeFile(targetPath,pendingFile);log(`✓ Lua 文件已挂载到: ${targetPath}`);log(`文件大小: ${pendingFile.length} bytes`);}catch(error){logError('✗ 挂载 Lua 文件失败:',error);logError('错误堆栈:',error.stack);}}else{logWarn('⚠ Module.FS 尚未初始化，将稍后重试...');const retryMount=function(){if(window.Module.FS){log('FS 已初始化，开始挂载...');try{const FS=window.Module.FS;const targetDir='/AgentProject/Scripts';try{FS.stat(targetDir);}catch(e){FS.mkdirTree(targetDir);}
const targetPath=targetDir+'/UserUpload.lua';FS.writeFile(targetPath,pendingFile);log(`✓ Lua 文件已挂载到: ${targetPath}`);log(`文件大小: ${pendingFile.length} bytes`);log(`✓ 延迟挂载成功`);}catch(error){logError('✗ 延迟挂载失败:',error);}}else{log('FS 仍未初始化，继续等待...');setTimeout(retryMount,100);}};setTimeout(retryMount,100);}});window.Module.preRun=preRunArray;log('✓ preRun 钩子已注册');}
function init(){log('='.repeat(60));log('初始化用户脚本加载器扩展 v2.1');log('当前时间:',new Date().toISOString());log('页面 URL:',window.location.href);log('='.repeat(60));mountPendingLuaFile();setupGlobalDragListener();registerToFAB();if(!window.floatingActionButton){const checkFAB=setInterval(()=>{if(window.floatingActionButton){registerToFAB();clearInterval(checkFAB);}},100);setTimeout(()=>clearInterval(checkFAB),5000);}}
init();window.UrhoXScriptLoader={showUploadPanel:showUploadPanel,hideUploadPanel:hideUploadPanel,version:'2.1.0'};})();(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){console.log('[MultiDebug]',...args);}
function logV(...args){if(VERBOSE)console.log('[MultiDebug]',...args);}
function error(...args){console.error('[MultiDebug]',...args);}
function openDebugClientWithBase64(base64Params,index){var urlParams=new URLSearchParams(location.search);urlParams.delete('multiDebugNum');urlParams.set('directConnectParams',base64Params);var url=location.origin+location.pathname+'?'+urlParams.toString();log('Opening debug client: index='+index);logV('URL:',url);var win=window.open(url,'debug_client_'+index,'width=960,height=640');if(!win){error('Failed to open debug client window. Please allow popups for this site.');}
return win;}
function openAllDebugClientsWithBase64(base64List){var playerCount=base64List.length;var failedCount=0;for(var i=0;i<playerCount;i++){var win=openDebugClientWithBase64(base64List[i],i);if(!win)failedCount++;}
if(failedCount>0){log('Warning: '+failedCount+' window(s) blocked. Please allow popups for this site.');setTimeout(function(){alert('有 '+failedCount+' 个调试窗口被浏览器阻止。\n\n请点击地址栏右侧的弹窗图标，允许此网站的弹窗，然后重试。');},100);}}
function showConfirmDialog(base64List){var playerCount=base64List.length;var overlay=document.getElementById('multi-debug-overlay');if(!overlay){var confirmed=confirm('多开调试\n\n将打开 '+playerCount+' 个调试客户端窗口\n\n是否继续？');if(confirmed){openAllDebugClientsWithBase64(base64List);}
return;}
var messageEl=overlay.querySelector('#multi-debug-message');if(messageEl){messageEl.textContent='即将打开 '+playerCount+' 个调试窗口';}
var confirmBtn=overlay.querySelector('#multi-debug-confirm');var cleanup=function(){overlay.classList.remove('visible');confirmBtn.onclick=null;};confirmBtn.onclick=function(){cleanup();openAllDebugClientsWithBase64(base64List);};overlay.classList.add('visible');log('Confirm dialog shown, playerCount='+playerCount);}
function injectDialogHTML(){if(document.getElementById('multi-debug-overlay')){return;}
var style=document.createElement('style');style.id='multi-debug-styles';style.textContent='\
      #multi-debug-overlay {\
        position: fixed; inset: 0; background: rgba(0,0,0,0.6);\
        display: flex; align-items: center; justify-content: center; z-index: 21000;\
        opacity: 0; visibility: hidden; transition: opacity 0.2s, visibility 0.2s;\
        backdrop-filter: blur(4px);\
      }\
      #multi-debug-overlay.visible { opacity: 1; visibility: visible; }\
      #multi-debug-box {\
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);\
        border-radius: 16px; padding: 40px 56px;\
        text-align: center; min-width: 340px;\
        box-shadow: 0 20px 60px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.1);\
      }\
      #multi-debug-icon {\
        font-size: 48px; margin-bottom: 16px;\
      }\
      #multi-debug-title {\
        color: #fff; font-size: 22px; margin: 0 0 12px 0; font-weight: 600;\
        letter-spacing: 0.5px;\
      }\
      #multi-debug-message {\
        color: rgba(255,255,255,0.7); font-size: 15px; margin: 0 0 32px 0;\
        line-height: 1.5;\
      }\
      #multi-debug-actions { display: flex; justify-content: center; }\
      .multi-debug-btn {\
        padding: 14px 52px; border-radius: 8px; font-size: 18px; font-weight: 500;\
        cursor: pointer; transition: all 0.2s; border: none;\
        letter-spacing: 2px;\
      }\
      .multi-debug-btn.primary {\
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\
        color: #fff; box-shadow: 0 4px 20px rgba(102,126,234,0.4);\
      }\
      .multi-debug-btn.primary:hover {\
        transform: translateY(-2px);\
        box-shadow: 0 6px 30px rgba(102,126,234,0.5);\
      }\
      .multi-debug-btn.primary:active { transform: translateY(0); }\
    ';document.head.appendChild(style);var overlay=document.createElement('div');overlay.id='multi-debug-overlay';overlay.innerHTML='\
      <div id="multi-debug-box">\
        <div id="multi-debug-icon">🎮</div>\
        <h2 id="multi-debug-title">多开调试</h2>\
        <p id="multi-debug-message">即将打开调试窗口</p>\
        <div id="multi-debug-actions">\
          <button id="multi-debug-confirm" class="multi-debug-btn primary">开始</button>\
        </div>\
      </div>\
    ';document.body.appendChild(overlay);logV('Dialog HTML injected');}
function init(){window.UrhoX=window.UrhoX||{};injectDialogHTML();window.UrhoX.onMultiDebugStart=function(base64ListJson){try{var base64List=JSON.parse(base64ListJson);log('onMultiDebugStart: playerCount='+base64List.length);window.parent.postMessage({type:'multi-debug-request',data:{instanceToDirectConnectParams:base64List}},'*');if(!window.isInTapFrame){showConfirmDialog(base64List);}}catch(e){error('Failed to parse base64 list:',e);}};log('Extension initialized');}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',init);}else{init();}
window.multiDebugExtension={showDialog:showConfirmDialog,openClient:openDebugClientWithBase64,openAllClients:openAllDebugClientsWithBase64};})(window);(function(window){'use strict';var VERBOSE=window.WASM_PLAYER_CONFIG&&window.WASM_PLAYER_CONFIG.verbose;function log(...args){if(VERBOSE)console.log('[CornerInfo]',...args);}
const CONFIG={offset:12,imageSize:32,gap:8,padding:8,fontSize:12,lineHeight:1.4,colors:{text:'rgba(255, 255, 255, 0.7)'}};const POSITIONS={'top-left':{top:CONFIG.offset,left:CONFIG.offset,bottom:'auto',right:'auto',flexDir:'row'},'top-right':{top:CONFIG.offset,right:CONFIG.offset,bottom:'auto',left:'auto',flexDir:'row-reverse'},'bottom-left':{bottom:CONFIG.offset,left:CONFIG.offset,top:'auto',right:'auto',flexDir:'row'},'bottom-right':{bottom:CONFIG.offset,right:CONFIG.offset,top:'auto',left:'auto',flexDir:'row-reverse'}};function injectStyles(){const styleId='corner-info-styles';if(document.getElementById(styleId))return;const style=document.createElement('style');style.id=styleId;style.textContent=`
      .urhox-corner-info {
        position: fixed;
        z-index: 99990;
        display: none;
        align-items: center;
        gap: ${CONFIG.gap}px;
        padding: ${CONFIG.padding}px;
        pointer-events: none;
        user-select: none;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
      }

      .urhox-corner-info.visible {
        display: flex;
      }

      .urhox-corner-info-image {
        width: ${CONFIG.imageSize}px;
        height: ${CONFIG.imageSize}px;
        object-fit: contain;
        flex-shrink: 0;
      }

      .urhox-corner-info-text {
        font-size: clamp(8px, min(2vw, 2vh), ${CONFIG.fontSize}px);
        line-height: ${CONFIG.lineHeight};
        color: ${CONFIG.colors.text};
        text-shadow:
          0 1px 2px rgba(0, 0, 0, 0.8),
          0 2px 6px rgba(0, 0, 0, 0.5);
        white-space: pre-line;
        margin: 0;
      }
    `;document.head.appendChild(style);}
class CornerInfo{constructor(){this.container=null;this.imageEl=null;this.textEl=null;this.currentConfig={position:'bottom-left',image:null,text:''};this.isVisible=false;}
init(){injectStyles();this.createElements();log('CornerInfo initialized');}
createElements(){this.container=document.createElement('div');this.container.className='urhox-corner-info';this.container.id='urhoxCornerInfo';this.imageEl=document.createElement('img');this.imageEl.className='urhox-corner-info-image';this.imageEl.style.display='none';this.textEl=document.createElement('p');this.textEl.className='urhox-corner-info-text';this.container.appendChild(this.imageEl);this.container.appendChild(this.textEl);document.body.appendChild(this.container);this.applyPosition('bottom-left');}
applyPosition(pos){const p=POSITIONS[pos]||POSITIONS['bottom-left'];this.container.style.top=typeof p.top==='number'?p.top+'px':p.top;this.container.style.bottom=typeof p.bottom==='number'?p.bottom+'px':p.bottom;this.container.style.left=typeof p.left==='number'?p.left+'px':p.left;this.container.style.right=typeof p.right==='number'?p.right+'px':p.right;this.container.style.flexDirection=p.flexDir;}
show(options={}){if(!this.container){this.init();}
this.update(options);this.container.classList.add('visible');this.isVisible=true;log('CornerInfo shown');}
hide(){if(this.container){this.container.classList.remove('visible');this.isVisible=false;log('CornerInfo hidden');}}
update(options={}){if(!this.container){this.init();}
if(options.position!==undefined){this.currentConfig.position=options.position;this.applyPosition(options.position);}
if(options.image!==undefined){this.currentConfig.image=options.image;}
if(this.currentConfig.image){this.imageEl.src=this.currentConfig.image;this.imageEl.style.display='block';}else{this.imageEl.style.display='none';}
if(options.text!==undefined){this.currentConfig.text=options.text;}
this.textEl.textContent=this.currentConfig.text||'';log('CornerInfo updated',this.currentConfig);}
setStyle(styles={}){if(!this.container)return;if(styles.imageSize!==undefined){this.imageEl.style.width=styles.imageSize+'px';this.imageEl.style.height=styles.imageSize+'px';}
if(styles.fontSize!==undefined){this.textEl.style.fontSize=styles.fontSize+'px';}
if(styles.textColor!==undefined){this.textEl.style.color=styles.textColor;}
if(styles.offset!==undefined){CONFIG.offset=styles.offset;this.applyPosition(this.currentConfig.position);}}
getState(){return{isVisible:this.isVisible,position:this.currentConfig.position,image:this.currentConfig.image,text:this.currentConfig.text};}
destroy(){if(this.container){this.container.remove();this.container=null;this.imageEl=null;this.textEl=null;}
const style=document.getElementById('corner-info-styles');if(style){style.remove();}
log('CornerInfo destroyed');}}
const instance=new CornerInfo();function initCornerInfo(){instance.init();}
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',initCornerInfo);}else{initCornerInfo();}
window.UrhoX=window.UrhoX||{};window.UrhoX.cornerInfo={show:instance.show.bind(instance),hide:instance.hide.bind(instance),update:instance.update.bind(instance),setStyle:instance.setStyle.bind(instance),getState:instance.getState.bind(instance),destroy:instance.destroy.bind(instance)};})(window);(function(){'use strict';if(window.UrhoX&&window.UrhoX.isPublishGame)return;var forceTest=new URLSearchParams(window.location.search).get('test_boot_log')==='true';var el=null;var stopped=false;var seen=Object.create(null);function append(text){if(stopped)return;if(seen[text])return;seen[text]=true;if(!el){el=document.createElement('div');el.style.cssText='position:fixed;bottom:0;left:0;right:0;'+'max-height:35vh;overflow-y:auto;z-index:99999;'+'padding:6px 10px;'+'font:10px/1.3 "SF Mono","Menlo",monospace;'+'color:#f87171;word-break:break-all;'+'-webkit-overflow-scrolling:touch;';(document.body||document.documentElement).appendChild(el);}
var d=document.createElement('div');d.textContent='['+new Date().toTimeString().slice(0,8)+'] '+text;el.appendChild(d);el.scrollTop=el.scrollHeight;}
function onError(e){append((e.message||'Error')+(e.filename?' ('+e.filename.split('/').pop()+':'+e.lineno+')':''));}
function onRejection(e){append('Promise: '+((e.reason&&e.reason.message)||e.reason||'Unknown'));}
var _origErr=console.error;function consoleErrorHook(){_origErr.apply(console,arguments);append([].slice.call(arguments).join(' '));}
function stop(){if(stopped)return;stopped=true;seen={};if(el){el.remove();el=null;}
window.removeEventListener('error',onError);window.removeEventListener('unhandledrejection',onRejection);window.removeEventListener('urhox:loading-hidden',stop);if(console.error===consoleErrorHook){console.error=_origErr;}}
window.addEventListener('error',onError);window.addEventListener('unhandledrejection',onRejection);window.addEventListener('urhox:loading-hidden',stop);console.error=consoleErrorHook;if(forceTest){_origErr('[BootLog] test mode enabled');var count=0;var testTimer=setInterval(function(){count++;if(count>20||stopped){clearInterval(testTimer);return;}
switch(count%3){case 1:console.error('Test console.error #'+count);break;case 2:setTimeout(function(n){throw new Error('Test thrown error #'+n);},0,count);break;case 0:Promise.reject('Test unhandled rejection #'+count);break;}},300);}})();