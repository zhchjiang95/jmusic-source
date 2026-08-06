use crate::models::lyrics::Lyrics;
use crate::network::netease;

/// 获取网易云歌词
#[flutter_rust_bridge::frb]
pub async fn get_netease_lyrics(id: String) -> Result<Lyrics, String> {
    netease::get_lyrics(&id).await
}

/// 解析 LRC 文本为 Lyrics 结构
#[flutter_rust_bridge::frb(sync)]
pub fn parse_lrc_text(lrc_text: String) -> Lyrics {
    Lyrics::parse_lrc(&lrc_text)
}
