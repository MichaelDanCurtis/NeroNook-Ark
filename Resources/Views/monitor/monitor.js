(() => {
  const $ = id => document.getElementById(id);
  let state={}, target='', editing=false, pending=false, entered=0;
  const targetValues = extra => ({device:state.device, host:state.host, ...extra});
  function draft(value) { entered=Number(value); $('volume-number').value=value; $('volume-slider').value=value; }
  function message(text) { $('notice').textContent=text; $('notice').title=text; $('notice').classList.add('result'); }
  async function emit(name, values={}) {
    if (pending) return;
    pending=true;
    try { await window.nero.emit(name,values); }
    catch { message('This control changed or is unavailable. Refresh before trying again.'); }
    finally { pending=false; }
  }
  function setVolume() {
    const raw=$('volume-number').value.trim();
    const value=Number(raw);
    if (!raw || !Number.isInteger(value) || value<0 || value>100 || !state.can_volume || state.busy) { editing=false;draft(state.volume??0);message('Choose a whole volume from 0 to 100 when the monitor is ready.');return; }
    editing=false; emit('volume',targetValues({value}));
  }
  function render(s) {
    if (!s.device && !('connected' in s)) return;
    const nextTarget=s.device+'|'+s.host;
    if (nextTarget!==target) { editing=false;target=nextTarget; }
    state=s;
    $('model').textContent=s.model?.startsWith('LS55')?'55″ curved display':'Samsung display';
    $('model').title=s.model;
    $('resolution').textContent=s.resolution||'Local connection';
    $('connection').textContent=s.connected?'Connected':'Unavailable';
    $('connection').classList.toggle('offline',!s.connected);
    $('remote-state').textContent=s.remote_ready?'Connected':s.remote_connecting?'Connecting…':'Not connected';
    $('remote-state').classList.toggle('ready',s.remote_ready);
    $('remote-hint').textContent=s.remote_ready?'Navigation on your monitor':s.remote_status&&s.remote_status!=='Remote not connected'?s.remote_status:s.paired?'Use your saved pairing':'Approve pairing on the monitor';
    $('remote-hint').title=s.remote_status||'';
    $('pair').textContent=s.remote_ready?'Reconnect':s.paired?'Connect':'Pair remote';
    $('pair').disabled=!s.connected||s.busy||s.remote_connecting;
    $('audio-status').textContent=s.can_volume?(s.muted===true?'Muted':s.muted===false?'Sound on':'Mute unavailable'):'Audio unavailable';
    if (!s.can_volume) { editing=false;$('volume-number').value='';$('volume-number').placeholder='—'; }
    else if (!editing) draft(s.volume);
    ['volume-number','volume-slider','minus','plus','set-volume'].forEach(id => $(id).disabled=!s.can_volume||s.busy);
    ['sound-on','muted'].forEach(id => $(id).disabled=!s.can_mute||s.busy);
    $('sound-on').setAttribute('aria-pressed',s.muted===false);
    $('muted').setAttribute('aria-pressed',s.muted===true);
    document.querySelectorAll('[data-key]').forEach(b => b.disabled=!s.remote_ready||s.busy);
    $('refresh').disabled=s.busy||s.refreshing;
    const note=s.notice||(!s.connected?'Open setup to connect your monitor.':'Audio follows the monitor · drag the slider to set volume');
    $('notice').textContent=note;$('notice').title=note;$('notice').classList.toggle('result',!!s.notice);
    $('last-read').textContent=s.busy?'Updating…':s.connected?`Read ${s.last_read}`:'';
  }
  $('volume-number').oninput=e=>{editing=true;entered=Number(e.target.value);};
  $('volume-number').onkeydown=e=>{if(e.key==='Escape'){editing=false;draft(state.volume??0);$('volume-number').blur();}};
  $('volume-number').onblur=()=>{if(editing && (!Number.isInteger(entered)||entered<0||entered>100)){editing=false;draft(state.volume??0);}};
  $('volume-form').onsubmit=e=>{e.preventDefault();setVolume();};
  $('volume-slider').oninput=e=>{editing=true;draft(e.target.value);};
  $('volume-slider').onchange=setVolume;
  $('minus').onclick=()=>{editing=false;emit('adjust',targetValues({delta:-1}));};
  $('plus').onclick=()=>{editing=false;emit('adjust',targetValues({delta:1}));};
  $('sound-on').onclick=()=>emit('mute',targetValues({value:false}));
  $('muted').onclick=()=>emit('mute',targetValues({value:true}));
  $('refresh').onclick=()=>{editing=false;emit('refresh');};
  $('settings').onclick=()=>emit('settings');
  $('pair').onclick=()=>emit('pair',targetValues({}));
  document.querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>emit('key',targetValues({key:b.dataset.key})));
  window.nero?.onState(render);
})();
