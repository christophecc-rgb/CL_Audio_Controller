/* One save barrier for downloads, imports and session navigation. */
(function () {
    if (window.clBuilderLifecycle) return;
    let busy = false;
    const status = text => {
        const node=document.getElementById('message');
        node.textContent=text;
        node.className='validation '+(/^(Export bloqué|Sauvegarde refusée)/.test(text)?'danger':text.startsWith('Fichier enregistré')?'ok':'muted');
    };
    const pending = () => builderEditVersion !== builderSavedVersion || builderPendingSaves > 0;
    async function flush() {
        if (preview) throw Error('Prévisualisation non adoptée : adoptez-la ou abandonnez-la avant cette opération.');
        if (!sessionId || !Number.isInteger(documentData.revision)) throw Error('Le Builder n’est pas chargé. Rechargez l’éditeur avant de continuer.');
        if(pending())await save();
        await builderSaveQueue;
        if (pending()) throw Error('Des modifications restent à sauvegarder. Réessayez.');
    }
    async function prepareNavigation() {
        if (preview) {
            if (!confirm('Prévisualisation non adoptée. L’abandonner et continuer ? Annuler pour rester.')) return false;
            // Do not turn a preview into a server document.
            return true;
        }
        try { await flush(); return true; }
        catch (error) {
            const captured=window.clBuilderDraft?.persist();
            const warning=captured===false?'Le brouillon local n’a pas pu être écrit.':'Les brouillons existants restent conservés.';
            status('Sauvegarde refusée : '+error.message);
            if (!confirm('Sauvegarde impossible : '+error.message+'\nAbandonner les modifications affichées et continuer ? Annuler pour rester. '+warning)) return false;
            clearTimeout(autosaveTimer);
            await builderSaveQueue.catch(()=>{});
            return true;
        }
    }
    async function operation(task) {
        if (busy) throw Error('Une opération est déjà en cours.');
        busy = true;
        const shell=document.querySelector('main.shell');
        if(shell)shell.inert=true;
        try { return await task(); }
        finally { if(shell)shell.inert=false;busy=false; }
    }
    function filename(response, url) {
        const disposition=response.headers.get('Content-Disposition')||'';
        const encoded=disposition.match(/filename\*=UTF-8''([^;]+)/i);
        if(encoded){try{return decodeURIComponent(encoded[1])}catch{}}
        const plain=disposition.match(/filename="([^"]+)"/i);
        return plain?plain[1]:url.endsWith('.csv')?'ShowCue_Builder.csv':url.endsWith('.xlsx')?'ShowCue_Builder.xlsx':'ShowCue.showcue';
    }
    async function download(url) {
        try { await operation(async()=>{
            await flush();
            const target=new URL(url,location.href);
            target.searchParams.set('session_id',sessionId);
            target.searchParams.set('revision',documentData.revision);
            const response=await fetch(target.pathname+target.search,{cache:'no-store'});
            if(!response.ok){const error=await response.json();throw Error(error.message||error.error||'Export refusé.');}
            const name=filename(response,url),blob=await response.blob();
            if(window.pywebview?.api?.save_export){
                const bytes=new Uint8Array(await blob.arrayBuffer());let binary='';
                for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
                const result=await window.pywebview.api.save_export(name,btoa(binary));
                if(result.status==='cancelled')status('Enregistrement annulé.');
                else if(result.status==='saved'&&result.path)status('Fichier enregistré : '+result.path);
                else throw Error(result.message||'Enregistrement impossible.');
            }else{
                const objectURL=URL.createObjectURL(blob),link=document.createElement('a');
                link.href=objectURL;link.download=name;document.body.append(link);link.click();link.remove();
                setTimeout(()=>URL.revokeObjectURL(objectURL),60000);
                status('Téléchargement demandé : '+name+'. Emplacement et dialogue selon les préférences du navigateur.');
            }
        }); }catch(error){status('Export bloqué : '+error.message);}
    }
    window.clBuilderLifecycle={flush,prepareNavigation,operation,download,canClose(){
        const captured=pending()?window.clBuilderDraft?.persist():true;
        const warning=captured===false?' Le brouillon local n’a pas pu être écrit.':' Les brouillons existants restent conservés.';
        return !busy&&(!(pending()||preview)||confirm('Des modifications ou une prévisualisation restent en attente. Fermer sans les enregistrer ?'+warning));
    }};
    document.addEventListener('click',event=>{
        const link=event.target.closest('a[href]');
        if(!link)return;
        const url=link.getAttribute('href');
        if(/^\/show-info\/builder\/(?:export\.(?:csv|xlsx)|sessions\/export)$/.test(url)){
            event.preventDefault();event.stopImmediatePropagation();void download(url);
        }else if(link.target!=='_blank'&&(pending()||preview)){
            event.preventDefault();event.stopImmediatePropagation();
            void operation(async()=>{if(await prepareNavigation()){window.clBuilderAllowUnload=true;location.assign(link.href)}}).catch(error=>status(error.message));
        }
    },true);
    document.addEventListener('keydown',event=>{
        if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='r'&&(pending()||preview)){
            event.preventDefault();
            void operation(async()=>{if(await prepareNavigation()){window.clBuilderAllowUnload=true;location.reload()}}).catch(error=>status(error.message));
        }
    });
    // All import previews preserve the edited show before replacing its tables.
    const request=api;
    api=async function(url,options={}){
        if(options.method==='POST'&&/^\/show-info\/builder\/import(?:-distribution|-pdf)?$/.test(url))return operation(async()=>{await flush();return request(url,options)});
        return request(url,options);
    };
})();
