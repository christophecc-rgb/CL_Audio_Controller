const fs=require('fs'),vm=require('vm'),assert=require('assert');
const script=fs.readFileSync('static/showcue-builder-access.js','utf8');
function node(text,id=''){return {textContent:text,id,disabled:false,style:{},attrs:{},setAttribute(k,v){this.attrs[k]=v},getAttribute(k){return this.attrs[k]}};}
for(const local of [true,false]){
 const save=node('ENREGISTRER'),details=node('Détails'),filter=node('','filter-phase'),edit=node('Modifier'),field=node('');field.contentEditable='true';
 const link=node('EXPORT');link.attrs.href='/show-info/builder/export.csv';
 const scope={dataset:{builderLocal:String(local)},addEventListener(){},querySelectorAll(q){return q.startsWith('button')?[save,details,filter,edit]:q==='[contenteditable]'?[field]:q==='a[href]'?[link]:[]}};
 const document={body:{},querySelector:()=>scope,getElementById:()=>null};
 vm.runInNewContext(script,{document,MutationObserver:class{observe(){}}});
 assert.equal(save.disabled,!local);assert.equal(edit.disabled,!local);assert.equal(details.disabled,false);assert.equal(filter.disabled,false);
 assert.equal(field.contentEditable,local?'true':'false');if(!local){assert.match(save.title,/poste local/);assert.equal(link.attrs['aria-disabled'],'true');}
}
console.log('Server-supplied local mode, remote controls disabled and consultation retained: passed');
