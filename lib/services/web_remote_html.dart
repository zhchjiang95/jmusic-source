/// 内嵌的 Web 遥控页面 HTML
const String remoteControlHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<title>JMusic 遥控</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
:root {
  --bg: #0a0a0a;
  --surface: #1a1a1a;
  --primary: #6366f1;
  --primary-dim: #4f46e5;
  --text: #f1f1f1;
  --text-muted: #888;
  --radius: 16px;
}
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 24px 16px;
  -webkit-tap-highlight-color: transparent;
}
.status {
  font-size: 12px;
  color: var(--text-muted);
  margin-bottom: 24px;
}
.status .dot {
  display: inline-block;
  width: 8px; height: 8px;
  border-radius: 50%;
  background: #ef4444;
  margin-right: 6px;
  vertical-align: middle;
  transition: background 0.3s;
}
.status .dot.connected { background: #22c55e; }

.song-info {
  text-align: center;
  margin-bottom: 32px;
  width: 100%;
  max-width: 360px;
}
.song-title {
  font-size: 20px;
  font-weight: 700;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.song-artist {
  font-size: 14px;
  color: var(--text-muted);
  margin-top: 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.progress-section {
  width: 100%;
  max-width: 360px;
  margin-bottom: 32px;
}
.progress-bar {
  width: 100%;
  height: 4px;
  background: #333;
  border-radius: 2px;
  overflow: hidden;
  cursor: pointer;
  position: relative;
}
.progress-fill {
  height: 100%;
  background: var(--primary);
  border-radius: 2px;
  transition: width 0.3s linear;
}
.progress-times {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  color: var(--text-muted);
  margin-top: 6px;
}

.controls {
  display: flex;
  align-items: center;
  gap: 20px;
  margin-bottom: 32px;
}
.btn {
  background: none;
  border: none;
  color: var(--text);
  cursor: pointer;
  padding: 12px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s;
}
.btn:active { background: rgba(255,255,255,0.1); }
.btn svg { width: 28px; height: 28px; fill: currentColor; }
.btn-play {
  background: var(--primary);
  width: 64px; height: 64px;
  border-radius: 50%;
}
.btn-play:active { background: var(--primary-dim); }
.btn-play svg { width: 32px; height: 32px; }

.volume-section {
  width: 100%;
  max-width: 360px;
  display: flex;
  align-items: center;
  gap: 12px;
}
.volume-section svg { width: 20px; height: 20px; fill: var(--text-muted); flex-shrink: 0; }
.volume-slider {
  flex: 1;
  -webkit-appearance: none;
  appearance: none;
  height: 4px;
  background: #333;
  border-radius: 2px;
  outline: none;
}
.volume-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 16px; height: 16px;
  border-radius: 50%;
  background: var(--primary);
  cursor: pointer;
}

.playlist-section {
  width: 100%;
  max-width: 360px;
  margin-top: 32px;
}
.playlist-header {
  font-size: 14px;
  color: var(--text-muted);
  margin-bottom: 12px;
}
.playlist {
  max-height: 240px;
  overflow-y: auto;
  border-radius: var(--radius);
  background: var(--surface);
}
.playlist-item {
  padding: 12px 16px;
  border-bottom: 1px solid #222;
  cursor: pointer;
  transition: background 0.2s;
  display: flex;
  align-items: center;
  gap: 12px;
}
.playlist-item:last-child { border-bottom: none; }
.playlist-item:active { background: rgba(255,255,255,0.05); }
.playlist-item.active { color: var(--primary); }
.playlist-item .idx { font-size: 12px; color: var(--text-muted); min-width: 24px; }
.playlist-item .name {
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  font-size: 14px;
}
</style>
</head>
<body>

<div class="status"><span class="dot" id="dot"></span><span id="statusText">连接中...</span></div>

<div class="song-info">
  <div class="song-title" id="title">--</div>
  <div class="song-artist" id="artist">--</div>
</div>

<div class="progress-section">
  <div class="progress-bar" id="progressBar">
    <div class="progress-fill" id="progressFill"></div>
  </div>
  <div class="progress-times">
    <span id="posTime">00:00</span>
    <span id="durTime">00:00</span>
  </div>
</div>

<div class="controls">
  <button class="btn" id="btnPrev" title="上一首">
    <svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>
  </button>
  <button class="btn btn-play" id="btnPlay" title="播放/暂停">
    <svg viewBox="0 0 24 24" id="playIcon"><path d="M8 5v14l11-7z"/></svg>
  </button>
  <button class="btn" id="btnNext" title="下一首">
    <svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>
  </button>
</div>

<div class="volume-section">
  <svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>
  <input type="range" class="volume-slider" id="volumeSlider" min="0" max="100" value="80">
</div>

<div class="playlist-section">
  <div class="playlist-header">播放列表 (<span id="plCount">0</span>)</div>
  <div class="playlist" id="playlist"></div>
</div>

<script>
var ws_url = "ws://" + location.host + "/ws";
var ws;
var state = {};
var reconnectTimer;

function connect() {
  ws = new WebSocket(ws_url);
  ws.onopen = function() {
    document.getElementById("dot").classList.add("connected");
    document.getElementById("statusText").textContent = "已连接";
    send({cmd: "get_state"});
  };
  ws.onclose = function() {
    document.getElementById("dot").classList.remove("connected");
    document.getElementById("statusText").textContent = "已断开，重连中...";
    reconnectTimer = setTimeout(connect, 2000);
  };
  ws.onerror = function() { ws.close(); };
  ws.onmessage = function(e) {
    try {
      var data = JSON.parse(e.data);
      Object.assign(state, data);
      render();
    } catch(ex) {}
  };
}

function send(obj) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function render() {
  document.getElementById("title").textContent = state.title || "--";
  document.getElementById("artist").textContent = state.artist || "--";

  var progress = state.duration > 0 ? (state.position / state.duration * 100) : 0;
  document.getElementById("progressFill").style.width = progress + "%";
  document.getElementById("posTime").textContent = fmtTime(state.position || 0);
  document.getElementById("durTime").textContent = fmtTime(state.duration || 0);

  var icon = document.getElementById("playIcon");
  if (state.isPlaying) {
    icon.innerHTML = '<path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/>';
  } else {
    icon.innerHTML = '<path d="M8 5v14l11-7z"/>';
  }

  document.getElementById("volumeSlider").value = Math.round((state.volume || 0) * 100);

  if (state.playlist) {
    var pl = document.getElementById("playlist");
    var count = document.getElementById("plCount");
    count.textContent = state.playlist.length;
    var html = "";
    for (var i = 0; i < state.playlist.length; i++) {
      var s = state.playlist[i];
      var cls = i === state.currentIndex ? "playlist-item active" : "playlist-item";
      html += '<div class="' + cls + '" data-idx="' + i + '">';
      html += '<span class="idx">' + (i + 1) + '</span>';
      html += '<span class="name">' + (s.title || "未知") + '</span>';
      html += '</div>';
    }
    pl.innerHTML = html;
  }
}

function fmtTime(ms) {
  var s = Math.floor(ms / 1000);
  var m = Math.floor(s / 60);
  return String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
}

document.getElementById("btnPlay").onclick = function() { send({cmd: "toggle"}); };
document.getElementById("btnPrev").onclick = function() { send({cmd: "prev"}); };
document.getElementById("btnNext").onclick = function() { send({cmd: "next"}); };

document.getElementById("volumeSlider").oninput = function(e) {
  send({cmd: "volume", value: parseInt(e.target.value) / 100});
};

document.getElementById("progressBar").onclick = function(e) {
  var rect = e.currentTarget.getBoundingClientRect();
  var ratio = (e.clientX - rect.left) / rect.width;
  send({cmd: "seek", value: ratio});
};

document.getElementById("playlist").onclick = function(e) {
  var item = e.target.closest(".playlist-item");
  if (item) {
    send({cmd: "play_index", value: parseInt(item.dataset.idx)});
  }
};

connect();
</script>
</body>
</html>
''';
