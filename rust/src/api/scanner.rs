use lofty::file::{AudioFile, TaggedFileExt};
use lofty::probe::Probe;
use lofty::tag::Accessor;
use walkdir::WalkDir;
use std::time::UNIX_EPOCH;

use crate::models::song::{Library, Song};
use crate::storage::library::{load_library, save_library};

/// 支持的音频格式
const SUPPORTED_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "wav", "ogg", "m4a", "aac", "wma", "ape",
];

/// 判断文件是否为支持的音频格式
fn is_audio_file(path: &std::path::Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| SUPPORTED_EXTENSIONS.contains(&ext.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// 扫描指定目录中的音乐文件
#[flutter_rust_bridge::frb]
pub fn scan_music_directory(dir_path: String) -> Result<Vec<Song>, String> {
    let mut songs = Vec::new();

    for entry in WalkDir::new(&dir_path)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();

        if !path.is_file() || !is_audio_file(path) {
            continue;
        }

        match parse_audio_file(path) {
            Ok(song) => songs.push(song),
            Err(e) => {
                log::warn!("解析文件失败 {:?}: {}", path, e);
            }
        }
    }

    Ok(songs)
}

/// 解析单个音频文件的元数据
fn parse_audio_file(path: &std::path::Path) -> Result<Song, String> {
    let file_path = path
        .to_str()
        .ok_or("无效的文件路径")?
        .to_string();

    // 获取文件元信息
    let metadata = std::fs::metadata(path)
        .map_err(|e| format!("读取文件元数据失败: {}", e))?;

    let file_size = metadata.len();
    let modified_at = metadata
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);

    // 获取文件格式
    let format = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("unknown")
        .to_lowercase();

    // 使用 lofty 读取音频标签
    let tagged_file = Probe::open(path)
        .map_err(|e| format!("无法打开文件: {}", e))?
        .read()
        .map_err(|e| format!("无法读取标签: {}", e))?;

    let properties = tagged_file.properties();
    let duration = properties.duration().as_secs_f64();

    // 尝试从所有标签中读取信息
    let tag = tagged_file.primary_tag().or_else(|| tagged_file.first_tag());

    let title = tag
        .and_then(|t| t.title().map(|s: std::borrow::Cow<str>| s.to_string()))
        .unwrap_or_else(|| {
            // 如果没有标签，用文件名作为标题
            path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("未知")
                .to_string()
        });

    let artist = tag
        .and_then(|t| t.artist().map(|s: std::borrow::Cow<str>| s.to_string()))
        .unwrap_or_else(|| "未知歌手".to_string());

    let album = tag
        .and_then(|t| t.album().map(|s: std::borrow::Cow<str>| s.to_string()))
        .unwrap_or_else(|| "未知专辑".to_string());

    Ok(Song {
        file_path,
        title,
        artist,
        album,
        duration,
        file_size,
        format,
        songmid: None,
        albummid: None,
        modified_at,
    })
}

/// 扫描并更新歌曲库（增量更新）
#[flutter_rust_bridge::frb]
pub fn scan_and_update_library(dir_path: String) -> Result<Library, String> {
    let mut library = load_library();

    // 扫描新目录
    let new_songs = scan_music_directory(dir_path.clone())?;

    // 合并：以文件路径为唯一标识
    let existing_paths: std::collections::HashSet<String> =
        library.songs.iter().map(|s| s.file_path.clone()).collect();

    for song in new_songs {
        if !existing_paths.contains(&song.file_path) {
            library.songs.push(song);
        }
    }

    // 记录扫描目录
    if !library.scan_dirs.contains(&dir_path) {
        library.scan_dirs.push(dir_path);
    }

    // 更新扫描时间
    library.last_scan_at = std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // 保存到 JSON
    save_library(&library)?;

    Ok(library)
}

/// 获取当前歌曲库
#[flutter_rust_bridge::frb(sync)]
pub fn get_library() -> Library {
    load_library()
}

/// 更新歌曲元数据（写入文件标签 + 更新本地歌曲库）
#[flutter_rust_bridge::frb]
pub fn update_song_metadata(
    file_path: String,
    title: String,
    artist: String,
    album: String,
) -> Result<(), String> {
    use lofty::config::WriteOptions;
    use lofty::tag::{Accessor, TagExt};
    use std::path::Path;

    let path = Path::new(&file_path);

    // 用 lofty 打开文件并写入标签
    let mut tagged_file = Probe::open(path)
        .map_err(|e| format!("无法打开文件: {}", e))?
        .read()
        .map_err(|e| format!("无法读取文件: {}", e))?;

    // 获取或创建主标签
    let tag = match tagged_file.primary_tag_mut() {
        Some(t) => t,
        None => {
            // 根据文件类型插入合适的标签
            let tag_type = tagged_file.primary_tag_type();
            tagged_file.insert_tag(lofty::tag::Tag::new(tag_type));
            tagged_file.primary_tag_mut().unwrap()
        }
    };

    // 设置标签字段
    tag.set_title(title.clone());
    tag.set_artist(artist.clone());
    tag.set_album(album.clone());

    // 写入到文件
    tag.save_to_path(path, WriteOptions::default())
        .map_err(|e| format!("写入标签失败: {}", e))?;

    // 更新歌曲库中对应歌曲的信息
    let mut library = load_library();
    if let Some(song) = library.songs.iter_mut().find(|s| s.file_path == file_path) {
        song.title = title;
        song.artist = artist;
        song.album = album;
    }
    save_library(&library)?;

    Ok(())
}

/// 读取文件中嵌入的封面图
#[flutter_rust_bridge::frb]
pub fn read_embedded_cover(file_path: String) -> Option<Vec<u8>> {
    use std::path::Path;

    let path = Path::new(&file_path);
    let tagged_file = Probe::open(path).ok()?.read().ok()?;
    let tag = tagged_file.primary_tag().or_else(|| tagged_file.first_tag())?;

    tag.pictures().first().map(|pic| pic.data().to_vec())
}

/// 读取文件中嵌入的歌词文本
#[flutter_rust_bridge::frb]
pub fn read_embedded_lyrics(file_path: String) -> Option<String> {
    use lofty::tag::ItemKey;
    use std::path::Path;

    let path = Path::new(&file_path);
    let tagged_file = Probe::open(path).ok()?.read().ok()?;
    let tag = tagged_file.primary_tag().or_else(|| tagged_file.first_tag())?;

    tag.get_string(&ItemKey::Lyrics)
        .map(|s| s.to_string())
        .filter(|s| !s.is_empty())
}

/// 将所有信息（标题/歌手/专辑/歌词/封面）写入源文件
#[flutter_rust_bridge::frb]
pub fn save_all_metadata(
    file_path: String,
    title: String,
    artist: String,
    album: String,
    lyrics_text: Option<String>,
    cover_data: Option<Vec<u8>>,
) -> Result<(), String> {
    save_all_metadata_impl(file_path, title, artist, album, lyrics_text, cover_data)
}

/// 实际写入逻辑（独立函数避免 FRB 宏干扰类型推断）
fn save_all_metadata_impl(
    file_path: String,
    title: String,
    artist: String,
    album: String,
    lyrics_text: Option<String>,
    cover_data: Option<Vec<u8>>,
) -> Result<(), String> {
    use lofty::config::WriteOptions;
    use lofty::picture::{MimeType, Picture, PictureType};
    use lofty::tag::{Accessor, ItemKey, ItemValue, TagExt, TagItem};
    use std::path::Path;

    let path = Path::new(&file_path);

    let mut tagged_file = Probe::open(path)
        .map_err(|e| format!("无法打开文件: {}", e))?
        .read()
        .map_err(|e| format!("无法读取文件: {}", e))?;

    let tag = match tagged_file.primary_tag_mut() {
        Some(t) => t,
        None => {
            let tag_type = tagged_file.primary_tag_type();
            tagged_file.insert_tag(lofty::tag::Tag::new(tag_type));
            tagged_file.primary_tag_mut().unwrap()
        }
    };

    // 基本信息
    tag.set_title(title.clone());
    tag.set_artist(artist.clone());
    tag.set_album(album.clone());

    // 歌词
    if let Some(lrc) = &lyrics_text {
        tag.insert(TagItem::new(ItemKey::Lyrics, ItemValue::Text(lrc.clone())));
    }

    // 封面图
    if let Some(data) = &cover_data {
        tag.remove_picture_type(PictureType::CoverFront);
        let mime = if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
            MimeType::Png
        } else {
            MimeType::Jpeg
        };
        let pic = Picture::new_unchecked(
            PictureType::CoverFront, Some(mime), None, data.clone(),
        );
        tag.push_picture(pic);
    }

    tag.save_to_path(path, WriteOptions::default())
        .map_err(|e| format!("写入标签失败: {}", e))?;

    // 更新歌曲库
    let mut library = load_library();
    if let Some(song) = library.songs.iter_mut().find(|s| s.file_path == file_path) {
        song.title = title;
        song.artist = artist;
        song.album = album;
    }
    save_library(&library)?;

    Ok(())
}

