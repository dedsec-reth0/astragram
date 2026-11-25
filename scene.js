/* AstraGram liquid chrome scene: one fullscreen raymarched object (liquid blob <-> paper plane). Shared by the site pages. */
window.AstraScene=(function(){
 const cv=document.getElementById('gl');
 const gl=cv.getContext('webgl',{antialias:false,alpha:false,powerPreference:'high-performance',preserveDrawingBuffer:false});
 if(!gl){cv.style.display='none';document.getElementById('glFallback').style.display='block';return null}
 const VS=`attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}`;
 const FS=`precision highp float;
 uniform vec2 R;uniform float T;uniform vec2 MS;uniform float MO;uniform vec3 POS;uniform float SC;uniform vec2 ROT;uniform float DIM;uniform float SPIN;
 #define STEPS 56
 float smin(float a,float b,float k){float h=clamp(.5+.5*(b-a)/k,0.,1.);return mix(b,a,h)-k*h*(1.-h);}
 float dot2(vec3 v){return dot(v,v);}
 float udTri(vec3 p,vec3 a,vec3 b,vec3 c){vec3 ba=b-a,pa=p-a,cb=c-b,pb=p-b,ac=a-c,pc=p-c;vec3 nor=cross(ba,ac);
  return sqrt((sign(dot(cross(ba,nor),pa))+sign(dot(cross(cb,nor),pb))+sign(dot(cross(ac,nor),pc))<2.)
  ?min(min(dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.,1.)-pa),dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.,1.)-pb)),dot2(ac*clamp(dot(ac,pc)/dot2(ac),0.,1.)-pc))
  :dot(nor,pa)*dot(nor,pa)/dot2(nor));}
 mat2 rot(float a){float c=cos(a),s=sin(a);return mat2(c,-s,s,c);}
 float blob(vec3 p){
  float d=1e5;
  for(int i=0;i<5;i++){float f=float(i);
   vec3 c=.62*vec3(sin(T*.37*(1.+f*.13)+f*1.9),cos(T*.31*(1.+f*.11)+f*2.7)*.8,sin(T*.29*(1.+f*.17)+f*3.1)*.7);
   d=smin(d,length(p-c)-(.46+.07*sin(T*.6+f*1.3)),.48);}
  vec3 mp=vec3(MS*vec2(1.25,.8),.55);d=smin(d,length(p-mp)-.3,.55);
  d+=.025*sin(4.*p.x+T*.9)*sin(4.3*p.y+T*1.1)*sin(3.7*p.z-T*.7);
  return d;}
 float plane(vec3 p){
  p.xy*=rot(-.38);
  p.y-=.02*sin(p.x*3.+T*1.6);
  vec3 n=vec3(1.25,.06,0.);vec3 tl=vec3(-.85,.16,-1.0),tr=vec3(-.85,.16,1.0),tm=vec3(-.62,0.,0.),tk=vec3(-.8,-.4,0.);
  float w=min(udTri(p,n,tl,tm),udTri(p,n,tr,tm));float k=udTri(p,n,tm,tk);
  return min(w,k)-.022;}
 float map(vec3 p){
  p-=POS;p/=SC;
  p.xz*=rot(ROT.x+SPIN);p.yz*=rot(ROT.y);
  float b=MO<.999?blob(p):1e5;float pl=MO>.001?plane(p):1e5;
  return mix(b,pl,smoothstep(0.,1.,MO))*SC;}
 vec3 nrm(vec3 p){vec2 e=vec2(.0015,-.0015);return normalize(e.xyy*map(p+e.xyy)+e.yyx*map(p+e.yyx)+e.yxy*map(p+e.yxy)+e.xxx*map(p+e.xxx));}
 vec3 env(vec3 d){
  vec3 c=vec3(.006);
  c+=vec3(1.)*smoothstep(.55,.95,d.y)*.95;
  c+=vec3(1.)*pow(max(0.,1.-abs(d.x-.62)*5.),3.)*smoothstep(-.3,.5,d.y)*.9;
  c+=vec3(1.)*pow(max(0.,1.-abs(d.x+.75)*7.),3.)*smoothstep(-.1,.7,d.y)*.45;
  c+=vec3(.55,.36,.98)*pow(max(0.,-d.x*.9-d.z*.3),3.)*.85;
  c+=vec3(.22,.74,.97)*pow(max(0.,d.x*.7-d.z*.5),3.)*.7;
  c+=vec3(.05)*exp(-abs(d.y+.1)*5.);
  return c;}
 void main(){
  vec2 uv=(gl_FragCoord.xy-.5*R)/R.y;
  vec3 ro=vec3(0.,0.,4.2),rd=normalize(vec3(uv,-1.75));
  vec3 col=vec3(0.);
  // bound sphere
  vec3 oc=ro-POS;float br=2.0*SC;float b=dot(oc,rd),c=dot(oc,oc)-br*br,h=b*b-c;
  if(h>0.){
   float t=max(-b-sqrt(h),0.),tm=-b+sqrt(h);bool hit=false;
   for(int i=0;i<STEPS;i++){vec3 p=ro+rd*t;float d=map(p);if(d<.0015){hit=true;break;}t+=d*.85;if(t>tm)break;}
   if(hit){vec3 p=ro+rd*t;vec3 n=nrm(p);vec3 r=reflect(rd,n);float fr=pow(1.-max(dot(n,-rd),0.),3.);
    vec3 e=env(r);
    col=e*(.55+.45*fr)+vec3(.02);
    // the paper plane reads as frosted white glass, like the logo
    vec3 L=normalize(vec3(.5,.9,.7));float dif=abs(dot(n,L));float back=abs(dot(n,normalize(vec3(-.7,-.2,.5))));
    vec3 paper=vec3(.86,.88,.95)*(.28+.72*dif)+vec3(.55,.36,.98)*.25*back+vec3(.22,.74,.97)*.35*fr;
    col=mix(col,paper*(.75+.25*e),smoothstep(.3,1.,MO)*.62);
    col+=vec3(1.)*pow(max(dot(r,normalize(vec3(.4,.8,.6))),0.),60.)*.8;
    col*=DIM;}
  }
  // soft halo behind object
  vec2 sp=POS.xy/(4.2-POS.z)*1.75;float g=length(uv-sp);
  col+=DIM*(vec3(.55,.36,.98)*.10*exp(-g*g*2.2/(SC*SC))+vec3(.22,.74,.97)*.06*exp(-pow(length(uv-sp-vec2(.25,-.15)),2.)*3./(SC*SC)));
  col=col/(1.+col*.25);
  col=pow(col,vec3(.92));
  gl_FragColor=vec4(col,1.);}`;
 function sh(t,s){const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);if(!gl.getShaderParameter(o,gl.COMPILE_STATUS)){console.error(gl.getShaderInfoLog(o));return null}return o}
 const pr=gl.createProgram();const v=sh(gl.VERTEX_SHADER,VS),f=sh(gl.FRAGMENT_SHADER,FS);
 if(!v||!f){cv.style.display='none';document.getElementById('glFallback').style.display='block';return null}
 gl.attachShader(pr,v);gl.attachShader(pr,f);gl.linkProgram(pr);gl.useProgram(pr);
 const buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
 const loc=gl.getAttribLocation(pr,'p');gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
 const U={};['R','T','MS','MO','POS','SC','ROT','DIM','SPIN'].forEach(n=>U[n]=gl.getUniformLocation(pr,n));
 const mobile=matchMedia('(max-width:860px)').matches||/iPhone|iPad|Android/.test(navigator.userAgent);
 let q=mobile?.5:.62; // internal resolution relative to CSS pixels (x dpr, capped)
 let W=0,H=0;
 function size(){const d=Math.min(window.devicePixelRatio||1,2);W=Math.max(2,Math.round(innerWidth*d*q));H=Math.max(2,Math.round(innerHeight*d*q));cv.width=W;cv.height=H;gl.viewport(0,0,W,H)}
 size();addEventListener('resize',size);
 let ft=[],lastAdj=0;
 return {draw(s,t,dt){
  gl.uniform2f(U.R,W,H);gl.uniform1f(U.T,t);gl.uniform2f(U.MS,s.mx,s.my);gl.uniform1f(U.MO,s.morph);gl.uniform3f(U.POS,s.x,s.y,s.z);
  gl.uniform1f(U.SC,s.sc);gl.uniform2f(U.ROT,s.ry,s.rx);gl.uniform1f(U.DIM,s.dim);gl.uniform1f(U.SPIN,s.spin);
  gl.drawArrays(gl.TRIANGLES,0,3);
  // adaptive resolution: keep frames under ~22ms
  ft.push(dt);if(ft.length>40){const avg=ft.reduce((a,b)=>a+b)/ft.length;ft=[];
   if(avg>24&&q>.3){q=Math.max(.3,q-.07);size()}else if(avg<13&&q<(mobile?.6:.8)&&t-lastAdj>4){q+=.04;lastAdj=t;size()}}
 }};
})();

