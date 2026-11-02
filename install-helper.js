(() => {
"use strict";
const isIOS=/iphone|ipad|ipod/i.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
const isAndroid=/android/i.test(navigator.userAgent);
const isStandalone=()=>window.matchMedia("(display-mode: standalone)").matches||window.matchMedia("(display-mode: fullscreen)").matches||navigator.standalone===true;
let deferredPrompt=null,shown=false;
const style=document.createElement("style");
style.textContent="#romano-install-dialog{position:fixed;z-index:10060;inset:0;background:#111a;display:grid;place-items:center;padding:18px}#romano-install-dialog[hidden]{display:none}#romano-install-dialog .ri-card{width:min(440px,100%);max-height:88vh;overflow:auto;background:#fffdf8;color:#211f1a;border:1px solid #dfcfb2;border-radius:22px;padding:24px;box-shadow:0 24px 80px #0005;font:14px/1.5 system-ui,-apple-system,sans-serif}#romano-install-dialog h2{font:700 23px Georgia,serif;margin:0 0 8px}#romano-install-dialog p{margin:8px 0;color:#514b40}#romano-install-dialog ol{padding-left:22px;margin:12px 0}#romano-install-dialog li{margin:8px 0}#romano-install-dialog .ri-actions{display:flex;gap:9px;flex-wrap:wrap;margin-top:18px}#romano-install-dialog button{border:0;border-radius:999px;padding:11px 16px;font-weight:700;cursor:pointer}#romano-install-dialog .ri-primary{background:#1c1c19;color:#fff}#romano-install-dialog .ri-secondary{background:#eee5d6;color:#342b1d}";
document.head.appendChild(style);
const modal=document.createElement("div");modal.id="romano-install-dialog";modal.hidden=true;
modal.innerHTML="<section class='ri-card' role='dialog' aria-modal='true' aria-labelledby='ri-title'><h2 id='ri-title'>Adicionar ROMANO ao ecrã inicial</h2><p id='ri-intro'>Tenha a aplicação disponível diretamente no telemóvel.</p><div id='ri-instructions'></div><div class='ri-actions'><button type='button' class='ri-primary' id='ri-install-now' hidden>Instalar agora</button><button type='button' class='ri-secondary' id='ri-close'>Agora não</button></div></section>";
document.body.appendChild(modal);
const close=()=>{modal.hidden=true;try{localStorage.setItem("romano_install_guide_seen","1")}catch(_){}};
modal.querySelector("#ri-close").addEventListener("click",close);
modal.addEventListener("click",e=>{if(e.target===modal)close()});
document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!modal.hidden)close()});
async function installNow(){
 const p=deferredPrompt||(typeof __romanoInstallPrompt!=="undefined"?__romanoInstallPrompt:null);
 if(!p)return;
 deferredPrompt=null;
 try{await p.prompt();await p.userChoice;modal.hidden=true;try{localStorage.setItem("romano_install_guide_seen","1")}catch(_){}}catch(_){}
}
modal.querySelector("#ri-install-now").addEventListener("click",installNow);
function employeeRole(){
 try{return String(window.currentProfile?.role|| (typeof currentProfile!=="undefined"?currentProfile?.role:"") || (typeof role==="function"?role():"")).toLowerCase().trim()}catch(_){return ""}
}
function showGuide(){
 if(shown||isStandalone())return;
 shown=true;modal.hidden=false;
 const intro=modal.querySelector("#ri-intro"),instructions=modal.querySelector("#ri-instructions"),install=modal.querySelector("#ri-install-now");
 install.hidden=true;
 if(isIOS){
  intro.textContent="No iPhone/iPad, faça estes passos uma única vez no Safari:";
  instructions.innerHTML="<ol><li>Se abriu pelo e-mail, abra o mesmo link no <b>Safari</b>.</li><li>Toque em <b>Partilhar</b> (quadrado com seta para cima).</li><li>Escolha <b>Adicionar ao ecrã principal</b>.</li><li>Toque em <b>Adicionar</b>.</li></ol>";
 }else if(isAndroid&&deferredPrompt){
  intro.textContent="Toque abaixo e confirme para adicionar a ROMANO ao ecrã inicial.";
  instructions.innerHTML="<p>A aplicação ficará disponível pelo ícone no telemóvel.</p>";install.hidden=false;
 }else if(isAndroid){
  intro.textContent="Para adicionar a aplicação ao ecrã inicial:";
  instructions.innerHTML="<ol><li>Abra este link no <b>Chrome</b>, fora do navegador do e-mail.</li><li>Toque no menu <b>⋮</b>.</li><li>Escolha <b>Instalar aplicação</b> ou <b>Adicionar ao ecrã inicial</b>.</li><li>Confirme em <b>Adicionar/Instalar</b>.</li></ol>";
 }else{
  intro.textContent="Abra a aplicação no navegador principal e use a opção de instalação:";
  instructions.innerHTML="<ol><li>Abra o menu do navegador.</li><li>Escolha <b>Instalar aplicação</b> ou <b>Adicionar ao ecrã inicial</b>.</li><li>Confirme.</li></ol>";
 }
}
function maybeShow(){
 if(shown||isStandalone()||!["employee","maintenance_technician"].includes(employeeRole()))return;
 let seen=false;try{seen=localStorage.getItem("romano_install_guide_seen")==="1"}catch(_){}
 if(!seen)showGuide();
}
window.addEventListener("beforeinstallprompt",e=>{e.preventDefault();deferredPrompt=e;});
window.addEventListener("appinstalled",()=>{deferredPrompt=null;modal.hidden=true;});
window.installRomanoApp=()=>{if(["employee","maintenance_technician"].includes(employeeRole()))showGuide()};
const observer=new MutationObserver(maybeShow);observer.observe(document.documentElement,{childList:true,subtree:true});
let tries=0;const wait=setInterval(()=>{maybeShow();if(++tries>=30||shown){clearInterval(wait)}},500);
window.addEventListener("pageshow",maybeShow);
})();
