// players.js — drop-in "who's playing?" picker for the Learn wing.
// Include with: <script src="shared/players.js"></script>
// Then call Players.init(function(profile){ ... start the game ... });
//
// profile = {id, name, avatar, level} where level is 'toddler' | 'k' | '3rd'.
// Falls back to a local guest profile if the arcade API is unreachable.
(function(global){
  var API = 'shared/arcade-api.php';
  var AVATARS = ['🦊','🐻','🐸','🐝','🦁','🐵','🐰','🐼'];
  var LEVELS = [['toddler','🐣 Toddler'],['k','🐸 Kindergarten'],['3rd','🦁 3rd Grade']];

  function store(k,v){
    try{
      if(v===undefined)return JSON.parse(localStorage.getItem(k));
      localStorage.setItem(k,JSON.stringify(v));
    }catch(e){return null}
  }

  function api(action,body){
    return new Promise(function(res,rej){
      var ctl=global.AbortController?new AbortController():null;
      var to=setTimeout(function(){if(ctl)ctl.abort();rej(new Error('timeout'))},2500);
      fetch(API+'?action='+action,{
        method:body?'POST':'GET',
        body:body?JSON.stringify(body):undefined,
        signal:ctl?ctl.signal:undefined,
        cache:'no-store'
      }).then(function(r){if(!r.ok)throw new Error('http '+r.status);return r.json()})
        .then(function(j){clearTimeout(to);if(!j||!j.state)throw new Error('bad json');res(j)})
        .catch(function(e){clearTimeout(to);rej(e)});
    });
  }

  function guestProfile(){
    var g=store('rtguest');
    if(!g){g={id:'guest',name:'Guest',avatar:AVATARS[0],level:'k'};store('rtguest',g)}
    return g;
  }

  function localProfiles(){
    return store('rtprofiles')||[];
  }
  function saveLocalProfiles(list){
    store('rtprofiles',list);
  }

  function buildPickerDOM(){
    var wrap=document.createElement('div');
    wrap.id='playerPickerOverlay';
    wrap.style.cssText='position:fixed;inset:0;z-index:999;background:#151a2e;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2.2vmin;font-family:system-ui,sans-serif;color:#fff;padding:4vmin;';
    wrap.innerHTML=
      '<h1 style="font-size:clamp(1.3rem,6vmin,2rem);margin:0;text-align:center">🎓 Who\'s playing?</h1>'+
      '<div id="ppList" style="display:flex;flex-wrap:wrap;gap:2.2vmin;justify-content:center;max-width:640px"></div>'+
      '<div id="ppAdd" style="display:flex;align-items:center;justify-content:center;gap:.5rem;width:96px;height:96px;border-radius:50%;background:rgba(255,255,255,.14);font-size:2.2rem;box-shadow:0 5px 0 rgba(0,0,0,.3)">➕</div>'+
      '<div id="ppGuest" style="color:rgba(255,255,255,.65);font-size:1rem;padding:.5rem 1rem">skip — just play</div>'+
      '<div id="ppNew" style="display:none;flex-direction:column;gap:1.4vmin;align-items:center;background:rgba(255,255,255,.08);padding:3vmin;border-radius:20px;max-width:420px;width:88vw">'+
        '<div id="ppAvatars" style="display:flex;flex-wrap:wrap;gap:1vmin;justify-content:center"></div>'+
        '<input id="ppName" maxlength="24" placeholder="name" style="font-size:1.3rem;padding:.5rem .8rem;border-radius:12px;border:none;width:80%;text-align:center">'+
        '<div id="ppLevels" style="display:flex;gap:.6rem"></div>'+
        '<div style="display:flex;gap:1rem">'+
          '<div id="ppSave" style="padding:.7rem 1.6rem;border-radius:999px;background:#43aa2b;font-weight:800;box-shadow:0 4px 0 rgba(0,0,0,.3)">Save</div>'+
          '<div id="ppCancel" style="padding:.7rem 1.6rem;border-radius:999px;background:rgba(255,255,255,.18);font-weight:800">Cancel</div>'+
        '</div>'+
      '</div>';
    document.body.appendChild(wrap);
    return wrap;
  }

  function tile(p,onPick){
    var d=document.createElement('div');
    d.style.cssText='display:flex;flex-direction:column;align-items:center;gap:.4rem;cursor:pointer;touch-action:manipulation';
    d.innerHTML='<div style="width:88px;height:88px;border-radius:50%;background:rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center;font-size:2.8rem;box-shadow:0 5px 0 rgba(0,0,0,.3)">'+p.avatar+'</div>'+
      '<div style="font-weight:700;font-size:.95rem">'+p.name+'</div>';
    d.addEventListener('pointerdown',function(){onPick(p)});
    return d;
  }

  var Players={};

  Players.init=function(onReady){
    var last=store('rtlastplayer');
    var overlay=null;

    function finish(profile){
      store('rtlastplayer',profile);
      if(overlay){overlay.remove()}
      onReady(profile);
    }

    function showPicker(list,serverOk){
      overlay=buildPickerDOM();
      var listEl=overlay.querySelector('#ppList');
      list.forEach(function(p){
        listEl.appendChild(tile(p,function(picked){finish(picked)}));
      });
      overlay.querySelector('#ppGuest').addEventListener('pointerdown',function(){
        finish(guestProfile());
      });
      overlay.querySelector('#ppAdd').addEventListener('pointerdown',function(){
        showNewForm(overlay,list,serverOk,finish);
      });
    }

    if(last){
      // Still show picker briefly? No — per spec, remembers last player, so skip straight in,
      // but offer a way back to the picker via a small corner control the game can add itself.
      onReady(last);
      return;
    }

    api('state').then(function(j){
      var list=j.state.profiles&&j.state.profiles.length?j.state.profiles:localProfiles();
      showPicker(list,true);
    }).catch(function(){
      showPicker(localProfiles(),false);
    });
  };

  Players.reopen=function(onReady){
    store('rtlastplayer',null);
    Players.init(onReady);
  };

  function showNewForm(overlay,list,serverOk,finish){
    overlay.querySelector('#ppList').style.display='none';
    overlay.querySelector('#ppAdd').style.display='none';
    overlay.querySelector('#ppGuest').style.display='none';
    var form=overlay.querySelector('#ppNew');
    form.style.display='flex';
    var avEl=form.querySelector('#ppAvatars');
    var chosenAvatar=AVATARS[0],chosenLevel='k';
    AVATARS.forEach(function(a){
      var b=document.createElement('div');
      b.textContent=a;
      b.style.cssText='width:52px;height:52px;border-radius:50%;background:rgba(255,255,255,.14);display:flex;align-items:center;justify-content:center;font-size:1.6rem;border:3px solid transparent';
      if(a===chosenAvatar)b.style.borderColor='#fff';
      b.addEventListener('pointerdown',function(){
        chosenAvatar=a;
        avEl.querySelectorAll('div').forEach(function(n){n.style.borderColor='transparent'});
        b.style.borderColor='#fff';
      });
      avEl.appendChild(b);
    });
    var lvEl=form.querySelector('#ppLevels');
    LEVELS.forEach(function(lv){
      var b=document.createElement('div');
      b.textContent=lv[1];
      b.style.cssText='padding:.5rem .8rem;border-radius:999px;background:rgba(255,255,255,.14);font-size:.85rem;font-weight:700;border:2px solid transparent';
      if(lv[0]===chosenLevel)b.style.borderColor='#fff';
      b.addEventListener('pointerdown',function(){
        chosenLevel=lv[0];
        lvEl.querySelectorAll('div').forEach(function(n){n.style.borderColor='transparent'});
        b.style.borderColor='#fff';
      });
      lvEl.appendChild(b);
    });
    form.querySelector('#ppCancel').addEventListener('pointerdown',function(){
      form.style.display='none';
      overlay.querySelector('#ppList').style.display='flex';
      overlay.querySelector('#ppAdd').style.display='flex';
      overlay.querySelector('#ppGuest').style.display='block';
    });
    form.querySelector('#ppSave').addEventListener('pointerdown',function(){
      var name=form.querySelector('#ppName').value.trim();
      if(!name)return;
      var profile={id:'p'+Math.random().toString(36).slice(2,10),name:name,avatar:chosenAvatar,level:chosenLevel};
      var updated=list.concat([profile]);
      saveLocalProfiles(updated);
      if(serverOk){
        api('setprofiles',{profiles:updated}).catch(function(){});
      }
      finish(profile);
    });
  }

  Players.award=function(profile,n){
    if(!profile||profile.id==='guest')return;
    api('award',{profileId:profile.id,stars:n||1}).catch(function(){});
  };

  Players.levelDefault=function(profile,map){
    // map = {toddler:..., k:..., '3rd':...}; falls back to map.k
    if(!profile)return map.k;
    return map[profile.level]!==undefined?map[profile.level]:map.k;
  };

  global.Players=Players;
})(window);
