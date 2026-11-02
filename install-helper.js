(() => {
"use strict";
const isIOS=/iphone|ipad|ipod/i.test(navigator.userAgent)||(navigator.platform==="MacIntel"&&navigator.maxTouchPoints>1);
const isAndroid=/android/i.test(navigator.userAgent);
const isStandalone=()=>window.matchMedia("(display-mode: standalone)").matches||window.matchMedia("(display-mode: fullscreen)").matches||navigator.standalone===true;
const inAppBrowser=/Gmail|FBAN|FBAV|Instagram|LinkedInApp|Outlook/i.test(navigator.userAgent)||(/Android/i.test(navigator.userAgent)&&/; wv\)/i.test(navigator.userAgent));
let deferredPrompt=null;
const style=document.createElement("style");
style.textContent="#romano-install-entry{position:fixed;z-index:10050;right:16px;bottom:16px;border:1px solid #d2b477;border-radius:999px;padding:13px 19px;background:linear-gradient(135deg,#f4dfb2,#c59a52);color:#241d12;font:700 14px system-ui,-apple-system,sans-serif;box-shadow:0 8px 28px #0004;cursor:pointer}#romano-install-entry:focus-visible,#romano-install-dialog button:focus-visible{outline:3px solid #8b6428;outline-offset:3px}#romano-install-dialog{position:fixed;z-index:10060;inset:0;background:#111a;display:grid;place-items:center;padding:18px}#romano-install-dialog[hidden],#romano-install-entry[hidden]{display:none}#romano-install-dialog .ri-card{width:min(440px,100%);max-height:88vh;overflow:auto;background:#fffdf8;color:#211f1a;border:1px solid #dfcfb2;border-radius:22px;padding:24px;box-shadow:0 24px 80px #0005;font:14px/1.5 system-ui,-apple-system,sans-serif}#romano-install-dialog h2{font:700 23px Georgia,serif;margin:0 0 8px}#romano-install-dialog p{margin:8px 0;color:#514b40}#romano-install-dialog ol{padding-left:22px;margin:12px 0}#romano-install-dialog li{margin:8px 0}#romano-install-dialog .ri-actions{display:flex;gap:9px;flex-wrap:wrap;margin-top:18px}#romano-install-dialog button{border:0;border-radius:999px;padding:11px 16px;font-weight:700;cursor:pointer}#romano-install-dialog .ri-primary{background:#1c1c19;color:#fff}#romano-install-dialog .ri-secondary{background:#eee5d6;color:#342b1d}@media(max-width:520px){#romano-install-entry{right:12px;bottom:12px;padding:12px 16px}}";
document.head.appendChild(style);
const button=document.createElement("button");button.id="romano-install-entry";button.type="button";button.textContent="↓ Instalar ROMANO";button.setAttribute("aria-label","Instalar ROMANO PROPERTY CARE no telemóvel");document.body.appendChild(button);
const modal=document.createElement("div");modal.id="romano-install-dialog";modal.hidden=true;
modal.innerHTML="<section class=\"ri-card\" role=\"dialog\" aria-modal=\"true\" aria-labelledby=\"ri-title\"><h2 id=\"ri-title\">Tenha a ROMANO no ecrã inicial</h2><p id=\"ri-intro\">Adicione a aplicação ao telemóvel para a abrir diretamente pelo ícone.</p><div id=\"ri-instructions\"></div><div class=\"ri-actions\"><button type=\"button\" class=\"ri-primary\" id=\"ri-copy\">Copiar endereço</button><button type=\"button\" class=\"ri-secondary\" id=\"ri-close\">Fechar</button></div></section>";
document.body.appendChild(modal);
const instructions=modal.querySelector("#ri-instructions");
const close=()=>{modal.hidden=true;};
modal.querySelector("#ri-close").addEventListener("click",close);
modal.addEventListener("click",e=>{if(e.target===modal)close();});
document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!modal.hidden)close();});
modal.querySelector("#ri-copy").addEventListener("click",async()=>{
 try{await navigator.clipboard.writeText(location.origin+location.pathname);modal.querySelector("#ri-copy").textContent="Endereço copiado ✓";}
 catch(_){const field=document.createElement("textarea");field.value=location.href;modal.querySelector(".ri-card").appendChild(field);field.select();try{document.execCommand("copy");}catch(__){}field.remove();modal.querySelector("#ri-copy").textContent="Tente copiar o endereço da barra";}
});
function showGuide(){
 modal.hidden=false;modal.querySelector("#ri-copy").textContent="Copiar endereço";
 const actions=modal.querySelector(".ri-actions");const old=actions.querySelector("#ri-install-now");if(old)old.remove();
 if(isIOS){
  modal.querySelector("#ri-intro").textContent="No iPhone ou iPad, a instalação deve ser confirmada no Safari.";
  instructions.innerHTML="<ol><li>Se abriu dentro do Gmail, Outlook ou outro aplicativo, escolha <b>Abrir no Safari</b> no menu de partilha ou opções.</li><li>No Safari, toque no botão <b>Partilhar</b> (quadrado com seta para cima).</li><li>Desça a lista e escolha <b>Adicionar ao ecrã principal</b>.</li><li>Confirme em <b>Adicionar</b>. O ícone ROMANO ficará no ecrã inicial.</li></ol><p><b>Nota:</b> se a opção não aparecer, procure em “Editar ações” na lista de partilha.</p>";
 }else if(isAndroid&&deferredPrompt){
  modal.querySelector("#ri-intro").textContent="O seu navegador permite instalar a aplicação diretamente.";
  instructions.innerHTML="<p>Toque em <b>Instalar agora</b> e confirme a instalação apresentada pelo Android.</p>";
  const installNow=document.createElement("button");installNow.id="ri-install-now";installNow.className="ri-primary";installNow.textContent="Instalar agora";installNow.addEventListener("click",triggerInstall);actions.prepend(installNow);
 }else if(isAndroid){
  modal.querySelector("#ri-intro").textContent="O navegador ainda não disponibilizou a instalação automática. Pode adicionar o atalho pelo menu.";
  instructions.innerHTML="<ol><li>Abra este endereço no <b>Chrome</b> ou no navegador principal do telemóvel (não dentro do Gmail/Outlook).</li><li>Toque no menu <b>⋮</b> no canto superior.</li><li>Escolha <b>Instalar aplicação</b> ou <b>Adicionar ao ecrã inicial</b>.</li><li>Confirme a opção apresentada.</li></ol>";
 }else{
  modal.querySelector("#ri-intro").textContent="Use o menu do navegador para instalar ou criar um atalho.";
  instructions.innerHTML="<ol><li>Abra o endereço no navegador principal.</li><li>Procure no menu a opção <b>Instalar aplicação</b> ou <b>Adicionar ao ecrã inicial</b>.</li><li>Confirme a operação.</li></ol>";
 }
 if(inAppBrowser){const note=document.createElement("p");note.innerHTML="<b>Está num navegador interno de e-mail ou de outra aplicação.</b> A instalação pode não funcionar aqui. Abra o endereço no Safari (iPhone) ou Chrome (Android) e repita os passos.";instructions.prepend(note);}
}
async function triggerInstall(){
 if(!deferredPrompt){showGuide();return;}
 const prompt=deferredPrompt;deferredPrompt=null;
 try{await prompt.prompt();await prompt.userChoice;}catch(_){}
 modal.hidden=true;refreshButton();
}
function refreshButton(){button.hidden=isStandalone();if(isStandalone())modal.hidden=true;}
window.addEventListener("beforeinstallprompt",event=>{event.preventDefault();deferredPrompt=event;refreshButton();});
window.addEventListener("appinstalled",()=>{deferredPrompt=null;refreshButton();});
button.addEventListener("click",()=>{if(isAndroid&&deferredPrompt)triggerInstall();else showGuide();});
window.installRomanoApp=()=>{if(isAndroid&&deferredPrompt)return triggerInstall();showGuide();};
window.addEventListener("pageshow",refreshButton);window.addEventListener("focus",refreshButton);document.addEventListener("visibilitychange",refreshButton);refreshButton();
})();