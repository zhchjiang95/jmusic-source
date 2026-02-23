use reqwest::header::{HeaderMap, REFERER, USER_AGENT};
use serde::Deserialize;

use crate::models::lyrics::Lyrics;
use crate::models::song::{QQMusicSearchResult, Singer};

/// QQ 音乐搜索响应数据结构
#[derive(Debug, Deserialize)]
struct SearchResponse {
    code: i32,
    data: Option<SearchData>,
}

#[derive(Debug, Deserialize)]
struct SearchData {
    song: Option<SearchSongData>,
}

#[derive(Debug, Deserialize)]
struct SearchSongData {
    list: Vec<SearchSongItem>,
}

#[derive(Debug, Deserialize)]
struct SearchSongItem {
    songmid: String,
    songname: String,
    albummid: String,
    albumname: String,
    singer: Vec<SearchSinger>,
    interval: u64,
}

#[derive(Debug, Deserialize)]
struct SearchSinger {
    id: u64,
    mid: String,
    name: String,
}

/// QQ 音乐歌词响应
#[derive(Debug, Deserialize)]
struct LyricResponse {
    retcode: i32,
    lyric: Option<String>,
}

/// 构建带有必要 Header 的 HTTP 客户端
fn build_client() -> Result<reqwest::Client, String> {
    let mut headers = HeaderMap::new();
    headers.insert(REFERER, "https://y.qq.com/".parse().unwrap());
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

/// 搜索歌曲（通过关键词匹配本地歌曲信息）
pub async fn search_song(keyword: &str) -> Result<Vec<QQMusicSearchResult>, String> {
    let client = build_client()?;
    let url = format!(
        "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w={}&format=json&n=5",
        urlencoding(keyword)
    );

    let resp: SearchResponse = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("搜索请求失败: {}", e))?
        .json()
        .await
        .map_err(|e| format!("解析搜索响应失败: {}", e))?;

    if resp.code != 0 {
        return Err(format!("QQ 音乐搜索接口返回错误码: {}", resp.code));
    }

    let results = resp
        .data
        .and_then(|d| d.song)
        .map(|s| {
            s.list
                .into_iter()
                .map(|item| QQMusicSearchResult {
                    songmid: item.songmid,
                    songname: item.songname,
                    albummid: item.albummid,
                    albumname: item.albumname,
                    singer: item
                        .singer
                        .into_iter()
                        .map(|s| Singer {
                            id: s.id,
                            mid: s.mid,
                            name: s.name,
                        })
                        .collect(),
                    interval: item.interval,
                })
                .collect()
        })
        .unwrap_or_default();

    Ok(results)
}

/// 获取歌词
pub async fn get_lyrics(songmid: &str) -> Result<Lyrics, String> {
    let client = build_client()?;
    let url = format!(
        "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg?songmid={}&format=json&nobase64=1",
        songmid
    );

    let resp: LyricResponse = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("歌词请求失败: {}", e))?
        .json()
        .await
        .map_err(|e| format!("解析歌词响应失败: {}", e))?;

    if resp.retcode != 0 {
        return Err(format!("QQ 音乐歌词接口返回错误码: {}", resp.retcode));
    }

    let lyric_text = resp.lyric.unwrap_or_default();

    // QQ 音乐歌词中的 HTML 实体解码
    let decoded = html_entity_decode(&lyric_text);

    Ok(Lyrics::parse_lrc(&decoded))
}

/// 获取专辑封面 URL
pub fn get_cover_url(albummid: &str) -> String {
    format!(
        "http://y.gtimg.cn/music/photo_new/T002R500x500M000{}.jpg",
        albummid
    )
}

/// 下载专辑封面图片
pub async fn download_cover(albummid: &str) -> Result<Vec<u8>, String> {
    let client = build_client()?;
    let url = get_cover_url(albummid);

    let bytes = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("下载封面失败: {}", e))?
        .bytes()
        .await
        .map_err(|e| format!("读取封面数据失败: {}", e))?;

    Ok(bytes.to_vec())
}

/// 简单的 URL 编码
fn urlencoding(s: &str) -> String {
    let mut result = String::new();
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                result.push(byte as char);
            }
            _ => {
                result.push_str(&format!("%{:02X}", byte));
            }
        }
    }
    result
}

/// HTML 实体解码（处理 QQ 音乐歌词中的 &#xx; 格式）
fn html_entity_decode(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '&' && chars.peek() == Some(&'#') {
            chars.next(); // 跳过 '#'
            let mut num_str = String::new();
            while let Some(&d) = chars.peek() {
                if d == ';' {
                    chars.next();
                    break;
                }
                num_str.push(d);
                chars.next();
            }
            if let Ok(num) = num_str.parse::<u32>() {
                if let Some(decoded_char) = char::from_u32(num) {
                    result.push(decoded_char);
                    continue;
                }
            }
            // 解码失败，保留原文
            result.push('&');
            result.push('#');
            result.push_str(&num_str);
            result.push(';');
        } else {
            result.push(c);
        }
    }

    result
}
