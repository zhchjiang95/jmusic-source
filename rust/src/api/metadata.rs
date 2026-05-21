use crate::models::lyrics::Lyrics;
use crate::models::song::QQMusicSearchResult;
use crate::network::qq_music;
use crate::network::netease;

/// 搜索歌曲信息（通过 QQ 音乐接口）
#[flutter_rust_bridge::frb]
pub async fn search_song_online(keyword: String) -> Result<Vec<QQMusicSearchResult>, String> {
    qq_music::search_song(&keyword).await
}

/// 获取歌词（在线获取）
#[flutter_rust_bridge::frb]
pub async fn get_lyrics(songmid: String) -> Result<Lyrics, String> {
    qq_music::get_lyrics(&songmid).await
}

/// 获取网易云歌词
#[flutter_rust_bridge::frb]
pub async fn get_netease_lyrics(id: String) -> Result<Lyrics, String> {
    netease::get_lyrics(&id).await
}

/// 获取专辑封面（在线下载）
#[flutter_rust_bridge::frb]
pub async fn get_cover(albummid: String) -> Result<Vec<u8>, String> {
    qq_music::download_cover(&albummid).await
}

/// 获取封面 URL（不下载）
#[flutter_rust_bridge::frb(sync)]
pub fn get_cover_url(albummid: String) -> String {
    qq_music::get_cover_url(&albummid)
}

/// 解析 LRC 文本为 Lyrics 结构
#[flutter_rust_bridge::frb(sync)]
pub fn parse_lrc_text(lrc_text: String) -> Lyrics {
    Lyrics::parse_lrc(&lrc_text)
}
