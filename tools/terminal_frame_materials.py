"""Code-native C-layout frames. Illustration files are inputs, never edited.

Every theme has its own drawn construction. All paint stays in the outer
24-pixel band of a 1280-wide reference canvas. Long corner shoulders run along
the rim rather than increasing depth into the terminal's reading area.
"""
from __future__ import annotations
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def rgb(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def blend(a,b,t): return tuple(round(x+(y-x)*t) for x,y in zip(a,b))


class Pen:
    def __init__(self,w,h):
        self.w,self.h,self.s=w,h,3
        self.im=Image.new('RGBA',(w*3,h*3));self.d=ImageDraw.Draw(self.im)
    def points(self,p): return [(round(x*self.s),round(y*self.s)) for x,y in p]
    def line(self,p,c,width=1): self.d.line(self.points(p),fill=c,width=max(1,round(width*self.s)),joint='curve')
    def poly(self,p,c,outline=None):
        self.d.polygon(self.points(p),fill=c)
        if outline:self.line(p+[p[0]],outline,.65)
    def ellipse(self,b,c=None,outline=None,width=1):
        self.d.ellipse(tuple(round(x*self.s) for x in b),fill=c,outline=outline,width=max(1,round(width*self.s)))
    def arc(self,b,start,end,c,width=1): self.d.arc(tuple(round(x*self.s) for x in b),start,end,fill=c,width=max(1,round(width*self.s)))
    def rect(self,b,c=None,outline=None,width=1):
        self.d.rectangle(tuple(round(x*self.s) for x in b),fill=c,outline=outline,width=max(1,round(width*self.s)))
    def rounded(self,b,r,c=None,outline=None,width=1):
        self.d.rounded_rectangle(tuple(round(x*self.s) for x in b),radius=round(r*self.s),fill=c,outline=outline,width=max(1,round(width*self.s)))
    def image(self):return self.im.resize((self.w,self.h),Image.Resampling.LANCZOS)


def star(p,cx,cy,r,c,inner=.32,n=4):
    pts=[]
    for i in range(n*2):
        a=-math.pi/2+i*math.pi/n;rr=r if i%2==0 else r*inner
        pts.append((cx+math.cos(a)*rr,cy+math.sin(a)*rr))
    p.poly(pts,c)


def gem(p,cx,cy,r,c,shape='diamond'):
    dark=blend(c,(0,8,18),.6);light=blend(c,(255,255,236),.7)
    if shape=='hex':
        pts=[(cx+math.cos(i*math.pi/3)*r,cy+math.sin(i*math.pi/3)*r) for i in range(6)]
    else:pts=[(cx,cy-r),(cx+r,cy),(cx,cy+r),(cx-r,cy)]
    p.poly(pts,dark,light)
    for i in range(len(pts)):
        p.poly([(cx,cy),pts[i],pts[(i+1)%len(pts)]],blend(c,light,(i%3)/3))
    p.ellipse((cx-1.1,cy-1.8,cx+.5,cy-.2),light)


def rail(row,w,h):
    """Shaded material, with different width/finish for each construction."""
    slug=row['slug'];bg=rgb(row['background']);metal=rgb(row['border'])
    light=slug=='wonderland';yy,xx=np.mgrid[:h,:w]
    edge=np.minimum(np.minimum(xx,w-1-xx),np.minimum(yy,h-1-yy))
    rng=np.random.default_rng(sum(map(ord,slug)))
    grain=rng.normal(0,1,(h,w))
    depth={'hextech':15,'tactical':17,'protocol':13,'adventure':20,'arsenal':18,'relic':20,'starlight':14,'formation':18,'astral':9,'wonderland':17}.get(slug,12)
    # Actual layers: shadow -> material body -> narrow specular lip. Texture
    # amplitude varies with the material, not merely the theme's tint.
    base=np.broadcast_to(np.array(bg,dtype=float),(h,w,3)).copy()
    shade=.14+.13*np.cos((edge-3)/max(depth,1)*math.pi)
    shade+=.12*np.exp(-((edge-4)/1.3)**2)-.1*np.exp(-((edge-depth+2)/1.5)**2)
    texture=grain*({'tactical':2.5,'adventure':3,'arsenal':3.2,'relic':4.5,'astral':.7,'wonderland':.5}.get(slug,1.4))
    if slug=='adventure':texture+=np.sin(xx*.23)*1.8
    if slug=='relic':texture+=np.sin(xx*.07+np.sin(yy*.11))*3
    if slug=='formation':shade+=np.sin(xx*.025)*.05
    target=np.array(metal)
    if light:target=np.array([165,206,195]);shade=.18+.12*np.cos(edge/19*math.pi)
    base=base*(1-shade[:,:,None])+target*shade[:,:,None]+texture[:,:,None]
    alpha=np.clip((depth+1-edge)/2,0,1)*(edge>=1)*.98
    rgba=np.dstack((np.clip(base,0,255).astype(np.uint8),(alpha*255).astype(np.uint8)))
    return Image.fromarray(rgba,'RGBA')


def corner(row):
    """A theme-specific corner plus a long, shallow top shoulder."""
    slug=row['slug'];p=Pen(174,52)
    a=rgb(row['accent']);b=rgb(row['secondary']);dark=blend(rgb(row['background']),(0,0,0),.35)
    metal=rgb(row['border']);hi=blend(a,(255,244,210),.45)
    if slug=='ink-jade':
        p.poly([(3,3),(108,3),(119,10),(104,19),(34,19),(21,30),(3,30)],blend(metal,dark,.55),a)
        p.line([(7,27),(7,7),(103,7)],hi,.7)
        for x in range(40,104,16):
            p.line([(x,9),(x+9,9),(x+9,15),(x+3,15),(x+3,12)],metal,.9)
        p.ellipse((10,9,28,27),dark,a,.8);gem(p,19,18,6,b)
        p.arc((25,7,58,20),170,345,b,.7)
    elif slug=='midnight':
        p.poly([(3,3),(105,3),(119,12),(99,20),(35,20),(20,31),(3,31)],blend((23,40,73),dark,.4),metal)
        p.arc((28,-3,116,26),15,170,a,.8);p.arc((40,1,102,24),190,350,b,.6)
        p.ellipse((5,4,31,30),dark,a,.8);p.arc((9,7,28,27),65,298,hi,1.2)
        star(p,19,17,6,b,inner=.22)
        for x,y in [(45,11),(62,8),(80,14),(100,10)]:star(p,x,y,2,hi,inner=.2)
    elif slug=='cinnabar':
        p.poly([(2,2),(111,2),(136,9),(108,18),(34,18),(18,31),(2,31)],blend((102,29,35),dark,.35),a)
        p.poly([(9,24),(17,12),(38,6),(34,11),(20,18),(17,29)],metal,hi)
        for i,x in enumerate(range(44,112,13)):
            p.line([(x,7),(x+8,10),(x+2,14)],hi if i%2 else metal,.8)
        gem(p,18,15,4,b);p.line([(36,16),(107,16),(124,10)],a,.6)
    elif slug=='hextech':
        p.poly([(3,3),(97,3),(111,11),(93,18),(37,18),(26,25),(3,25)],blend(metal,dark,.55),a)
        p.line([(31,7),(91,7),(101,11),(90,14),(37,14)],hi,.65)
        for x in (49,62,75):p.poly([(x,8),(x+7,8),(x+10,11),(x+7,14),(x,14),(x-3,11)],dark,b)
        for i in range(12):
            t=i*math.pi/6
            p.line([(16+math.cos(t)*9,15+math.sin(t)*9),(16+math.cos(t)*12,15+math.sin(t)*12)],a,2)
        p.ellipse((6,5,26,25),dark,hi,.75);p.ellipse((10,9,22,21),None,metal,1)
        gem(p,16,15,5,b,'hex');p.line([(29,21),(39,21),(43,17)],b,.7)
    elif slug=='tactical':
        p.poly([(2,2),(116,2),(123,9),(109,16),(28,16),(16,27),(2,27)],dark,metal)
        p.line([(6,24),(6,6),(34,6)],a,1.4)
        p.line([(10,21),(10,10),(25,10)],hi,.65)
        for i,x in enumerate(range(39,111,6)):
            p.line([(x,4),(x,8 if i%3 else 11)],a if i%3==0 else metal,.7)
        p.poly([(15,18),(21,12),(24,15),(18,21)],a)
        p.line([(31,13),(91,13)],b,.6)
        p.rect((99,11,108,13),a)
    elif slug=='protocol':
        p.poly([(2,2),(94,2),(111,13),(96,21),(35,21),(21,7),(10,7),(10,27),(2,27)],dark,metal)
        p.poly([(3,3),(55,3),(67,11),(35,11),(24,3)],a)
        p.poly([(50,14),(97,14),(104,11),(98,18),(57,18)],blend(a,dark,.4))
        p.line([(16,25),(16,16),(26,7)],hi,1.2)
        p.line([(69,6),(94,6),(101,10)],b,.7)
        for x in (115,127,139):p.poly([(x,6),(x+6,6),(x+1,12),(x-5,12)],a)
    elif slug=='adventure':
        p.poly([(3,3),(111,3),(126,11),(112,20),(32,20),(20,31),(3,31)],blend(metal,dark,.6),hi)
        p.poly([(30,8),(107,8),(115,11),(108,15),(31,15)],(64,40,24),metal)
        for x in range(37,108,7):p.line([(x,9),(x+3,14)],blend(a,(87,53,25),.5),.7)
        for x,y in [(11,11),(22,23),(113,11)]:
            p.ellipse((x-3.3,y-3.3,x+3.3,y+3.3),dark,metal,.75)
            p.ellipse((x-1.8,y-2,x+1.8,y+1.5),a)
            p.line([(x-1,y-.3),(x+1,y-.3)],hi,.5)
        p.line([(5,29),(29,5)],hi,1.1);p.line([(10,29),(33,6)],metal,.75)
        gem(p,18,15,4,b)
    elif slug=='arsenal':
        p.poly([(2,2),(111,2),(137,9),(104,16),(32,16),(16,29),(2,29)],dark,metal)
        p.poly([(7,25),(11,25),(37,5),(30,7)],blend(a,(244,227,194),.25),hi)
        p.poly([(7,11),(11,7),(27,28),(22,26)],blend(metal,dark,.18),a)
        p.line([(37,7),(104,7),(124,9),(100,12),(46,12)],a,.8)
        for i,x in enumerate(range(48,100,12)):
            p.line([(x,9),(x+3,6),(x+6,9),(x+3,12),(x,9)],b,.7)
        p.ellipse((13,12,22,21),dark,a,.7);star(p,17.5,16.5,3,b)
    elif slug=='relic':
        p.poly([(2,2),(101,2),(108,7),(101,12),(35,12),(35,18),(24,18),(24,28),(2,28)],blend(metal,dark,.67),metal)
        for k in (4,8,12):
            p.line([(k,27-k/3),(k,k),(96-k,k)],hi if k==4 else metal,.65)
        for x in range(43,94,13):
            p.line([(x,5),(x+7,5),(x+7,9),(x+3,9),(x+3,7)],a,.75)
        p.rect((13,12,26,25),dark,a,.9)
        p.line([(17,14),(22,14),(22,18),(16,18),(16,22),(23,22)],hi,.7)
        p.line([(29,7),(31,10),(28,14),(31,17)],dark,.7)
    elif slug=='starlight':
        p.poly([(2,2),(89,2),(113,10),(83,19),(36,19),(25,28),(2,28)],blend(rgb(row['surface']),dark,.2),a)
        p.arc((11,-1,64,24),8,165,a,.8);p.arc((36,-5,104,23),10,165,hi,.5)
        p.poly([(23,15),(32,8),(48,11),(32,17)],blend(a,dark,.25),hi)
        p.ellipse((5,4,28,27),dark,a,.9);p.ellipse((8,7,25,24),None,hi,.6)
        gem(p,16.5,15.5,6.3,b);star(p,16.5,15.5,4.6,hi,inner=.18)
        for x,y in [(62,9),(79,13),(96,10)]:star(p,x,y,2,b)
    elif slug=='formation':
        p.rounded((2,2,117,23),8,blend(rgb(row['surface']),dark,.15),a,.9)
        p.rounded((30,7,106,17),3,dark,metal,.65)
        for i,x in enumerate(range(36,102,12)):
            p.rounded((x,9,x+8,15),2,blend(b,dark,.48 if i%2 else .18),b,.5)
            p.line([(x+2,9.5),(x+6,9.5)],hi,.5)
        p.rounded((5,4,27,27),7,dark,hi,.8)
        p.ellipse((10,9,22,21),None,b,.8);gem(p,16,15,4,a,'hex')
        p.ellipse((23,5,27,9),hi)
    elif slug=='astral':
        p.line([(3,28),(3,3),(112,3)],a,.6)
        p.arc((10,3,76,22),180,355,a,.7);p.arc((42,-5,118,22),8,173,metal,.5)
        p.line([(25,18),(43,9),(69,13),(89,7),(112,12),(135,5)],metal,.55)
        for i,(x,y) in enumerate([(43,9),(69,13),(89,7),(112,12),(135,5)]):
            p.ellipse((x-1.3,y-1.3,x+1.3,y+1.3),hi if i%2 else b)
        p.ellipse((5,4,29,28),dark,a,.6);p.arc((8,7,26,25),15,330,hi,.6)
        for i in range(8):
            ang=i*math.pi/4;p.line([(17+math.cos(ang)*8,16+math.sin(ang)*8),(17+math.cos(ang)*11,16+math.sin(ang)*11)],a,.6)
        star(p,17,16,7,hi,inner=.18);gem(p,17,16,2.5,b)
    elif slug=='wonderland':
        ivory=(247,239,217);teal=(69,138,144);gold=(167,126,57)
        p.rounded((2,2,113,23),9,ivory,gold,.8)
        p.arc((26,3,67,20),170,355,teal,.8);p.arc((53,3,95,20),175,355,gold,.65)
        p.arc((80,4,119,19),160,320,teal,.65)
        for x,y,r in [(12,17,7),(20,11,6),(28,17,5)]:
            p.ellipse((x-r,y-r,x+r,y+r),ivory,teal,.8)
        p.arc((6,10,18,22),180,350,gold,.65)
        p.line([(8,24),(24,24),(28,20)],gold,.75)
        gem(p,19,18,3.5,(69,157,142));p.ellipse((101,8,107,14),(173,77,64))
    else:
        p.line([(3,29),(3,3),(97,3)],a,.8)
        p.line([(8,29),(8,8),(92,8)],metal,.65)
        p.ellipse((11,11,23,23),dark,hi,.7);gem(p,17,17,3.5,b)
    return p.image()


def build_frame(row,w=1280,h=754):
    """Static frame with full horizontal/vertical shoulders in a safe rim."""
    image=rail(row,w,h);p=Pen(w,h)
    slug=row['slug'];a=rgb(row['accent']);b=rgb(row['secondary']);metal=rgb(row['border'])
    p.rect((3,3,w-4,h-4),None,blend(metal,a,.35),.8)
    p.rect((6,6,w-7,h-7),None,blend(metal,rgb(row['background']),.2),.45)
    inner={'adventure':18,'relic':18,'formation':17,'tactical':16,'astral':11}.get(slug,14)
    p.rect((inner,inner,w-inner-1,h-inner-1),None,blend(metal,rgb(row['background']),.4),.45)
    if slug=='tactical':
        for x in range(180,w-170,8):
            depth=7 if x%40 else 11
            p.line([(x,5),(x,depth)],metal,.6);p.line([(w-x,h-6),(w-x,h-depth-1)],metal,.6)
        for y in range(120,h-110,20):p.line([(4,y),(10 if y%100 else 15,y)],metal,.6)
    elif slug=='protocol':
        for x in range(190,w-170,44):
            p.line([(x,9),(x+12,9)],a,.9)
        for y in range(130,h-100,58):p.poly([(6,y),(10,y+4),(10,y+17),(6,y+13)],metal)
    elif slug=='adventure':
        for x in range(154,w-130,18):p.line([(x,11),(x+6,14)],metal,.7)
        for y in range(110,h-90,68):
            for x in (10,w-11):p.ellipse((x-2,y-2,x+2,y+2),a,metal,.5)
    elif slug=='arsenal':
        for x in range(182,w-150,92):
            p.line([(x-5,10),(x,6),(x+5,10),(x,14),(x-5,10)],metal,.7)
            p.line([(x,7),(x,13)],b,.5)
    elif slug=='relic':
        for x in range(170,w-150,58):
            p.line([(x,7),(x+12,7),(x+12,14),(x+5,14),(x+5,10)],metal,.6)
        for y in range(90,h-80,87):p.line([(5,y),(12,y+3),(8,y+8),(14,y+12)],blend(metal,(0,0,0),.5),.7)
    elif slug=='formation':
        for x in range(164,w-140,36):
            p.rounded((x,6,x+21,13),2,None,metal,.6)
            p.rect((x+3,8,x+8,11),blend(b,metal,.4))
    elif slug in ('hextech','starlight','astral'):
        for x in range(182,w-150,132):
            p.line([(x-32,8),(x-9,8),(x,12),(x+9,8),(x+32,8)],metal,.55)
            star(p,x,9,3,a if slug!='hextech' else b,inner=.25)
    elif slug=='wonderland':
        for x in range(160,w-140,74):
            p.arc((x,5,x+31,14),180,350,blend(metal,b,.35),.65)
            p.arc((x+20,5,x+51,14),5,180,metal,.55)
    image=Image.alpha_composite(image,p.image())
    c=corner(row)
    # A shoulder is horizontal and shallow. A rotated copy gives its matching
    # vertical member; masks below keep the whole construction outside text.
    temp=Image.new('RGBA',(w,h))
    for patch in (c,c.transpose(Image.Transpose.TRANSPOSE)):
        for flipx,flipy in ((False,False),(True,False),(False,True),(True,True)):
            part=patch
            if flipx:part=ImageOps_mirror(part)
            if flipy:part=ImageOps_flip(part)
            temp.alpha_composite(part,(w-part.width if flipx else 0,h-part.height if flipy else 0))
    image=Image.alpha_composite(image,temp)
    arr=np.array(image)
    yy,xx=np.mgrid[:h,:w];edge=np.minimum(np.minimum(xx,w-1-xx),np.minimum(yy,h-1-yy))
    # Corners can extend to 29px only when both coordinates are in the corner
    # square. Reading starts at x36/y32 so their curved tips remain separated.
    allow=(edge<24)|((np.minimum(xx,w-1-xx)<31)&(np.minimum(yy,h-1-yy)<31))
    arr[:,:,3]*=allow
    return Image.fromarray(arr,'RGBA')


def ImageOps_mirror(im): return im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
def ImageOps_flip(im): return im.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
