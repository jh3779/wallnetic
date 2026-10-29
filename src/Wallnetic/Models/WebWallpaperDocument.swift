import Foundation
import CoreGraphics

struct WebWallpaperSource: Codable, Equatable {
    enum Kind: String, Codable { case website, local, builtIn }
    let kind: Kind
    let url: URL
    var folderBookmark: Data?

    static func website(_ text: String) throws -> Self {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { throw SourceError.address }
        return Self(kind: .website, url: url)
    }

    static func local(_ url: URL) throws -> Self {
        guard url.isFileURL, ["html", "htm"].contains(url.pathExtension.lowercased()) else {
            throw SourceError.document
        }
        return Self(kind: .local, url: url.resolvingSymlinksInPath().standardizedFileURL)
    }

    static let orbit = Self(kind: .builtIn, url: URL(string: "about:blank")!)

    var title: String {
        switch kind {
        case .website: return url.host ?? "Website"
        case .local: return url.deletingLastPathComponent().lastPathComponent
        case .builtIn: return "Orbit"
        }
    }

    func allowsNavigation(to destination: URL) -> Bool {
        switch kind {
        case .website:
            return destination.scheme?.lowercased() == "https"
                && destination.host?.lowercased() == url.host?.lowercased()
                && (destination.port ?? 443) == (url.port ?? 443)
                && destination.user == nil && destination.password == nil
        case .local:
            guard destination.isFileURL else { return false }
            let root = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path + "/"
            return destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root)
        case .builtIn: return destination.absoluteString == "about:blank"
        }
    }

    enum SourceError: LocalizedError {
        case address, document, missingIndex
        var errorDescription: String? {
            switch self {
            case .address: return "Enter an HTTPS website address without a username or password."
            case .document: return "Choose an HTML document."
            case .missingIndex: return "This folder needs an index.html or index.htm file."
            }
        }
    }
}

enum WebWallpaperPointer {
    /// AppKit has a bottom-left origin; web pages use a top-left origin.
    static func normalized(_ point: CGPoint, in frame: CGRect) -> CGPoint? {
        guard frame.width > 0, frame.height > 0, point.x.isFinite, point.y.isFinite,
              frame.contains(point) else { return nil }
        return CGPoint(x: (point.x - frame.minX) / frame.width,
                       y: 1 - (point.y - frame.minY) / frame.height)
    }

    static func script(for point: CGPoint) -> String {
        """
        (() => {
          const nx = \(point.x), ny = \(point.y), x = nx * innerWidth, y = ny * innerHeight;
          const style = document.documentElement.style;
          style.setProperty('--pointer-x', String(nx)); style.setProperty('--pointer-y', String(ny));
          window.dispatchEvent(new CustomEvent('wallpaperpointer', {detail:{x:nx,y:ny,clientX:x,clientY:y}}));
          const target = document.elementFromPoint(x,y) || document;
          target.dispatchEvent(new MouseEvent('mousemove', {clientX:x,clientY:y,bubbles:true}));
          if (window.PointerEvent) target.dispatchEvent(new PointerEvent('pointermove', {clientX:x,clientY:y,bubbles:true,pointerType:'mouse'}));
        })();
        """
    }
}

enum OrbitWallpaper {
    static let html = #"""
    <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Orbit</title><style>
    html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#070c19}canvas{display:block;width:100%;height:100%}
    .signature{position:absolute;right:4vw;bottom:5vh;color:#a7b6d7;font:11px -apple-system,sans-serif;letter-spacing:.4em;opacity:.55;pointer-events:none}
    </style><canvas aria-label="A field of stars and orbital light responding to your pointer"></canvas><div class="signature">O R B I T</div>
    <script>
    const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
    let w=0,h=0,px=.5,py=.5,tx=.5,ty=.5,last=0;
    const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
    const stars=Array.from({length:105},(_,i)=>({x:((i*73.37)%101)/101,y:((i*31.17)%97)/97,z:.25+(i%7)/9}));
    function resize(){w=innerWidth;h=innerHeight;const d=Math.min(devicePixelRatio,1.5);canvas.width=w*d;canvas.height=h*d;ctx.setTransform(d,0,0,d,0,0)}
    addEventListener('resize',resize);resize();
    addEventListener('wallpaperpointer',e=>{tx=e.detail.x;ty=e.detail.y;window.lastWallpaperPointer=e.detail});
    addEventListener('mousemove',e=>{tx=e.clientX/w;ty=e.clientY/h});
    function draw(now){requestAnimationFrame(draw);if(now-last<33)return;last=now;px+=(tx-px)*.08;py+=(ty-py)*.08;
      const t=reduced?0:now*.00006,cx=w*(.52+(px-.5)*.10),cy=h*(.48+(py-.5)*.09),r=Math.min(w,h)*.34;
      ctx.fillStyle='#070c19';ctx.fillRect(0,0,w,h);
      const glow=ctx.createRadialGradient(cx,cy,0,cx,cy,r*1.9);glow.addColorStop(0,'#192d50');glow.addColorStop(.5,'#101c35');glow.addColorStop(1,'#070c19');ctx.fillStyle=glow;ctx.fillRect(0,0,w,h);
      for(const s of stars){ctx.fillStyle=`rgba(185,211,242,${s.z*.7})`;ctx.beginPath();ctx.arc(s.x*w+(px-.5)*s.z*28,s.y*h+(py-.5)*s.z*22,s.z*1.5,0,Math.PI*2);ctx.fill()}
      ctx.save();ctx.translate(cx,cy);ctx.rotate(-.34+(px-.5)*.12);
      for(let i=0;i<5;i++){ctx.beginPath();ctx.ellipse(0,0,r*(1+i*.13),r*(.36+i*.055),0,0,Math.PI*2);ctx.strokeStyle=`rgba(116,173,232,${.32-i*.045})`;ctx.lineWidth=i===0?1.5:1;ctx.stroke()}
      for(let i=0;i<3;i++){const a=t*(.3+i*.09)+i*2.15,rr=r*(1+i*.22);const x=Math.cos(a)*rr,y=Math.sin(a)*rr*(.36+i*.04);ctx.shadowColor=i===1?'#e7b47a':'#9dd1f8';ctx.shadowBlur=18;ctx.fillStyle=i===1?'#f1cb96':'#c5e5ff';ctx.beginPath();ctx.arc(x,y,i===1?4:2.8,0,Math.PI*2);ctx.fill()}
      ctx.restore();
    }requestAnimationFrame(draw);
    </script></html>
    """#
}
