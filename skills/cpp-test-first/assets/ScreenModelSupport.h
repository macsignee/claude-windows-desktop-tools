#pragma once
#include <exception>
#include <string>
#include <utility>
#include <vector>

// 画面モデルの共通の型 (MFC に依存しない)。文字列は std::wstring (CString を、契約に出さない。MFC 側の境界で変換する)。

// 検査の誤り。properties = 対象の欄の一覧 (画面ごとの PropertyId の列挙を int にしたもの)。
// 空なら、欄に紐づかない画面全体の誤り。複数なら、複数の欄にまたがる誤り (先頭が、主たる欄)。
struct ValidationError
{
    std::vector<int> properties;
    std::wstring message;

    bool operator==(const ValidationError&) const = default;
};

// 検査の結果。誤りがなければ、空。誤りの並びは、検査の規則を書いた順。
using ValidationResult = std::vector<ValidationError>;

// リポジトリの失敗。GetText() は、ユーザー向けの文章 (GetMessage は、Windows のマクロ (GetMessageW) と衝突するので、使わない)。
// 本物のリポジトリが、データベース固有の例外を、これに変換して投げる。画面モデルは、この例外だけを、失敗 (Failure) にする。
class RepositoryException : public std::exception
{
public:
    explicit RepositoryException(std::wstring message)
        : m_message(std::move(message))
    {
    }

    const std::wstring& GetText() const
    {
        return m_message;
    }

private:
    std::wstring m_message;
};
