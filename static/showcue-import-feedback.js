/* Presentation only: reuse import, adoption and save handlers. */
(function(){
 function install(){
  const input=document.getElementById('import'),adopt=document.getElementById('adopt');
  if(!input||!adopt)return;
  const panel=document.createElement('section');
  panel.id='cl-builder-import-feedback';panel.setAttribute('role','status');panel.setAttribute('aria-live','polite');panel.hidden=true;
  panel.style.cssText='margin:12px 0;padding:14px;border:1px solid #6684aa;border-left:4px solid #6684aa;border-radius:8px;background:#18202c;white-space:pre-wrap;overflow-wrap:anywhere;font-size:14px;line-height:1.5';
  document.querySelector('header.top').append(panel);
  const description=document.createElement('div');panel.append(description,adopt);
  const saveButton=document.createElement('button');saveButton.type='button';saveButton.textContent='ENREGISTRER LE BUILDER';saveButton.hidden=true;saveButton.onclick=()=>document.getElementById('save').click();panel.append(saveButton);
  adopt.style.cssText='margin-top:10px;min-height:44px;background:#28613d;border-color:#65ba82';
  let active=false,fileName='',format='',summary='';
  function show(title,detail,error=false){
   panel.hidden=false;description.textContent=title+'\n'+fileName+'\n'+detail;
   panel.style.borderColor=error?'#d66b71':'#6684aa';
  }
  const request=api;
  api=async function(url,options={}){
   if(url!=='/show-info/builder/import'){
    if(['/show-info/builder/import-distribution','/show-info/builder/import.pdf'].includes(url))window.clImportExplicitSave=false;
    return request(url,options);
   }
   try{
    const result=await request(url,options);
    window.clImportExplicitSave=true;saveButton.hidden=true;
    const unknown=result.unknown_columns||[];
    summary='✓ Fichier '+format+' lu\n'+(result.document?.cues?.length||0)+' cues détectés\n'+unknown.length+' colonnes inconnues'+(unknown.length?' : '+unknown.join(', '):'');
    const diagnostic=result.diagnostics||{};
    if(diagnostic.conduite){
     summary+='\nFeuille : '+diagnostic.conduite.sheet+' · En-têtes : ligne '+diagnostic.conduite.header_row;
    }
    if(diagnostic.encoding)summary+='\nEncodage : '+diagnostic.encoding;
    if(diagnostic.separator)summary+=' · Séparateur : '+(diagnostic.separator==='\t'?'tabulation':diagnostic.separator);
    for(const warning of diagnostic.warnings||[])summary+='\n⚠ '+warning;
    show('PRÉVISUALISATION PRÊTE',summary+'\nAucune modification enregistrée pour l’instant.\nAdoptez dans le Builder, puis enregistrez.');
    return result;
   }catch(error){
    show('ERREUR D’IMPORT '+format,error.message+'\nFormat attendu : XLSX ou CSV',true);throw error;
   }
  };
  const importFile=input.onchange;
  input.onchange=async function(event){
   const file=event.target.files[0];if(!file)return;
   active=true;fileName=file.name;format=file.name.toLowerCase().endsWith('.csv')?'CSV':'XLSX';summary='';
   show('FICHIER SÉLECTIONNÉ','Analyse du fichier en cours…');
   return importFile.call(this,event);
  };
  adopt.textContent='ADOPTER DANS LE BUILDER';
  const adoption=adopt.onclick;
  adopt.onclick=function(event){
   const result=adoption.call(this,event);
   saveButton.hidden=false;
   if(active)show('✓ IMPORT ADOPTÉ DANS LE BUILDER',summary+'\nModifications non encore sauvegardées. Cliquez ENREGISTRER LE BUILDER.');
   return result;
  };
  const saveStatus=setSaveState;
  setSaveState=function(value,error=false){
   saveStatus(value,error);
   if(!active){
    if(value.startsWith('PRÉVISUALISATION')){panel.hidden=false;description.textContent='PRÉVISUALISATION DISPONIBLE\nAdoptez puis enregistrez explicitement le Builder.';saveButton.hidden=true;}
    return;
   }
   if(value==='BUILDER SAUVEGARDÉ')show('✓ BUILDER SAUVEGARDÉ',summary+'\nSauvegarde terminée. La conduite ShowCue reste inchangée.');
   else if(value==='SAUVEGARDE DU BUILDER…')show('SAUVEGARDE EN COURS',summary);
   else if(value==='MODIFICATIONS EN COURS')show('MODIFICATIONS NON SAUVEGARDÉES',summary);
   else if(error)show('ERREUR DE SAUVEGARDE',value+'\n'+summary,true);
  };
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();
