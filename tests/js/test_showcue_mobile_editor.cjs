const fs=require('fs'),vm=require('vm'),assert=require('assert');
const css=fs.readFileSync('static/showcue-mobile-editor.css','utf8');
assert.match(css,/font-size:\s*16px\s*!important/);assert.match(css,/min-height:\s*44px\s*!important/);
assert.match(css,/100dvh/);assert.match(css,/safe-area-inset-bottom/);assert.match(css,/\.cl-editor-body \{ display: contents;/);
class Element{
 constructor(name){this.name=name;this.children=[];this.dataset={};this.listeners={};this.scrollTop=0;this.classList={toggle:(name,value)=>{this.mobile=value}};}
 append(child){if(child.parentNode)child.parentNode.children=child.parentNode.children.filter(x=>x!==child);this.children.push(child);child.parentNode=this;}
 prepend(child){this.append(child);this.children=[child,...this.children.filter(x=>x!==child)];}
 insertBefore(child,anchor){this.append(child);this.children=this.children.filter(x=>x!==child);this.children.splice(this.children.indexOf(anchor),0,child);}
 addEventListener(event,callback){this.listeners[event]=callback;}
 contains(child){return this===child||this.children.some(node=>node.contains(child));}
 getBoundingClientRect(){return {top:40,bottom:240};}
 querySelector(selector){if(selector==='form')return form;if(selector.includes('actions'))return footer;if(selector.includes('h2'))return title;if(selector==='.delete-action')return del;}
}
const dialog=new Element('dialog'),form=new Element('form'),title=new Element('title'),field=new Element('field'),footer=new Element('footer'),del=new Element('delete');
form.append(title);form.append(field);form.append(footer);footer.append(del);dialog.showModal=()=>{dialog.open=true};
const styles={},events={},media={matches:true,addEventListener(event,callback){this.change=callback}},viewport={height:844,width:390,offsetTop:0,offsetLeft:0,addEventListener(event,callback){events[event]=callback}};
let frames=[];const context={document:{readyState:'complete',documentElement:{style:{setProperty:(name,value)=>styles[name]=value}},body:new Element('body'),getElementById:id=>id==='editor'?dialog:null,createElement:name=>new Element(name),activeElement:null},window:{matchMedia:()=>media,visualViewport:viewport,innerHeight:844,innerWidth:390,addEventListener(event,callback){events[event]=callback}},MutationObserver:class{observe(){}},requestAnimationFrame:callback=>{frames.push(callback);return frames.length}};
vm.createContext(context);vm.runInContext(fs.readFileSync('static/showcue-mobile-editor.js','utf8'),context);
const flush=()=>{const pending=frames;frames=[];pending.forEach(callback=>callback());};flush();dialog.showModal();flush();
assert.equal(styles['--cl-editor-height'],'844px');assert(dialog.mobile);assert.equal(del.parentNode.className,'cl-editor-delete');
viewport.height=350;viewport.offsetTop=24;events.resize();flush();assert.equal(styles['--cl-editor-height'],'350px');assert.equal(styles['--cl-editor-top'],'24px');
viewport.height=210;viewport.width=844;events.orientationchange();flush();assert.equal(styles['--cl-editor-height'],'210px');assert.equal(styles['--cl-editor-width'],'844px');
media.matches=false;media.change();flush();assert(!dialog.mobile);assert.equal(del.parentNode,footer);
console.log('Mobile portrait, keyboard resize, landscape/rotation and desktop restoration: passed');
