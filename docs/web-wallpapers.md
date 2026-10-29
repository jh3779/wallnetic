# Web wallpapers

Open **Web** in the navigation bar. **Use Orbit** starts the built-in offline scene. **Apply website** accepts an HTTPS URL; use the final URL if the website redirects to another host. **Open HTML folder** accepts a folder containing index.html (or index.htm) and its assets. Choose **Turn off web wallpaper** to reveal the system wallpaper, or select a video in Home to switch back.

Applying a web background turns off video auto-switch schedules. Pause and power events unload the page; Resume reloads it. Restore at launch is opt-in. No clicks or keyboard input are intercepted, so desktop icons stay usable.

Custom pages can handle pointer movement through:

```js
window.addEventListener('wallpaperpointer', ({ detail }) => {
  // x/y: normalized [0,1] with a top-left origin
  // clientX/clientY: viewport CSS pixel coordinates
  scene.setPointer(detail.x, detail.y);
});
```

The engine also sets CSS variables --pointer-x and --pointer-y and dispatches bubbling mousemove and pointermove events. These events are synthetic (isTrusted is false); CSS :hover and trusted user gestures are not provided. Mouse reaction therefore depends on the page.

The built-in Orbit source is in Models/WebWallpaperDocument.swift. See testing/web-wallpapers.md for verification and current limits.
