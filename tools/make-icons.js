// Renders wok icons to PNG (no deps): supersampled shapes + zlib.
const fs=require("fs"),zlib=require("zlib");
function png(w,h,px){const crc=(b)=>{let c,t=[];for(let n=0;n<256;n++){c=n;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;t[n]=c>>>0}c=0xffffffff;for(const x of b)c=t[(c^x)&255]^(c>>>8);return(c^0xffffffff)>>>0};
const ch=(t,d)=>{const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc(td));return Buffer.concat([l,td,c])};
const raw=Buffer.alloc((w*4+1)*h);for(let y=0;y<h;y++){raw[y*(w*4+1)]=0;px.copy(raw,y*(w*4+1)+1,y*w*4,(y+1)*w*4)}
const ih=Buffer.alloc(13);ih.writeUInt32BE(w,0);ih.writeUInt32BE(h,4);ih[8]=8;ih[9]=6;
return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),ch("IHDR",ih),ch("IDAT",zlib.deflateSync(raw)),ch("IEND",Buffer.alloc(0))])}
// shapes in unit space 0..1, painter's order
function scene(on){const S=[];
 const flame=on?[255,122,26]:[90,90,96], flame2=on?[255,214,64]:[130,130,138];
 const iron=on?[38,34,32]:[70,70,76], rim=on?[230,90,30]:[120,120,128];
 // flames
 S.push([(x,y)=>{const c=[[.32,.86],[.5,.84],[.68,.86]];return c.some(([cx,cy])=>{const dx=(x-cx)/.11,dy=(y-cy)/.16;return dx*dx+dy*dy<1&&y<cy+.08})},flame]);
 S.push([(x,y)=>{const c=[[.32,.9],[.5,.88],[.68,.9]];return c.some(([cx,cy])=>{const dx=(x-cx)/.06,dy=(y-cy)/.09;return dx*dx+dy*dy<1})},flame2]);
 // handle
 S.push([(x,y)=>x>.78&&x<.99&&Math.abs(y-(.42-(x-.78)*.35))<.045,iron]);
 // wok bowl: lower half ellipse
 S.push([(x,y)=>{const dx=(x-.46)/.4,dy=(y-.42)/.34;return y>=.42&&dx*dx+dy*dy<1},iron]);
 // rim
 S.push([(x,y)=>{const dx=(x-.46)/.42,dy=(y-.42)/.07;return dx*dx+dy*dy<1&&!(((x-.46)/.36)**2+((y-.42)/.045)**2<1)},rim]);
 // noodles/food inside rim
 S.push([(x,y)=>((x-.46)/.36)**2+((y-.42)/.045)**2<1,on?[250,200,90]:[150,150,150]]);
 // tossed noodle bits
 if(on)S.push([(x,y)=>{const c=[[.36,.22],[.52,.16],[.62,.26]];return c.some(([cx,cy])=>(x-cx)**2+(y-cy)**2<.0022)},[250,200,90]]);
 return S}
function render(size,on){const ss=4,px=Buffer.alloc(size*size*4),S=scene(on);
 for(let y=0;y<size;y++)for(let x=0;x<size;x++){let r=0,g=0,b=0,a=0;
  for(let sy=0;sy<ss;sy++)for(let sx=0;sx<ss;sx++){const u=(x+(sx+.5)/ss)/size,v=(y+(sy+.5)/ss)/size;let col=null;for(const[f,c]of S)if(f(u,v))col=c;if(col){r+=col[0];g+=col[1];b+=col[2];a++}}
  const i=(y*size+x)*4,n=ss*ss;if(a){px[i]=r/a;px[i+1]=g/a;px[i+2]=b/a;px[i+3]=255*a/n}}
 return png(size,size,px)}
for(const on of[true,false])for(const s of[16,32])fs.writeFileSync(`extension/icons/${on?"on":"off"}${s}.png`,render(s,on));
