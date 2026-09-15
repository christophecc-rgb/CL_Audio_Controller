// Run with: node --test tests/js/test_showcue_mobile_conduite.js
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../static/showcue-stage.js'), 'utf8')
  .split('/* ShowCue mobile conduite:')[1];

function setup() {
  class Element {
    constructor(tag = 'div') {
      this.tagName = tag; this.children = []; this.dataset = {}; this.events = {};
      this.attributes = {}; this.className = ''; this.value = ''; this.hidden = false;
      this.style = {setProperty() {}};
      this.classList = {
        contains: name => this.className.split(' ').includes(name),
        add: name => { if (!this.classList.contains(name)) this.className += ' ' + name; },
        remove: name => { this.className = this.className.split(' ').filter(x => x !== name).join(' '); },
        toggle: (name, active) => active ? this.classList.add(name) : this.classList.remove(name),
      };
    }
    append(...children) {
      this.children.push(...children);
      if (this.tagName === 'select' && !this.value) this.value = children[0]?.value;
    }
    after() {}
    replaceChildren(...children) { this.children = children; }
    setAttribute(name, value) { this.attributes[name] = value; }
    addEventListener(name, fn) { (this.events[name] ||= []).push(fn); }
    emit(name, event = {}) { for (const fn of this.events[name] || []) fn(event); }
    get options() { return this.children; }
    getBoundingClientRect() { return {height: 70}; }
    showModal() { this.open = true; }
    close() { this.open = false; this.emit('close'); }
    closest(selector) { return selector === '.stage-mobile-cue' && this.classList.contains('stage-mobile-cue') ? this : null; }
  }
  const ids = Object.fromEntries(['view-conduite','timed-sequence','section-filters','add-cue'].map(id => [id,new Element()]));
  ids['view-conduite'].classList.add('active');
  const nav = new Element(), body = new Element(), window = new Element();
  const mobile = new Element(); mobile.matches = true;
  window.matchMedia = () => mobile; window.scrollY = 0; window.innerHeight = 600;
  const postEl = new Element(); postEl.value = 'LUMIERE';
  const calls = []; let now = 0; let baseRow;
  const context = {
    document: {body, documentElement: {scrollHeight: 2000}, createElement: tag => new Element(tag),
      getElementById: id => ids[id], querySelector: () => nav},
    window, postEl, performance: {now: () => now},
    ResizeObserver: class {observe() {}},
    Option: function(text, value) {const el = new Element('option'); el.textContent = text; el.value = value; return el;},
    destinationLabels: {FOH:'FOH',RETOURS:'RET',PLATEAU:'PLT',LUMIERE:'LUM'},
    snapshot: {active_session_id:'session-a',title:'HOLLOBACK GIRL',elapsed_seconds:25,scene_duration_seconds:173,remaining_seconds:148},
    cueLine(cue) {baseRow = new Element(); baseRow.dataset.cueId = cue.id; baseRow.draggable = true; baseRow.ondragstart = () => {}; return baseRow;},
    interactionActive: () => false, renderSequence() {}, sectionFilter:'SHOW', setView() {}, render() {},
    isTimecode: value => /^\d{2}:\d{2}:\d{2}:\d{2}$/.test(value || ''),
    formatSeconds: value => String(value), scoped: (value, sessionId) => ({...value,session_id:sessionId}),
    api: async (url, args) => { calls.push([url,JSON.parse(args.body)]); }, refresh: async () => {}, openEditor() {},
    conduiteOrderedCues: () => [cue],
  };
  const cue = {id:'cue-a',status:'official',mode:'timed',timecode:'18:41:01:06',text:'HOLLOBACK GIRL',posts:['LUMIERE']};
  vm.createContext(context);
  vm.runInContext('/* ShowCue mobile conduite:' + source, context);
  const dialog = body.children.find(el => el.tagName === 'dialog');
  const click = row => ids['view-conduite'].emit('click',{target:row,stopImmediatePropagation(){},preventDefault(){}});
  const pointer = (name,row,x=0,y=0) => (['pointerup','pointercancel'].includes(name) ? window : ids['timed-sequence']).emit(name,{target:row,isPrimary:true,button:0,pointerId:1,clientX:x,clientY:y});
  return {context,cue,mobile,ids,dialog,nav,window,calls,postEl,click,pointer,setNow: value => now=value,baseRow:()=>baseRow};
}

test('mobile summaries use business posts and unknown assignments stay visible', () => {
  const s=setup();
  for (const [posts,label,hidden] of [
    [['PLATEAU','LUMIERE'],'PLT · LUM',false],
    [['FOH','RETOURS','PLATEAU','LUMIERE'],'TOUT',false],
    [['FOH'],'FOH',true], [undefined,'POSTES ?',false], [[], 'POSTES ?',false],
    [['FOH','UNKNOWN'],'POSTES ?',false],
  ]) {
    const row=s.context.cueLine({...s.cue,posts},'');
    assert.equal(row.children[2].textContent,label);
    assert.equal(row.hidden,hidden);
    assert.equal(row.children.length,3);
    assert.equal(row,s.baseRow());
    assert.equal(typeof row.ondragstart,'function');
  }
});

test('tap opens, scroll-return, long press, cancel and native drag do not', () => {
  const s=setup(), row=s.context.cueLine(s.cue,'');
  s.pointer('pointerdown',row); s.pointer('pointerup',row); s.click(row);
  assert.equal(s.dialog.open,true); s.dialog.close();
  s.pointer('pointerdown',row); s.pointer('pointermove',row,0,30); s.pointer('pointerup',row); s.click(row);
  assert.equal(s.dialog.open,false);
  s.pointer('pointerdown',row); s.setNow(500); s.pointer('pointerup',row); s.click(row);
  assert.equal(s.dialog.open,false);
  s.pointer('pointerdown',row); s.pointer('pointercancel',row); s.click(row);
  assert.equal(s.dialog.open,false);
  s.pointer('pointerdown',row); s.ids['timed-sequence'].emit('dragstart'); s.ids['timed-sequence'].emit('dragend'); s.click(row);
  assert.equal(s.dialog.open,false);
});

test('role changes remain local until save and keep the opening session', async () => {
  const s=setup(), row=s.context.cueLine(s.cue,'');
  s.click(row);
  const options=s.dialog.children[2], actions=s.dialog.children[4];
  options.children.find(el=>el.dataset.post==='PLATEAU').onclick();
  actions.children.find(el=>el.textContent==='ANNULER').onclick();
  assert.equal(s.calls.length,0);
  assert.deepEqual(s.cue.posts,['LUMIERE']);
  s.click(row);
  options.children.find(el=>el.dataset.post==='PLATEAU').onclick();
  s.context.snapshot.active_session_id='session-b';
  await actions.children.find(el=>el.textContent==='TERMINER').onclick();
  assert.deepEqual(s.calls,[['/show-info/cues/cue-a',{posts:['PLATEAU','LUMIERE'],session_id:'session-a'}]]);
});

test('desktop rows remain untouched; navigation restores on upward scroll and view changes', () => {
  const s=setup(); s.mobile.matches=false;
  const row=s.context.cueLine(s.cue,'');
  assert.equal(row.children.length,0);
  s.mobile.matches=true;
  s.window.scrollY=200; s.window.emit('scroll'); assert.equal(s.nav.classList.contains('stage-nav-hidden'),true);
  s.window.scrollY=199; s.window.emit('scroll'); assert.equal(s.nav.classList.contains('stage-nav-hidden'),false);
  s.window.scrollY=220; s.window.emit('scroll'); s.context.setView('live');
  assert.equal(s.nav.classList.contains('stage-nav-hidden'),false);
  assert.equal(s.context.sectionFilter,'SHOW');
});
