const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync('static/showcue-sessions.js', 'utf8');
const state = {active: 'session_initiale', sessions: [{id:'session_initiale',name:'Session actuelle'}], documents: {session_initiale: {revision:6,cues:[]}}, calls:[], reloads:0};
function element() { return {children:[], value:'', append(...x){this.children.push(...x)}, replaceChildren(){this.children=[]}, remove(){}, closest(){return this}}; }
function page() {
    const elements = Object.fromEntries(['cl-session-upload','cl-saved-sessions','cl-open-session','cl-import-result','cl-session-archives','cl-libraries','session'].map(id=>[id,element()]));
    const context = {document:{getElementById:id=>elements[id],createElement:element,querySelector:element}, console, Uint8Array, String, JSON, Error, encodeURIComponent,
        FormData: class {append(key,value){this[key]=value}},
        location:{reload(){state.reloads++}}, preview:null, sessionId:state.active, documentData:state.documents[state.active], render(){},showValidation(){},
        btoa: x=>Buffer.from(x,'binary').toString('base64'),
        fetch: async()=>({ok:true,arrayBuffer:async()=>new Uint8Array([1,2]).buffer}),
        pywebview:{api:{recover_builder:async(_,doc)=>({ok:true,document:{...doc,cues:Array.from({length:16},(_,i)=>({id:'b'+i}))}})}}};
    context.window=context;
    context.api=async(url,options={})=>{
        state.calls.push([url,options.method]);
        if(url==='/show-info/sessions') return {ok:true,active_session_id:state.active,sessions:state.sessions};
        if(url==='/show-info/builder/resources') return {ok:true,sessions:[],libraries:{}};
        if(url==='/show-info/builder/document') {
            if(options.method==='PUT'){
                const data=JSON.parse(options.body); assert.equal(data.session_id,state.active);
                assert.equal(data.document.revision,state.documents[state.active].revision);
                state.documents[state.active]={...data.document,revision:data.document.revision+1};
            }
            return {ok:true,session_id:state.active,document:state.documents[state.active],validation:{}};
        }
        if(url==='/show-info/builder/sessions/import'){
            const file=options.body.file;
            const id='session_'+file.name;
            const item={id,name:file.name};state.sessions.push(item);
            state.documents[id]={revision:file.revision,cues:Array(file.count).fill({})};
            return {ok:true,imported_session:item};
        }
        if(url.endsWith('/activate')){state.active=url.split('/')[3];return {ok:true};}
        throw Error(url);
    };
    return {context:vm.createContext(context),elements};
}
(async()=>{
    let p=page(); await vm.runInContext(script,p.context);
    assert.equal(state.documents.session_initiale.cues.length,16);
    assert.equal(p.context.documentData.cues.length,16);
    for(const file of [{name:'OP',revision:341,count:134},{name:'MPC',revision:30,count:56}]){
        state.calls=[];
        await p.elements['cl-session-upload'].onchange({target:{files:[file],value:'file'}});
        assert.equal(state.active,'session_'+file.name);
        assert(!state.calls.some(([url,method])=>url==='/show-info/builder/document'&&method==='PUT'), 'No save of current Builder during import');
        p=page(); await vm.runInContext(script,p.context);
    }
    assert.equal(state.reloads,2);
    assert.equal(p.elements['cl-saved-sessions'].children.length,3);
    p.elements['cl-saved-sessions'].value='session_OP';
    await p.elements['cl-open-session'].onclick();
    assert.equal(state.active,'session_OP');
    p=page();await vm.runInContext(script,p.context);
    await assert.rejects(()=>p.context.api('/show-info/builder/document',{method:'PUT',body:JSON.stringify({document:{cues:[]}})}),/Builder vide refusé/);
    assert.equal(state.documents.session_OP.cues.length,134);
    assert.equal(state.documents.session_MPC.cues.length,56);
    // Reinjection is idempotent on a new server that already loaded the script.
    const count=p.elements['cl-saved-sessions'].children.length;
    await vm.runInContext(script,p.context);
    assert.equal(p.elements['cl-saved-sessions'].children.length,count);
    console.log('PASS: legacy desktop recovery, OP/MPC import, reload, selector, empty-save guard, idempotence');
})().catch(error=>{console.error(error);process.exitCode=1});
