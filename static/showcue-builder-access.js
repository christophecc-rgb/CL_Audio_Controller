/* The server supplies locality; this only explains/enforces the UI mode. */
(function(){
 const shell=document.querySelector('main.shell');
 if(!shell||shell.dataset.builderLocal==='true')return;
 const reason='Disponible uniquement sur le poste local';
 function consultable(node){
  return node.id?.startsWith('filter-')||(node.textContent?.trim()==='Détails'||node.getAttribute('aria-label')==='Détails')||node.textContent?.trim()==='Fermer'||node.id==='cl-builder-sessions-open';
 }
 function update(){
  const scopes=[shell,document.getElementById('cue-panel'),document.getElementById('cl-builder-sessions-dialog')].filter(Boolean);
  for(const scope of scopes){
  for(const node of scope.querySelectorAll('button,input,select,textarea')){
   if(consultable(node))continue;
   if(!node.disabled)node.disabled=true;node.title=reason;if(node.getAttribute('aria-disabled')!=='true')node.setAttribute('aria-disabled','true');
  }
  for(const node of scope.querySelectorAll('[contenteditable]'))if(node.contentEditable!=='false')node.contentEditable='false';
  for(const node of scope.querySelectorAll('a[href]')){
   if(!node.getAttribute('href').startsWith('/show-info/builder/'))continue;
   if(node.getAttribute('aria-disabled')!=='true')node.setAttribute('aria-disabled','true');node.title=reason;node.style.opacity='.5';
  }
  for(const node of scope.querySelectorAll('[draggable="true"]'))node.draggable=false;
  }
 }
 shell.addEventListener('click',event=>{
  const node=event.target.closest('button,a,input');
  if(node?.getAttribute('aria-disabled')==='true'){event.preventDefault();event.stopImmediatePropagation();}
 },true);
 shell.addEventListener('dragstart',event=>event.preventDefault(),true);
 new MutationObserver(update).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['disabled','contenteditable','draggable']});update();
})();
