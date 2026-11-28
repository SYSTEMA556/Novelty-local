//! Kotlin（moe.l4ph.novelty.Kanalizer）から呼ぶ入口。
//!
//! 英単語（a〜z だけ）を受け取り、推測したカタカナの読みを返す。
//! 推測が最後まで終わらなかったとき・失敗したときは空文字を返し、
//! Dart 側でアルファベットを1文字ずつ読む方へ回す。

use jni::JNIEnv;
use jni::objects::{JClass, JObjectArray, JString};
use jni::sys::jobjectArray;

fn convert_one(word: &str) -> String {
    let lower = word.to_ascii_lowercase();
    if lower.is_empty() || !lower.chars().all(|c| c.is_ascii_lowercase()) {
        return String::new();
    }
    // モデルの中で思わぬ失敗があってもアプリごと落とさない
    std::panic::catch_unwind(|| {
        kanalizer::convert(&lower)
            .with_error_on_incomplete(true)
            .perform()
            .unwrap_or_default()
    })
    .unwrap_or_default()
}

/// 単語の配列をまとめて変換する（呼び出しの往復を減らすため）。
#[unsafe(no_mangle)]
pub extern "system" fn Java_moe_l4ph_novelty_Kanalizer_convertAll<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    words: JObjectArray<'local>,
) -> jobjectArray {
    let result = (|| -> jni::errors::Result<jobjectArray> {
        let len = env.get_array_length(&words)?;
        let string_class = env.find_class("java/lang/String")?;
        let empty = env.new_string("")?;
        let out = env.new_object_array(len, &string_class, &empty)?;
        for i in 0..len {
            let item = env.get_object_array_element(&words, i)?;
            let word: String = env.get_string(&JString::from(item))?.into();
            let kana = env.new_string(convert_one(&word))?;
            env.set_object_array_element(&out, i, &kana)?;
            env.delete_local_ref(kana)?;
        }
        Ok(out.into_raw())
    })();
    result.unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::convert_one;

    #[test]
    fn converts_words() {
        assert_eq!(convert_one("kanalizer"), "カナライザー");
        assert_eq!(convert_one("Hello"), convert_one("hello"));
        assert_eq!(convert_one("e-mail"), "");
    }
}
