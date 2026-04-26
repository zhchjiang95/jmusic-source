use reqwest::header::{HeaderMap, REFERER, USER_AGENT};
use serde::Deserialize;
use crate::models::lyrics::Lyrics;

#[derive(Debug, Deserialize)]
struct NeteaseLyricResponse {
    lyric: Option<String>,
    code: i32,
}

fn build_client() -> Result<reqwest::Client, String> {
    let mut headers = HeaderMap::new();
    headers.insert(REFERER, "https://music.163.com/".parse().unwrap());
    headers.insert(
        USER_AGENT,
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
            .parse()
            .unwrap(),
    );

    reqwest::Client::builder()
        .default_headers(headers)
        .build()
        .map_err(|e| format!("构建 HTTP 客户端失败: {}", e))
}

pub async fn get_lyrics(id: &str) -> Result<Lyrics, String> {
    let client = build_client()?;
    let url = format!("https://music.163.com/api/song/media?id={}", id);

    let text = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("网易云歌词请求失败: {}", e))?
        .text()
        .await
        .map_err(|e| format!("读取网易云歌词响应失败: {}", e))?;

    let resp: NeteaseLyricResponse = serde_json::from_str(&text)
        .map_err(|e| format!("解析网易云歌词 JSON 失败: {}", e))?;

    if resp.code != 200 {
        return Err(format!("网易云接口返回错误码: {}", resp.code));
    }

    let lyric_text = resp.lyric.unwrap_or_default();
    Ok(Lyrics::parse_lrc(&lyric_text))
}
