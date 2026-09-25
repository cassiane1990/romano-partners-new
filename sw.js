const CACHE="romano-pwa-v7";
const CORE=["/","/index.html","/manifest.json","/icon.svg"];
self.addEventListener("install",event=>{event.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",event=>{
 const req=event.request;
 if(req.method!=="GET")return;
 if(new URL(req.url).origin!==self.location.origin)return;
 const isNavigation=req.mode==="navigate"||req.destination==="document";
 event.respondWith(
   fetch(req,{cache:"no-store"}).then(res=>{
     const copy=res.clone();
     caches.open(CACHE).then(c=>c.put(req,copy));
     return res;
   }).catch(()=>caches.match(req).then(x=>x||caches.match("/index.html")))
 );
});
self.addEventListener("push",event=>{
 let data={};
 try{data=event.data?.json()||{}}catch(e){data={body:event.data?.text()||"Nueva alerta"}}
 const n=data.notification||data;
 const title=n.title||data.title||"ROMANO PROPERTY CARE";
 const options={body:n.body||data.body||"Nueva alerta",icon:n.icon||data.icon||"/icon.svg",badge:n.badge||data.badge||"/icon.svg",tag:n.tag||data.tag||"romano-alert",renotify:true,data:{url:n.navigate||data.url||"/"},silent:n.silent===true,vibrate:[200,100,200]};
 event.waitUntil(self.registration.showNotification(title,options));
});
self.addEventListener("notificationclick",event=>{
 event.notification.close();
 const target=new URL(event.notification.data?.url||"/",self.location.origin).href;
 event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{
   const existing=list.find(c=>c.url.startsWith(self.location.origin));
   if(existing){existing.focus();existing.navigate(target);return}
   return clients.openWindow(target);
 }));
});
self.addEventListener("notificationclose",()=>{});