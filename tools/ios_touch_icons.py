#!/usr/bin/env python3
"""Generate port/ios/host/host_touch_icons.m: the Halo-style touch control
icons as path data on a 100-unit square, filled even-odd. Only absolute M, L,
C and Z are emitted so the app's parser stays tiny.

    python3 tools/ios_touch_icons.py             # write host_touch_icons.m
    python3 tools/ios_touch_icons.py --preview icons.png   # also draw them (needs cairosvg)
"""
import math, sys, textwrap
from pathlib import Path
K=0.5522847498
def fmt(v): return ('%.2f'%v).rstrip('0').rstrip('.')
class P:
    def __init__(s): s.d=[]
    def M(s,x,y): s.d.append('M%s %s'%(fmt(x),fmt(y))); return s
    def L(s,x,y): s.d.append('L%s %s'%(fmt(x),fmt(y))); return s
    def C(s,a,b,c,d,e,f): s.d.append('C%s %s %s %s %s %s'%tuple(map(fmt,(a,b,c,d,e,f)))); return s
    def Z(s): s.d.append('Z'); return s
    def poly(s,pts):
        s.M(*pts[0]); [s.L(*p) for p in pts[1:]]; return s.Z()
    def circle(s,cx,cy,r): return s.ellipse(cx,cy,r,r)
    def ellipse(s,cx,cy,rx,ry):
        kx,ky=rx*K,ry*K
        s.M(cx+rx,cy); s.C(cx+rx,cy+ky,cx+kx,cy+ry,cx,cy+ry); s.C(cx-kx,cy+ry,cx-rx,cy+ky,cx-rx,cy)
        s.C(cx-rx,cy-ky,cx-kx,cy-ry,cx,cy-ry); s.C(cx+kx,cy-ry,cx+rx,cy-ky,cx+rx,cy); return s.Z()
    def ring(s,cx,cy,r,w): s.circle(cx,cy,r); return s.circle(cx,cy,r-w)
    def rect(s,x,y,w,h): return s.poly([(x,y),(x+w,y),(x+w,y+h),(x,y+h)])
    def bevel(s,x,y,w,h,c):
        """a rectangle with its corners cut at 45 degrees (the HUD's shape)"""
        return s.poly([(x+c,y),(x+w-c,y),(x+w,y+c),(x+w,y+h-c),(x+w-c,y+h),(x+c,y+h),(x,y+h-c),(x,y+c)])
    def rot(s,pts,cx,cy,deg):
        a=math.radians(deg); return [(cx+(x-cx)*math.cos(a)-(y-cy)*math.sin(a), cy+(x-cx)*math.sin(a)+(y-cy)*math.cos(a)) for x,y in pts]
    def __str__(s): return ' '.join(s.d)

def chevron(p,cx,cy,w,h,t,up=True):
    """an angular chevron pointing up (or down), stroke thickness t"""
    s=1 if up else -1
    pts=[(cx,cy-s*h/2),(cx+w/2,cy+s*(h/2-t)),(cx+w/2-t,cy+s*h/2),(cx,cy-s*(h/2-t*1.15)),(cx-w/2+t,cy+s*h/2),(cx-w/2,cy+s*(h/2-t))]
    return p.poly(pts)

I={}
# fire: a ring reticle with four inward ticks and a centre dot
p=P().ring(50,50,36,7)
for a in (0,90,180,270): p.poly(p.rot([(46,8),(54,8),(52.5,26),(47.5,26)],50,50,a))
p.circle(50,50,5)
I['reticle']=p
# fire alt: a bracketed diamond reticle
p=P()
for a in (0,90,180,270): p.poly(p.rot([(22,14),(40,14),(40,21),(29,21),(29,32),(22,32)],50,50,a))
p.poly([(50,38),(62,50),(50,62),(38,50)])
I['bracket']=p
def tf(pts,sx,ox,oy): return [(ox+x*sx,oy+y*sx) for x,y in pts]
def arc(cx,cy,r1,r2,a0,a1,n=10):
    """a ring segment from angle a0 to a1 (degrees) as a polygon"""
    out=[(cx+r2*math.cos(math.radians(a0+(a1-a0)*i/n)),cy+r2*math.sin(math.radians(a0+(a1-a0)*i/n))) for i in range(n+1)]
    out+=[(cx+r1*math.cos(math.radians(a1-(a1-a0)*i/n)),cy+r1*math.sin(math.radians(a1-(a1-a0)*i/n))) for i in range(n+1)]
    return out
def frag(p,sx=1,ox=0,oy=0):
    p.ellipse(ox+46*sx,oy+60*sx,25*sx,29*sx)
    p.poly(tf([(19,53),(73,53),(73,60),(19,60)],sx,ox,oy))     # band
    p.poly(tf([(38,22),(54,22),(54,31),(38,31)],sx,ox,oy))     # cap
    p.poly(tf([(54,24),(72,24),(80,34),(80,60),(74,60),(74,37),(70,31),(54,31)],sx,ox,oy))  # spoon
def plasma(p,sx=1,ox=0,oy=0):
    cx,cy=ox+50*sx,oy+52*sx
    p.circle(cx,cy,17*sx)                                       # glowing core
    p.circle(cx,cy,9*sx)
    for a in (-90+20,30+20,150+20):                             # a shell broken in three
        p.poly(arc(cx,cy,24*sx,32*sx,a,a+80))
    for a in (-90-20+20,30-20+20,150-20+20):                    # claws at the breaks
        a=a-20+10
        r0,r1=26*sx,44*sx; w=math.radians(9)
        A=math.radians(a)
        p.poly([(cx+r0*math.cos(A-w),cy+r0*math.sin(A-w)),(cx+r1*math.cos(A),cy+r1*math.sin(A)),(cx+r0*math.cos(A+w),cy+r0*math.sin(A+w))])
p=P(); frag(p); I['frag']=p
p=P(); plasma(p); I['plasma']=p
# melee: an angular impact burst
pts=[]
for i in range(16):
    r=44 if i%2==0 else (20 if i%4==1 else 26)
    a=math.radians(i*22.5-90); pts.append((50+r*math.cos(a),50+r*math.sin(a)))
I['impact']=P().poly(pts)
# jump: two stacked chevrons
p=P(); chevron(p,50,36,62,30,11); chevron(p,50,66,62,30,11)
I['jump']=p
# crouch: a chevron down onto a bar
p=P(); chevron(p,50,40,62,30,11,up=False); p.bevel(18,70,64,11,3)
I['crouch']=p
# reload: a curved rifle magazine topped with a round
p=P(); p.poly([(32,30),(62,30),(64,52),(74,86),(46,92),(36,56)])
for y in (44,60): p.poly([(38+(y-30)*0.17,y),(60+(y-30)*0.33,y),(61+(y-30)*0.33,y+5),(39+(y-30)*0.17,y+5)])
p.poly([(40,26),(40,16),(46,8),(52,16),(52,26)])
I['magazine']=p
# weapon switch: two angular arrows, one each way
p=P(); p.poly([(14,34),(32,18),(32,28),(78,28),(78,40),(32,40),(32,50)])
p.poly([(86,66),(68,82),(68,72),(22,72),(22,60),(68,60),(68,50)])
I['swap']=p
# zoom: a scope reticle with a crosshair and mil dots
p=P().ring(50,50,38,6)
p.rect(47,16,6,26).rect(47,58,6,26).rect(16,47,26,6).rect(58,47,26,6)
for d in (-24,24): p.circle(50+d,50,3).circle(50,50+d,3)
I['scope']=p
# flashlight: a torch body angled up with three beam rays
p=P(); body=[(18,70),(42,46),(52,56),(28,80)]; p.poly(body)
p.poly([(42,46),(50,30),(70,50),(52,56)])
for (x1,y1,x2,y2) in ((60,26,72,10),(70,36,88,30),(56,22,56,6)):
    dx,dy=x2-x1,y2-y1; l=math.hypot(dx,dy); nx,ny=-dy/l*3,dx/l*3
    p.poly([(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)])
I['flashlight']=p
# switch grenade: a frag and a plasma side by side
p=P(); frag(p,0.66,-10,16); plasma(p,0.62,36,20)
I['grenades']=p
# pause: two bevelled bars
I['pause']=P().bevel(26,18,17,64,4).bevel(57,18,17,64,4)
# back / scoreboard: three angled bars
p=P()
for i,y in enumerate((22,44,66)): p.poly([(20,y),(80,y),(74,y+12),(14,y+12)])
I['scores']=p
# menu arrows: an angular arrowhead with a notch
for name,deg in (('up',0),('right',90),('down',180),('left',270)):
    I['arrow-'+name]=P().poly(P().rot([(50,18),(84,64),(62,64),(50,48),(38,64),(16,64)],50,50,deg))
# start alt: a bevelled play triangle
I['start']=P().poly([(30,16),(42,16),(80,46),(80,54),(42,84),(30,84)])

HEAD = '/* Halo-style icons for the touch controls: original HUD-like shapes (bevelled\n   bars, angular chevrons, a ring reticle, grenades, a magazine) drawn as\n   vector paths on a 100-unit square and filled even-odd, so cut-outs read as\n   holes. The paths use only absolute M, L, C and Z commands. They are\n   generated by a script from the same data used to preview them; edit the\n   shapes there rather than by hand. */\n#import <UIKit/UIKit.h>\n#import "host_touch.h"\n#include <stdlib.h>\n#include <string.h>\n\n'
TAIL = "static UIBezierPath *icon_path(const char *data, CGFloat scale) {\n    UIBezierPath *path=[UIBezierPath bezierPath];\n    path.usesEvenOddFillRule=YES;\n    const char *cursor=data;\n    char command=0;\n    for(;;) {\n        while(*cursor==' ' || *cursor==',') cursor++;\n        if(!*cursor) break;\n        if((*cursor>='A' && *cursor<='Z') || (*cursor>='a' && *cursor<='z')) {\n            command=*cursor++;\n            if(command=='Z') [path closePath];\n            continue;\n        }\n        int count=command=='C'?6:(command=='M' || command=='L')?2:0;\n        double value[6];\n        if(!count) return path;\n        for(int i=0;i<count;i++) {\n            while(*cursor==' ' || *cursor==',') cursor++;\n            char *end=NULL;\n            value[i]=strtod(cursor,&end);\n            if(end==cursor) return path;\n            cursor=end;\n        }\n        if(command=='M') {\n            [path moveToPoint:CGPointMake(value[0]*scale,value[1]*scale)];\n            command='L';\n        } else if(command=='L') {\n            [path addLineToPoint:CGPointMake(value[0]*scale,value[1]*scale)];\n        } else {\n            [path addCurveToPoint:CGPointMake(value[4]*scale,value[5]*scale)\n                controlPoint1:CGPointMake(value[0]*scale,value[1]*scale)\n                controlPoint2:CGPointMake(value[2]*scale,value[3]*scale)];\n        }\n    }\n    return path;\n}\n\nUIImage *halo_icon_image(NSString *name, CGFloat side) {\n    const char *data=NULL;\n    const char *wanted=name.UTF8String;\n    if(!wanted || side<1) return nil;\n    for(size_t i=0;i<sizeof(halo_icons)/sizeof(halo_icons[0]);i++)\n        if(!strcmp(halo_icons[i].name,wanted)) {data=halo_icons[i].path;break;}\n    if(!data) return nil;\n    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side,side)];\n    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {\n        (void)context;\n        [UIColor.whiteColor setFill];\n        [icon_path(data,side/100.0) fill];\n    }];\n    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];\n}\n"

def emit():
    rows = []
    for name, path in I.items():
        chunks = textwrap.wrap(str(path), 96, break_long_words=False)
        body = "\n".join('        "%s%s"' % (c, " " if n < len(chunks) - 1 else "") for n, c in enumerate(chunks))
        rows.append('    {"%s",\n%s},' % (name, body))
    table = "static const struct {\n    const char *name;\n    const char *path;\n} halo_icons[]={\n" + "\n".join(rows) + "\n};\n\n"
    out = Path(__file__).resolve().parents[1] / "port/ios/host/host_touch_icons.m"
    out.write_text(HEAD + table + TAIL)
    print(f"wrote {out} ({len(I)} icons)")

def preview(png):
    import cairosvg
    cols, cell = 7, 150
    rows = (len(I) + cols - 1) // cols
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{cols*cell}" height="{rows*(cell+20)}">'
             '<rect width="100%" height="100%" fill="#0b1622"/>']
    for n, name in enumerate(I):
        x, y = (n % cols) * cell, (n // cols) * (cell + 20)
        parts.append(f'<g transform="translate({x+15},{y+10})"><circle cx="60" cy="60" r="58" fill="#0d2235" stroke="#5fc8ff" stroke-width="2"/>'
                     f'<g transform="translate(24,24) scale(0.72)"><path d="{I[name]}" fill="#bfe9ff" fill-rule="evenodd"/></g></g>'
                     f'<text x="{x+75}" y="{y+cell+8}" fill="#9fd" font-size="13" text-anchor="middle" font-family="sans-serif">{name}</text>')
    parts.append("</svg>")
    cairosvg.svg2png(bytestring="".join(parts).encode(), write_to=png)
    print(f"wrote {png}")

if __name__ == "__main__":
    emit()
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
