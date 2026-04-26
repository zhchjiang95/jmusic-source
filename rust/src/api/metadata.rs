use crate::models::lyrics::Lyrics;
use crate::models::song::QQMusicSearchResult;
use crate::network::qq_music;
use crate::network::netease;
use crate::storage::cache;

/// 搜索歌曲信息（通过 QQ 音乐接口）
#[flutter_rust_bridge::frb]
pub async fn search_song_online(keyword: String) -> Result<Vec<QQMusicSearchResult>, String> {
    qq_music::search_song(&keyword).await
}

/// 获取歌词（优先从缓存读取，无缓存则在线获取）
#[flutter_rust_bridge::frb]
pub async fn get_lyrics(songmid: String) -> Result<Lyrics, String> {
    // 先检查本地缓存
    if let Some(cached_lrc) = cache::load_cached_lyrics(&songmid) {
        return Ok(Lyrics::parse_lrc(&cached_lrc));
    }

    // 从 QQ 音乐在线获取
    let lyrics = qq_music::get_lyrics(&songmid).await?;

    // TODO: 缓存原始 LRC 文本（当前 API 返回的是解析后的结构，后续优化）

    Ok(lyrics)
}

/// 获取网易云歌词
#[flutter_rust_bridge::frb]
pub async fn get_netease_lyrics(id: String) -> Result<Lyrics, String> {
    netease::get_lyrics(&id).await
}

/// 获取专辑封面（优先从缓存读取，无缓存则在线下载）
#[flutter_rust_bridge::frb]
pub async fn get_cover(albummid: String) -> Result<Vec<u8>, String> {
    // 先检查本地缓存
    if let Some(cached_cover) = cache::load_cached_cover(&albummid) {
        return Ok(cached_cover);
    }

    // 在线下载
    let cover_data = qq_music::download_cover(&albummid).await?;

    // 缓存到本地
    cache::save_cover_cache(&albummid, &cover_data)?;

    Ok(cover_data)
}

/// 获取缓存的封面文件路径
#[flutter_rust_bridge::frb(sync)]
pub fn get_cover_cache_path(albummid: String) -> Option<String> {
    cache::get_cover_cache_path(&albummid)
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
