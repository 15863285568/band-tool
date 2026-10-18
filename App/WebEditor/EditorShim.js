/*
 * MiFace Studio — Electron compatibility layer for the Xiaomi watch-face
 * editor.  Served from the loopback server so the original editor bundle can
 * run unmodified inside WKWebView.
 */
(function () {
  if (window.__MIFACE_SHIM__) return;
  window.__MIFACE_SHIM__ = true;
  if (!window.Buffer && window.buffer) {
    window.Buffer = window.buffer.Buffer || window.buffer;
  }

  try {
    Object.defineProperty(navigator, 'platform', { get: function () { return 'MacIntel'; } });
  } catch (e) {}

  var PORT = __MIFACE_PORT__;
  var TOKEN = '__MIFACE_TOKEN__';
  var BASE = 'http://127.0.0.1:' + PORT + '/_api';

  function encodeQuery(params) {
    return Object.keys(params).map(function (k) {
      return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
    }).join('&');
  }
  function request(method, path, params, body, responseType) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, BASE + path + (params ? '?' + encodeQuery(params) : ''), false);
    xhr.setRequestHeader('X-MiFace-Token', TOKEN);
    if (responseType) xhr.responseType = responseType;
    xhr.send(body == null ? null : body);
    if (xhr.status < 200 || xhr.status >= 300) {
      var message = '';
      try { message = xhr.responseText || ''; } catch (e) {}
      var error = new Error('MiFace fs ' + path + ': ' + xhr.status + ' ' + message);
      error.code = xhr.status === 404 ? 'ENOENT' : 'EIO';
      throw error;
    }
    return xhr;
  }
  function getText(path, params) { return request('GET', path, params).responseText; }
  function getBytes(path, params) {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', BASE + path + (params ? '?' + encodeQuery(params) : ''), false);
    xhr.setRequestHeader('X-MiFace-Token', TOKEN);
    // Synchronous XHR forbids responseType=arraybuffer; x-user-defined maps
    // every byte to one UTF-16 code unit so we can recover binary data.
    xhr.overrideMimeType('text/plain; charset=x-user-defined');
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 300) {
      var error = new Error('MiFace fs ' + path + ': ' + xhr.status);
      error.code = xhr.status === 404 ? 'ENOENT' : 'EIO';
      throw error;
    }
    var text = xhr.responseText || '';
    var bytes = new Uint8Array(text.length);
    for (var i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xFF;
    return bytes;
  }
  function postJSON(path, object) {
    var xhr = request('POST', path, null, JSON.stringify(object || {}));
    return xhr.responseText;
  }
  function postBytes(path, params, bytes) {
    return request('POST', path, params, bytes).responseText;
  }
  function toBytes(data, encoding) {
    if (data == null) return new Uint8Array(0);
    if (typeof data === 'string') {
      if (encoding === 'base64') {
        var raw = atob(data), out = new Uint8Array(raw.length);
        for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
        return out;
      }
      if (encoding === 'latin1' || encoding === 'binary') {
        var arr = new Uint8Array(data.length);
        for (var j = 0; j < data.length; j++) arr[j] = data.charCodeAt(j) & 255;
        return arr;
      }
      return new TextEncoder().encode(data);
    }
    if (data instanceof Uint8Array) return data;
    if (data instanceof ArrayBuffer) return new Uint8Array(data);
    if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    if (Array.isArray(data)) return new Uint8Array(data);
    if (typeof data === 'object' && data.type === 'Buffer' && Array.isArray(data.data)) return new Uint8Array(data.data);
    return new Uint8Array(0);
  }
  function makeBuffer(bytes) {
    if (typeof Buffer !== 'undefined') return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return bytes;
  }

  var path = {
    sep: '/',
    join: function () {
      var parts = Array.prototype.slice.call(arguments).filter(function (p) { return p != null && p !== ''; });
      var joined = parts.join('/').replace(/\/+/g, '/');
      if (parts.length && String(parts[0]).charAt(0) === '/' && joined.charAt(0) !== '/') joined = '/' + joined;
      return joined.replace(/\/$/, '') || '/';
    },
    resolve: function () {
      var out = [];
      Array.prototype.slice.call(arguments).join('/').split('/').forEach(function (p) {
        if (!p || p === '.') return;
        if (p === '..') out.pop(); else out.push(p);
      });
      return '/' + out.join('/');
    },
    dirname: function (p) {
      p = String(p || '').replace(/\/+$/, '');
      var i = p.lastIndexOf('/');
      return i <= 0 ? (i === 0 ? '/' : '.') : p.slice(0, i);
    },
    basename: function (p, ext) {
      p = String(p || '').replace(/\/+$/, '');
      var b = p.slice(p.lastIndexOf('/') + 1);
      if (ext && b.slice(-ext.length) === ext) b = b.slice(0, -ext.length);
      return b;
    },
    extname: function (p) {
      var b = path.basename(p);
      var i = b.lastIndexOf('.');
      return i <= 0 ? '' : b.slice(i);
    },
    normalize: function (p) { return path.resolve(p); },
    isAbsolute: function (p) { return String(p).charAt(0) === '/'; },
    relative: function (a, b) { return b; }
  };

  function readFileSync(p, options) {
    var encoding = typeof options === 'string' ? options : (options && options.encoding);
    var bytes = getBytes('/read', { path: String(p) });
    if (encoding) return new TextDecoder('utf-8').decode(bytes);
    return makeBuffer(bytes);
  }
  function writeFileSync(p, data, options) {
    var encoding = typeof options === 'string' ? options : (options && options.encoding);
    var bytes = toBytes(data, encoding);
    postBytes('/write', { path: String(p) }, bytes);
  }
  function existsSync(p) {
    try { return getText('/exists', { path: String(p) }) === '1'; } catch (e) { return false; }
  }
  function readdirSync(p) { return JSON.parse(getText('/readdir', { path: String(p) })); }
  function mkdirSync(p) { postJSON('/mkdir', { path: String(p) }); }
  function rmSync(p) { postJSON('/rm', { path: String(p) }); }
  function statSync(p) {
    var s = JSON.parse(getText('/stat', { path: String(p) }));
    s.isFile = function () { return s.type === 'file'; };
    s.isDirectory = function () { return s.type === 'dir'; };
    return s;
  }
  function copyFileSync(a, b) { postJSON('/copy', { from: String(a), to: String(b) }); }
  function cpSync(a, b) { postJSON('/cp', { from: String(a), to: String(b) }); }
  function renameSync(a, b) { postJSON('/rename', { from: String(a), to: String(b) }); }

  // --- file descriptors ---------------------------------------------------
  // The export pipeline opens a temp file, streams the archive into it and
  // then renames it into place.  Descriptors are emulated with an append-only
  // buffer so openSync/writeSync/closeSync behave like the Node originals.
  var openFiles = {};
  var nextFd = 1000;

  function openSync(p, flags) {
    var read = false;
    var truncate = false;
    var append = false;
    if (typeof flags === 'string') {
      if (flags.charAt(0) === 'r' && flags.indexOf('+') === -1) {
        read = true;
      } else {
        if (flags.indexOf('w') !== -1) truncate = true;
        if (flags.indexOf('a') !== -1) append = true;
      }
      if (flags.indexOf('+') !== -1) read = true;
    } else if (typeof flags === 'number') {
      // fs.constants: O_RDONLY=0, O_WRONLY=1, O_RDWR=2, O_CREAT=64, O_TRUNC=512, O_APPEND=1024
      read = (flags & 3) !== 1;
      truncate = (flags & 512) !== 0;
      append = (flags & 1024) !== 0;
    }
    var existing = new Uint8Array(0);
    if (read && existsSync(p)) {
      try { existing = toBytes(readFileSync(p)); } catch (e) { existing = new Uint8Array(0); }
    }
    if (!truncate && !read && existsSync(p)) {
      try { existing = toBytes(readFileSync(p)); } catch (e) { existing = new Uint8Array(0); }
    }
    if (truncate) existing = new Uint8Array(0);
    var fd = nextFd++;
    openFiles[fd] = { path: String(p), chunks: [existing], length: existing.length, append: append };
    return fd;
  }

  function writeSync(fd, data, offset, encoding) {
    var handle = openFiles[fd];
    if (!handle) throw Object.assign(new Error('EBADF'), { code: 'EBADF' });
    if (typeof offset === 'string') encoding = offset;
    var bytes = toBytes(data, encoding);
    handle.chunks.push(bytes);
    handle.length += bytes.length;
    handle.touched = true;
    return bytes.length;
  }

  function readSync(fd, buffer, offset, length) {
    var handle = openFiles[fd];
    if (!handle) throw Object.assign(new Error('EBADF'), { code: 'EBADF' });
    var all = flushHandle(handle);
    var count = Math.min(length, all.length);
    buffer.set(all.subarray(0, count), offset || 0);
    return count;
  }

  function flushHandle(handle) {
    var all = new Uint8Array(handle.length);
    var at = 0;
    handle.chunks.forEach(function (chunk) { all.set(chunk, at); at += chunk.length; });
    handle.chunks = [all];
    handle.length = all.length;
    return all;
  }

  function closeSync(fd) {
    var handle = openFiles[fd];
    if (!handle) return;
    delete openFiles[fd];
    if (handle.length > 0 || handle.touched) {
      writeFileSync(handle.path, flushHandle(handle));
    }
  }

  function ftruncateSync(fd, len) {
    var handle = openFiles[fd];
    if (!handle) throw Object.assign(new Error('EBADF'), { code: 'EBADF' });
    var all = flushHandle(handle);
    var size = typeof len === 'number' ? len : 0;
    var next = new Uint8Array(size);
    next.set(all.subarray(0, Math.min(size, all.length)));
    handle.chunks = [next];
    handle.length = size;
    return 0;
  }

  function fstatSync(fd) {
    var handle = openFiles[fd];
    if (!handle) throw Object.assign(new Error('EBADF'), { code: 'EBADF' });
    var stat = {
      size: handle.length,
      type: 'file',
      isFile: function () { return true; },
      isDirectory: function () { return false; }
    };
    return stat;
  }

  var fs = {
    promises: {
      readFile: function (p, o) { return Promise.resolve().then(function () { return readFileSync(p, o); }); },
      writeFile: function (p, d, o) { return Promise.resolve().then(function () { return writeFileSync(p, d, o); }); },
      readdir: function (p) { return Promise.resolve(readdirSync(p)); },
      mkdir: function (p) { return Promise.resolve().then(function () { return mkdirSync(p); }); },
      rm: function (p) { return Promise.resolve().then(function () { return rmSync(p); }); },
      unlink: function (p) { return Promise.resolve().then(function () { return rmSync(p); }); },
      stat: function (p) { return Promise.resolve().then(function () { return statSync(p); }); },
      copyFile: function (a, b) { return Promise.resolve().then(function () { return copyFileSync(a, b); }); },
      cp: function (a, b) { return Promise.resolve().then(function () { return cpSync(a, b); }); },
      rename: function (a, b) { return Promise.resolve().then(function () { return renameSync(a, b); }); },
      access: function (p) { return existsSync(p) ? Promise.resolve() : Promise.reject(Object.assign(new Error('ENOENT'), { code: 'ENOENT' })); }
    },
    readFileSync: readFileSync,
    writeFileSync: writeFileSync,
    existsSync: existsSync,
    readdirSync: readdirSync,
    mkdirSync: mkdirSync,
    rmSync: rmSync,
    unlinkSync: rmSync,
    statSync: statSync,
    lstatSync: statSync,
    copyFileSync: copyFileSync,
    cpSync: cpSync,
    renameSync: renameSync,
    createWriteStream: function (p) {
      var chunks = [];
      return {
        write: function (d) { chunks.push(toBytes(d)); return true; },
        end: function (cb) {
          var length = chunks.reduce(function (sum, c) { return sum + c.length; }, 0);
          var all = new Uint8Array(length), offset = 0;
          chunks.forEach(function (c) { all.set(c, offset); offset += c.length; });
          writeFileSync(p, all);
          if (cb) cb();
        },
        on: function () { return this; },
        once: function () { return this; },
        emit: function () { return false; }
      };
    },
    createReadStream: function (p) {
      var listeners = {};
      var stream = {
        on: function (event, fn) {
          (listeners[event] = listeners[event] || []).push(fn);
          return stream;
        },
        once: function (event, fn) { return stream.on(event, fn); },
        pipe: function () { return stream; },
        destroy: function () {},
        emit: function (event, value) {
          (listeners[event] || []).forEach(function (fn) { fn(value); });
          return true;
        }
      };
      setTimeout(function () {
        try {
          stream.emit('data', readFileSync(p));
          stream.emit('end');
        } catch (e) {
          stream.emit('error', e);
        }
      }, 0);
      return stream;
    },
    openSync: openSync,
    closeSync: closeSync,
    writeSync: writeSync,
    writevSync: function (fd, buffers) {
      var total = 0;
      (buffers || []).forEach(function (item) {
        total += writeSync(fd, item && item.buffer ? item.buffer : item);
      });
      return total;
    },
    readSync: readSync,
    ftruncateSync: ftruncateSync,
    fstatSync: fstatSync,
    truncateSync: function (p, len) {
      var bytes = existsSync(p) ? toBytes(readFileSync(p)) : new Uint8Array(0);
      var size = typeof len === 'number' ? len : 0;
      var next = new Uint8Array(size);
      next.set(bytes.subarray(0, Math.min(size, bytes.length)));
      writeFileSync(p, next);
    },
    constants: {
      O_RDONLY: 0, O_WRONLY: 1, O_RDWR: 2,
      O_CREAT: 64, O_EXCL: 128, O_TRUNC: 512, O_APPEND: 1024,
      F_OK: 0, R_OK: 4, W_OK: 2, X_OK: 1,
      COPYFILE_EXCL: 1
    }
  };

  var appInfo = {
    name: 'MiFace Studio',
    isPackaged: true,
    version: '1.0.0',
    appPath: '/app',
    platform: 'darwin',
    versions: { chrome: '605.1.15', electron: '28.0.0', node: '20.0.0' }
  };

  var ipcRenderer = {
    invoke: function (channel, payload) {
      if (channel === 'get_app_info') return Promise.resolve(appInfo);
      if (channel === 'get_path') {
        return Promise.resolve(getText('/path', { key: (payload && payload.pathKey) || 'userData' }));
      }
      if (channel === 'exec-file') {
        return Promise.resolve().then(function () {
          var result = JSON.parse(postJSON('/exec', {
            filename: payload.execFilename,
            args: payload.commands || []
          }));
          if (result.error) throw new Error(result.error);
          return { stdout: result.stdout || '', stderr: result.stderr || '' };
        });
      }
      if (channel === 'pick_file') {
        return pickWithFileInput(payload || {});
      }
      if (channel === 'close' || channel === 'exit' || channel === 'reload' ||
          channel === 'minimize' || channel === 'open_devtools' || channel === 'exec_adb_file') {
        return Promise.resolve(null);
      }
      return Promise.resolve(null);
    },
    send: function () {}, on: function () {}, once: function () {}, removeListener: function () {}
  };

  function pickWithFileInput(payload) {
    if (payload.mode === 'dir') return Promise.resolve([]);
    return new Promise(function (resolve) {
      var extensions = payload.extensions || [];
      var accept = extensions.length
        ? extensions.map(function (e) { return '.' + String(e).replace(/^\./, ''); }).join(',')
        : 'image/*';
      var input = document.createElement('input');
      input.type = 'file';
      input.accept = accept;
      input.multiple = !!payload.multi;
      input.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;opacity:0.01;z-index:-1;';
      document.body.appendChild(input);

      var settled = false;
      function finish(paths) {
        if (settled) return;
        settled = true;
        try { input.remove(); } catch (e) {}
        resolve(paths);
      }

      input.addEventListener('change', function () {
        var files = Array.prototype.slice.call(input.files || []);
        if (!files.length) { finish([]); return; }
        var pending = files.length;
        var paths = new Array(files.length);
        files.forEach(function (file, index) {
          var reader = new FileReader();
          reader.onload = function () {
            var bytes = new Uint8Array(reader.result);
            var safe = (file.name || 'image.png').replace(/[\\/:*?"<>|]/g, '_');
            var path = '/workspace/Imports/' + Date.now() + '-' + index + '-' + safe;
            try {
              writeFileSync(path, bytes);
              paths[index] = path;
            } catch (e) {
              console.error('pick_file write failed', e);
            }
            pending -= 1;
            if (pending === 0) finish(paths.filter(Boolean));
          };
          reader.onerror = function () {
            pending -= 1;
            if (pending === 0) finish(paths.filter(Boolean));
          };
          reader.readAsArrayBuffer(file);
        });
      });

      window.addEventListener('focus', function () {
        window.setTimeout(function () {
          if (!settled && (!input.files || input.files.length === 0)) finish([]);
        }, 900);
      }, { once: true });

      input.click();
    });
  }

  var shell = {
    openExternal: function (url) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miface) {
        window.webkit.messageHandlers.miface.postMessage({ type: 'openURL', url: String(url) });
      }
      return Promise.resolve();
    },
    showItemInFolder: function () { return Promise.resolve(); },
    openPath: function () { return Promise.resolve(''); }
  };

  var os = {
    platform: function () { return 'darwin'; },
    homedir: function () { return '/userData'; },
    tmpdir: function () { return '/temp'; },
    cpus: function () { return [{ model: 'Apple', speed: 2400, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }]; },
    availableParallelism: function () { return 4; },
    totalmem: function () { return 4 * 1024 * 1024 * 1024; },
    freemem: function () { return 2 * 1024 * 1024 * 1024; }
  };

  window.electron = {
    os: os,
    path: path,
    fs: fs,
    shell: shell,
    ipcRenderer: ipcRenderer,
    versionType: 'normal',
    fileToMd5: function (p) {
      try { return Promise.resolve(getText('/md5', { path: String(p) }).slice(8, 15)); }
      catch (e) { return Promise.resolve('0000000'); }
    }
  };

  if (!window.require) window.require = function () { return {}; };
  if (!window.process) {
    window.process = {
      platform: 'darwin',
      versions: {},
      env: {},
      cwd: function () { return '/'; },
      cpuUsage: function () { return { user: 0, system: 0 }; }
    };
  }
  if (!window.global) window.global = window;

  function notify(payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miface) {
      window.webkit.messageHandlers.miface.postMessage(payload);
    }
  }

  // A download in Electron usually opens a save dialog.  In the app we put
  // the file into the export directory and refresh the native library.
  var originalCreateElement = document.createElement.bind(document);
  document.createElement = function (tag) {
    var element = originalCreateElement(tag);
    if (String(tag).toLowerCase() === 'a') {
      var originalClick = element.click;
      element.click = function () {
        if (element.href && element.href.indexOf('blob:') === 0) {
          fetch(element.href).then(function (response) { return response.arrayBuffer(); }).then(function (buffer) {
            var name = element.download || 'watchface.bin';
            writeFileSync('/workspace/Exports/' + name, new Uint8Array(buffer));
            notify({ type: 'export', name: name });
          }).catch(function (error) {
            notify({ type: 'toast', text: '导出失败：' + error.message });
          });
          return;
        }
        return originalClick.apply(element, arguments);
      };
    }
    return element;
  };
})();
