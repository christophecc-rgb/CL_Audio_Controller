/* One scroll region, sized to the visible viewport above the iOS keyboard. */
(() => {
  'use strict';
  const mobile=window.matchMedia('(max-width: 760px), (pointer: coarse) and (max-width: 950px)');
  const viewport=window.visualViewport;
  const root=document.documentElement;
  const dialogs=[];
  let frame=null;
  function update(){
    frame=null;
    root.style.setProperty('--cl-editor-height',`${viewport?.height||window.innerHeight}px`);
    root.style.setProperty('--cl-editor-top',`${viewport?.offsetTop||0}px`);
    root.style.setProperty('--cl-editor-width',`${viewport?.width||window.innerWidth}px`);
    root.style.setProperty('--cl-editor-left',`${viewport?.offsetLeft||0}px`);
    for(const {dialog,form,body,footer,deleteButton,deleteZone} of dialogs){
      dialog.classList.toggle('cl-mobile-editor',mobile.matches);
      if(deleteButton){
        if(mobile.matches)deleteZone.append(deleteButton);
        else if(deleteButton.parentNode!==footer)footer.prepend(deleteButton);
      }
      if(mobile.matches&&dialog.open){
        const active=document.activeElement;
        if(body.contains(active)){
          const field=active.getBoundingClientRect(),region=body.getBoundingClientRect();
          if(field.bottom>region.bottom)body.scrollTop+=field.bottom-region.bottom+8;
          if(field.top<region.top)body.scrollTop-=region.top-field.top+8;
        }
      }
    }
  }
  function schedule(){if(frame===null)frame=requestAnimationFrame(update);}
  function setup(){
    for(const id of ['editor','quick-editor','stage-notes-editor']){
      const dialog=document.getElementById(id);
      if(!dialog||dialog.dataset.mobileViewportReady)continue;
      const form=dialog.querySelector('form');
      const footer=form?.querySelector('.actions,.stage-notes-editor-actions');
      if(!form||!footer)continue;
      dialog.dataset.mobileViewportReady='true';
      const heading=form.querySelector('h2,.stage-notes-editor-title');
      const body=document.createElement('div');body.className='cl-editor-body';
      // Keep IDs and form controls intact; desktop uses display:contents.
      for(const child of [...form.children])if(child!==heading&&child!==footer)body.append(child);
      form.insertBefore(body,footer);
      // Keep failure messages visible without scrolling through all cue fields.
      const error=form.querySelector('.error,.stage-notes-editor-error');
      if(error)form.insertBefore(error,footer);
      const deleteButton=footer.querySelector('.delete-action');
      const deleteZone=document.createElement('div');deleteZone.className='cl-editor-delete';
      if(deleteButton)body.append(deleteZone);
      dialogs.push({dialog,form,body,footer,deleteButton,deleteZone});
      const showModal=dialog.showModal.bind(dialog);
      dialog.showModal=function(){update();showModal();body.scrollTop=0;schedule();};
      dialog.addEventListener('close',schedule);
      form.addEventListener('focusin',schedule);
    }
    schedule();
  }
  viewport?.addEventListener('resize',schedule);
  viewport?.addEventListener('scroll',schedule);
  window.addEventListener('resize',schedule);
  window.addEventListener('orientationchange',schedule);
  mobile.addEventListener('change',schedule);
  // The Live notes dialog is created lazily after the page loads.
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{
    setup();new MutationObserver(setup).observe(document.body,{childList:true});
  });
  else{setup();new MutationObserver(setup).observe(document.body,{childList:true});}
})();
