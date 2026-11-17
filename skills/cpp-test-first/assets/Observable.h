#pragma once
#include <functional>
#include <map>
#include <utility>

// 画面モデルの変更通知 (小さなクラス。MFC に依存しない。std::function だけ)。
//   - 画面モデルが、継承 (private でよい) して、状態を変えたあとに Raise(識別) を呼ぶ。識別は、画面ごとの列挙 (PropertyId) を int にしたもの。
//   - 複数の値を変える操作は、最後に「全体 (All)」を 1 回通知する (操作の途中の通知は、出てよい。ハンドラーは、通知のたびに状態を読み直す)。
//   - ダイアログは、OnInitDialog で AddHandler (戻り値の id を持つ)、OnDestroy で RemoveHandler する。
//   - スレッドセーフではない。画面モデルは、UI スレッドからだけ呼ぶ (別スレッドからの通知は、規約違反)。
class Observable
{
public:
    // ハンドラーを足す。戻り値の id は、RemoveHandler に渡す。
    int AddHandler(std::function<void(int)> handler)
    {
        const int id = ++m_lastId;
        m_handlers[id] = std::move(handler);
        return id;
    }

    void RemoveHandler(int id)
    {
        m_handlers.erase(id);
    }

protected:
    // 変わった識別を、すべてのハンドラーへ通知する。通知の途中で、ハンドラーを足し引きしても、壊れない (コピーを呼ぶ)。
    void Raise(int property)
    {
        const auto handlers = m_handlers;
        for (const auto& entry : handlers)
        {
            entry.second(property);
        }
    }

private:
    int m_lastId = 0;
    std::map<int, std::function<void(int)>> m_handlers;
};
