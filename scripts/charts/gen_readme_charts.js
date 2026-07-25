#!/usr/bin/env node
// gen_charts.js — render the lieflat-charts Lupi Basics templates to static SVG.
// The render bodies below are the gallery implementations (F1 rung bars, F4 tick donut,
// F5 tick rows, F9 rung waterfall, F12 dumbbell queue) with data swapped; the geometry,
// unit encoding, tick cadence and jitter are the template's, not re-invented.
const fs = require('fs');
const path = require('path');
const OUT = process.argv[2] || '.';

// ── minimal SVG DOM shim so the gallery's el()/txt() run unchanged ────────────────────
const esc = s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
class N {
  constructor(t){ this.t=t; this.a={}; this.kids=[]; this.text=null; }
  setAttribute(k,v){ this.a[k]=v; }
  appendChild(n){ this.kids.push(n); return n; }
  get outer(){
    const at = Object.entries(this.a).map(([k,v])=>` ${k}="${esc(v)}"`).join('');
    const inner = (this.text!==null?esc(this.text):'') + this.kids.map(k=>k.outer).join('');
    return `<${this.t}${at}>${inner}</${this.t}>`;
  }
}
global.document = { createElementNS:(_,t)=>new N(t) };

// ── shared Mono tokens (gallery-identical) ───────────────────────────────────────────
const INK='#1C1C1A',PAPER='#F0EFEB',MUTED='#8F8E88',GRID='#DEDDD6';
const el=(p,t,a)=>{const n=document.createElementNS(0,t);for(const k in a)n.setAttribute(k,a[k]);p.appendChild(n);return n};
const txt=(p,a,s)=>{const n=el(p,'text',a);n.text=s;return n};
const tip=(n,s)=>{const t=document.createElementNS(0,'title');t.text=s;n.appendChild(t)};
const rnd=(i,k)=>Math.abs(((i*73856093)^(k*19349663))%1000)/1000;
const D2R=Math.PI/180;
const pol=(cx,cy,r,deg)=>[cx+r*Math.cos(deg*D2R),cy+r*Math.sin(deg*D2R)];

// README assets are IMAGES, so they must be legible with no animation running at all. The gallery's
// `.fade`/`.pop` use animation-fill-mode `both` over `from{opacity:0}`, which parks every element at
// opacity 0 until an animation runs — a static rasteriser (and any export path) renders a blank card.
// The geometry, unit encoding, ladder shades and jitter are the template's, untouched; only the
// reveal choreography is dropped, and it is restored in the interactive HTML build.
const CSS = `<style>
  text{font-family:Inter,-apple-system,'Helvetica Neue',Arial,sans-serif}
</style>`;
const STRIP = /\s(?:class|style)="[^"]*"/g;

function card({file, title, sub, src, h=352, draw}){
  const root = new N('svg');
  root.setAttribute('xmlns','http://www.w3.org/2000/svg');
  root.setAttribute('viewBox',`0 0 400 ${h}`);
  root.setAttribute('width','400'); root.setAttribute('height',String(h));
  root.setAttribute('font-family','Inter,-apple-system,Helvetica Neue,Arial,sans-serif');
  el(root,'rect',{x:0,y:0,width:400,height:h,fill:PAPER});
  txt(root,{x:20,y:26,'font-size':13.5,'font-weight':700,fill:INK,'letter-spacing':'-.02em'},title);
  txt(root,{x:20,y:41,'font-size':8.5,fill:MUTED},sub);
  const g = el(root,'g',{transform:'translate(0,26)'});
  draw(g);
  txt(root,{x:20,y:h-9,'font-size':7,'font-weight':600,fill:'#B0AFA9','letter-spacing':'.1em'},src);
  const out = root.outer.replace(STRIP,'').replace('>', '>'+CSS);
  fs.writeFileSync(path.join(OUT,file), out+'\n');
  console.log(`  ${file}  ${out.length} B`);
}

// ═════ 1 · F12 dumbbell queue — mechanical phase, before vs after ════════════════════
// template: C8 · dumbbell queue. one bead = 500 ms saved · hollow = baseline · ink = now
card({
  file:'perf-phase.svg',
  title:'The mechanical phase, before and after',
  sub:'one bead = 500 ms saved · hollow = 31dbda2 · ink = v2.2 · PanicCamp, 823 files, 20 symbols',
  src:'DUMBBELL QUEUE · MONO-BASIC · STEP-1 TIMING',
  h:250,
  draw(s){
    // The review-packet step is NOT plotted: it was never touched, and its 89 ms -> 93 ms is measurement
    // noise. A row drifting rightward would read as a regression and would break this template's premise
    // that every row moves left. It is stated in the caption instead.
    const D=[['CALLER SEARCH',8250,101],['MAP BUILD',1727,249]];
    const y0=i=>52+i*58,X0=132,X1=366,MAXV=8400,mapX=v=>X0+(v/MAXV)*(X1-X0);
    D.forEach(([name,was,now],i)=>{
      const y=y0(i),xa=mapX(was),xb=mapX(now);
      txt(s,{x:122,y:y+3,'font-size':7.5,'font-weight':700,fill:'#6A6963','text-anchor':'end',
        'letter-spacing':'.06em',class:'fade',style:`animation-delay:${i*.08}s`},name);
      el(s,'line',{x1:X0-6,y1:y,x2:X1+6,y2:y,stroke:'#E3E2DB','stroke-width':.7,
        class:'fade',style:`animation-delay:${i*.08}s`});
      const n=Math.round((was-now)/500);
      for(let k=0;k<n;k++){
        const t=(k+.5)/n,x=xb+t*(xa-xb),yy=y+(rnd(k+1,i+3)-.5)*2.6;
        el(s,'circle',{cx:x.toFixed(1),cy:yy.toFixed(1),r:(1.5+rnd(k+2,i+4)*.9).toFixed(2),fill:'#8F8E88',opacity:.85,
          class:'pop',style:`animation-delay:${(.3+i*.08+k*.03).toFixed(2)}s`});
      }
      el(s,'circle',{cx:xa.toFixed(1),cy:y,r:4.2,fill:PAPER,stroke:INK,'stroke-width':1.3,
        class:'pop',style:`animation-delay:${.2+i*.08}s`});
      const after=el(s,'circle',{cx:xb.toFixed(1),cy:y,r:4.6,fill:INK,
        class:'pop',style:`animation-delay:${.6+i*.08}s`});
      tip(after,`${name} — ${was} ms → ${now} ms`);
      // On a short row the two dots nearly coincide, so the labels would overlap; hold them apart.
      const wasX=Math.max(xa+10,xb+36);
      txt(s,{x:wasX.toFixed(1),y:y-8,'font-size':8.5,'font-weight':700,fill:'#B0AFA9',
        class:'fade',style:`animation-delay:${.3+i*.08}s`},was.toLocaleString());
      txt(s,{x:(xb-9).toFixed(1),y:y-8,'font-size':10,'font-weight':800,fill:INK,'text-anchor':'end',
        class:'fade',style:`animation-delay:${.7+i*.08}s`},now.toLocaleString());
    });
    txt(s,{x:X0,y:170,'font-size':7,'font-weight':600,fill:'#C6C5BF',class:'fade'},'FASTER ←');
    txt(s,{x:X1,y:170,'font-size':7,'font-weight':600,fill:'#C6C5BF','text-anchor':'end',class:'fade'},'MILLISECONDS');
    txt(s,{x:200,y:186,'font-size':7,'font-weight':600,fill:'#B0AFA9','text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:1s'},
      'TOTAL 10,066 → 443 MS · 22.7× · REVIEW PACKET UNCHANGED AT ~90 MS, NOT PLOTTED');
  }
});

// ═════ 2 · F9 rung waterfall — how the signature count moved ═════════════════════════
// template: C5 · rung waterfall. solid rungs add, dashed rungs take away.
card({
  file:'context-waterfall.svg',
  title:'From 622 signatures to 2,035',
  sub:'one rung = 50 signatures · solid adds · dashed takes away · PanicCamp repo map',
  src:'RUNG WATERFALL · MONO-BASIC · CONTEXT COMPOSITION',
  h:356,
  draw(s){
    // 622 baseline (0 of them C#) → +1630 C# unlocked → −217 prose capped / empty blocks dropped → 2035
    const rows=[['BASELINE',12,0,12],['C# UNLOCKED',33,45,12],['PROSE CAPPED',-4,41,45],['NOW',41,0,41]];
    const x0=i=>62+i*82,step=4.6,HW=13,base=256,yOf=k=>base-k*step;  // step tightened: 45 rungs must clear the subtitle
    const NUM=['622','+1,630','−217','2,035'];
    rows.forEach(([name,v,hi,lo],i)=>{
      const x=x0(i),isTotal=(i===0||i===3),neg=v<0;
      const from=isTotal?0:Math.min(lo,hi),to=isTotal?Math.abs(v):Math.max(lo,hi),n=Math.abs(to-from);
      for(let k=0;k<n;k++){
        const y=yOf(from+k),w=HW-1.2+rnd(k+1,i+2)*2.4;
        if(neg)el(s,'line',{x1:(x-w).toFixed(1),y1:y.toFixed(1),x2:(x+w).toFixed(1),y2:y.toFixed(1),stroke:'#8F8E88','stroke-width':1,
          'stroke-dasharray':'2.5 2.5',opacity:.7,class:'fade',style:`animation-delay:${(i*.12+k*.014).toFixed(2)}s`});
        else el(s,'line',{x1:(x-w).toFixed(1),y1:y.toFixed(1),x2:(x+w).toFixed(1),y2:y.toFixed(1),stroke:INK,'stroke-width':1,
          opacity:(.6+rnd(k+2,i+4)*.4).toFixed(2),class:'fade',style:`animation-delay:${(i*.12+k*.014).toFixed(2)}s`});
      }
      if(i<rows.length-1){
        const nx=x0(i+1),lvl=isTotal?Math.abs(v):Math.max(lo,hi);
        el(s,'line',{x1:x+HW+2,y1:yOf(lvl).toFixed(1),x2:nx-HW-2,y2:yOf(lvl).toFixed(1),stroke:'#C6C5BF',
          'stroke-width':.7,'stroke-dasharray':'2 3',class:'fade',style:`animation-delay:${.3+i*.12}s`});
      }
      const topY=yOf(Math.max(from,to));
      const num=txt(s,{x,y:(topY-8).toFixed(1),'font-size':10,'font-weight':800,fill:neg?'#8F8E88':INK,'text-anchor':'middle',
        class:'fade',style:`animation-delay:${.4+i*.12}s`},NUM[i]);
      tip(num,`${name} — ${NUM[i]} signatures`);
      txt(s,{x,y:base+18,'font-size':7,'font-weight':700,fill:MUTED,'text-anchor':'middle',
        'letter-spacing':'.06em',class:'fade',style:`animation-delay:${i*.12}s`},name);
    });
    el(s,'line',{x1:30,y1:base+4,x2:370,y2:base+4,stroke:GRID,'stroke-width':.8,class:'fade'});
    txt(s,{x:200,y:base+38,'font-size':7,'font-weight':600,fill:'#B0AFA9','text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:1.2s'},
      'BASELINE HELD ZERO C# SIGNATURES · THE REPO IS 142 C# FILES');
  }
});

// ═════ 3 · F1 rung bars — seat latency against the cap ═══════════════════════════════
// template: B1 · rung bars. one rung = one honest unit; dot marks every fifth.
card({
  file:'timeout-placement.svg',
  title:'The cap sat inside the work',
  sub:'one rung = 20 seconds · dot marks every fifth · three measured Gemini-seat runs',
  src:'RUNG BARS · MONO-BASIC · PANEL SEAT LATENCY',
  h:372,
  draw(s){
    const D=[['RUN 1',10,'204s'],['RUN 2',15,'304s'],['RETRY',12,'240s']];
    const x0=i=>92+i*84,base=266,step=5.6,HW=14;
    // the two caps, drawn first so rungs sit above them
    [[15,'OLD CAP · 300s','#8F8E88'],[28,'NOW · 570s','#C6C5BF']].forEach(([k,lab,col],j)=>{
      const y=base-k*step;
      el(s,'line',{x1:40,y1:y.toFixed(1),x2:368,y2:y.toFixed(1),stroke:col,'stroke-width':.9,
        'stroke-dasharray':'4 4',class:'fade',style:`animation-delay:${.9+j*.1}s`});
      txt(s,{x:368,y:(y-5).toFixed(1),'font-size':7,'font-weight':700,fill:col,'text-anchor':'end',
        'letter-spacing':'.08em',class:'fade',style:`animation-delay:${.95+j*.1}s`},lab);
    });
    D.forEach(([name,v,secs],i)=>{
      const x=x0(i);
      for(let k=0;k<v;k++){
        const y=base-k*step,w=HW-1.5+rnd(k+1,i+2)*3;
        el(s,'line',{x1:(x-w).toFixed(1),y1:y.toFixed(1),x2:(x+w).toFixed(1),y2:y.toFixed(1),stroke:INK,'stroke-width':1,
          opacity:(.5+rnd(k+2,i+4)*.5).toFixed(2),class:'fade',style:`animation-delay:${(i*.08+k*.012).toFixed(2)}s`});
        if(k%5===4)el(s,'circle',{cx:(x+HW+4.5).toFixed(1),cy:y.toFixed(1),r:.8,fill:'#C6C5BF',
          class:'fade',style:`animation-delay:${(i*.08+k*.012).toFixed(2)}s`});
      }
      const topY=base-(v-1)*step;
      const num=txt(s,{x,y:(topY-10).toFixed(1),'font-size':11,'font-weight':800,fill:INK,'text-anchor':'middle',
        class:'fade',style:`animation-delay:${.4+i*.08}s`},secs);
      tip(num,`${name} — ${secs}`);
      txt(s,{x,y:base+18,'font-size':7.5,'font-weight':700,fill:MUTED,'text-anchor':'middle',
        'letter-spacing':'.08em',class:'fade',style:`animation-delay:${i*.08}s`},name);
    });
    el(s,'line',{x1:28,y1:base+4,x2:372,y2:base+4,stroke:GRID,'stroke-width':.8,class:'fade'});
    txt(s,{x:200,y:base+40,'font-size':7,'font-weight':600,fill:'#B0AFA9','text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:1.2s'},
      'RUN 2 TIMED OUT · THE SAME PROMPT FINISHED IN 240s ON RETRY');
  }
});

// ═════ 4 · F5 tick rows — where the defects were caught ══════════════════════════════
// template: C1 · tick rows. one tick = one defect; dot marks every fifth.
card({
  file:'defect-origin.svg',
  title:'Fifty defects, and who caught them',
  sub:'one tick = one defect · dot marks every fifth · seven review passes on this branch',
  src:'TICK ROWS · MONO-BASIC · DEFECT LEDGER',
  h:248,
  draw(s){
    const D=[['PANEL FOUND',30],['SELF-INFLICTED',10],['SELF-AUDIT',10]];
    // The track spans the LARGEST row, not a hardcoded width: with 16 hardcoded, a 22-tick row ran off
    // the end of its own baseline.
    const MAXV=Math.max(...D.map(d=>d[1]));
    const y0=i=>40+i*46,X0=126,PX=9.5;
    D.forEach(([name,v],i)=>{
      const y=y0(i);
      txt(s,{x:116,y:y+3,'font-size':7.5,'font-weight':700,fill:'#6A6963','text-anchor':'end',
        'letter-spacing':'.08em',class:'fade',style:`animation-delay:${i*.08}s`},name);
      el(s,'line',{x1:X0,y1:y+9,x2:(X0+MAXV*PX).toFixed(1),y2:y+9,stroke:GRID,'stroke-width':.6,
        class:'fade',style:`animation-delay:${i*.08}s`});
      for(let k=0;k<v;k++){
        const x=X0+k*PX+PX/2,h=9+rnd(k+1,i+2)*6;
        el(s,'line',{x1:x.toFixed(1),y1:y+9,x2:x.toFixed(1),y2:(y+9-h).toFixed(1),stroke:INK,'stroke-width':.9,
          opacity:(.55+rnd(k+3,i+5)*.45).toFixed(2),class:'fade',style:`animation-delay:${(i*.08+k*.012).toFixed(2)}s`});
        if(k%5===4)el(s,'circle',{cx:x.toFixed(1),cy:y+13,r:.8,fill:'#C6C5BF',
          class:'fade',style:`animation-delay:${(i*.08+k*.012).toFixed(2)}s`});
      }
      const lab=txt(s,{x:(X0+v*PX+10).toFixed(1),y:y+4,'font-size':11,'font-weight':800,fill:INK,
        class:'fade',style:`animation-delay:${.4+i*.08}s`},v);
      tip(lab,`${name} — ${v} defects`);
    });
    txt(s,{x:200,y:196,'font-size':7,'font-weight':600,fill:'#B0AFA9','text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:.9s'},
      'PANEL FOUND = CAUGHT BY A SECOND READER THE AUTHOR DID NOT HAVE · ALL 50 CLOSED');
  }
});

// ═════ 5 · F4 tick donut — what the byte ceiling does ════════════════════════════════
// template: B4 · tick donut. one tick = 1%; the dial reads clockwise from twelve.
card({
  file:'map-budget.svg',
  title:'What the byte ceiling actually drops',
  sub:'one tick = one percent of 498 source files · PanicCamp, default 150 kB map ceiling',
  src:'TICK DONUT · MONO-BASIC · MAP BUDGET',
  h:330,
  draw(s){
    const D=[['MAPPED',30,INK],['NAMED ONLY',67,'#8F8E88'],['TREE-ONLY',3,'#B0AFA9']];
    const cx=200,cy=150,R0=64;
    let k0=0;
    D.forEach(([name,v,shade],si)=>{
      for(let k=0;k<v;k++){
        const idx=k0+k,a=idx*3.6-90;
        const len=10+rnd(idx+1,si+2)*6;
        const [x1,y1]=pol(cx,cy,R0,a),[x2,y2]=pol(cx,cy,R0+len,a);
        el(s,'line',{x1:x1.toFixed(1),y1:y1.toFixed(1),x2:x2.toFixed(1),y2:y2.toFixed(1),stroke:shade,'stroke-width':1,
          class:'fade',style:`animation-delay:${(idx*.012).toFixed(2)}s`});
        if(idx%10===0){
          const [dx,dy]=pol(cx,cy,R0-5,a);
          el(s,'circle',{cx:dx.toFixed(1),cy:dy.toFixed(1),r:.8,fill:'#C6C5BF',class:'fade',style:`animation-delay:${(idx*.012).toFixed(2)}s`});
        }
      }
      const mid=(k0+v/2)*3.6-90,[lx,ly]=pol(cx,cy,R0+40,mid),[gx,gy]=pol(cx,cy,R0+20,mid);
      el(s,'line',{x1:gx.toFixed(1),y1:gy.toFixed(1),x2:lx.toFixed(1),y2:ly.toFixed(1),stroke:'#C6C5BF','stroke-width':.7,
        'stroke-dasharray':'1 3',class:'fade',style:`animation-delay:${.6+si*.1}s`});
      const anchor=Math.cos(mid*D2R)>0.3?'start':Math.cos(mid*D2R)<-0.3?'end':'middle';
      const lab=txt(s,{x:lx.toFixed(1),y:(ly+3).toFixed(1),'font-size':8,'font-weight':800,fill:shade,'text-anchor':anchor,
        'letter-spacing':'.06em',style:`paint-order:stroke;stroke:${PAPER};stroke-width:3px;animation-delay:${(.65+si*.1).toFixed(2)}s`,
        class:'fade'},`${name} · ${v}%`);
      tip(lab,`${name} — ${v}% of 498 files`);
      k0+=v;
    });
    txt(s,{x:cx,y:cy-2,'font-size':22,'font-weight':800,fill:INK,'text-anchor':'middle',
      class:'fade',style:'animation-delay:.9s'},'498');
    txt(s,{x:cx,y:cy+14,'font-size':7,'font-weight':600,fill:MUTED,'text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:.9s'},'SOURCE FILES');
    txt(s,{x:200,y:274,'font-size':7,'font-weight':600,fill:'#B0AFA9','text-anchor':'middle',
      'letter-spacing':'.1em',class:'fade',style:'animation-delay:1.1s'},
      'NAMED ONLY = LISTED IN FILE_MAP, NO SIGNATURES — DISCLOSED, NEVER SILENT');
  }
});
